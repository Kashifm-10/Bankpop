import json
import logging
import secrets

from django.conf import settings
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.core.mail import EmailMultiAlternatives
from django.core.validators import validate_email
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

from . import config

logger = logging.getLogger(__name__)

MAX_SUBJECT_LENGTH = 200
MAX_BODY_LENGTH = 50_000


@require_GET
def health(request):
    """Liveness, and which account the service will send through.

    `source` is the useful half on a deploy: `supabase` means the app's
    email_settings row answered, `env` means the service fell back to its own
    environment variables (or was never given a Supabase project).
    """
    try:
        account = config.load()
    except config.MailConfigError as error:
        return JsonResponse({'status': 'misconfigured', 'error': str(error)}, status=503)
    return JsonResponse(
        {
            'status': 'ok',
            'provider': account.provider,
            'source': account.source,
        }
    )


def _client_ip(request):
    # The proxy in front of us appends the real client address last; earlier
    # entries are whatever the client chose to send.
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR', '')
    if forwarded:
        return forwarded.split(',')[-1].strip()
    return request.META.get('REMOTE_ADDR', 'unknown')


def _is_authorized(request):
    if not settings.MAIL_API_TOKEN:
        return False
    scheme, _, token = request.headers.get('Authorization', '').partition(' ')
    return scheme.lower() == 'bearer' and secrets.compare_digest(
        token.strip().encode(), settings.MAIL_API_TOKEN.encode()
    )


def _rate_limited(request):
    key = f'mail-rate:{_client_ip(request)}'
    cache.add(key, 0, timeout=settings.MAIL_RATE_WINDOW_SECONDS)
    try:
        count = cache.incr(key)
    except ValueError:  # expired between add() and incr()
        cache.set(key, 1, timeout=settings.MAIL_RATE_WINDOW_SECONDS)
        count = 1
    return count > settings.MAIL_RATE_LIMIT


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, list) and all(isinstance(v, str) for v in value):
        return value
    raise ValidationError('must be an email address or a list of them')


def _clean_addresses(value, field, errors, required=False):
    try:
        addresses = [a.strip() for a in _as_list(value) if a.strip()]
    except ValidationError as exc:
        errors[field] = exc.messages[0]
        return []
    if required and not addresses:
        errors[field] = 'at least one address is required'
        return []
    for address in addresses:
        try:
            validate_email(address)
        except ValidationError:
            errors[field] = f'invalid email address: {address}'
            return []
        domain = address.rsplit('@', 1)[1].lower()
        allowed = settings.MAIL_ALLOWED_RECIPIENT_DOMAINS
        if allowed and field != 'reply_to' and domain not in allowed:
            errors[field] = f'recipient domain not allowed: {domain}'
            return []
    return addresses


def _clean_payload(data):
    errors = {}
    to = _clean_addresses(data.get('to'), 'to', errors, required=True)
    cc = _clean_addresses(data.get('cc'), 'cc', errors)
    bcc = _clean_addresses(data.get('bcc'), 'bcc', errors)
    reply_to = _clean_addresses(data.get('reply_to'), 'reply_to', errors)

    if len(to) + len(cc) + len(bcc) > settings.MAIL_MAX_RECIPIENTS:
        errors['to'] = f'at most {settings.MAIL_MAX_RECIPIENTS} recipients in total'

    subject = data.get('subject')
    if not isinstance(subject, str) or not subject.strip():
        errors['subject'] = 'required'
    elif len(subject) > MAX_SUBJECT_LENGTH or '\n' in subject or '\r' in subject:
        errors['subject'] = f'must be one line of at most {MAX_SUBJECT_LENGTH} characters'

    text = data.get('text', '')
    html = data.get('html', '')
    if not isinstance(text, str) or not isinstance(html, str):
        errors['text'] = 'text and html must be strings'
    elif not text.strip() and not html.strip():
        errors['text'] = 'provide text, html or both'
    elif len(text) > MAX_BODY_LENGTH or len(html) > MAX_BODY_LENGTH:
        errors['text'] = f'body must be at most {MAX_BODY_LENGTH} characters'

    cleaned = {
        'to': to, 'cc': cc, 'bcc': bcc, 'reply_to': reply_to,
        'subject': subject, 'text': text, 'html': html,
    }
    return cleaned, errors


@csrf_exempt  # token-authenticated API, no cookies involved
@require_POST
def send_mail(request):
    if not _is_authorized(request):
        return JsonResponse({'error': 'unauthorized'}, status=401)

    try:
        data = json.loads(request.body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return JsonResponse({'error': 'body must be JSON'}, status=400)
    if not isinstance(data, dict):
        return JsonResponse({'error': 'body must be a JSON object'}, status=400)

    cleaned, errors = _clean_payload(data)
    if errors:
        return JsonResponse({'error': 'invalid request', 'fields': errors}, status=400)

    # The mailbox comes from the app's email_settings row, so it is read here,
    # per request, rather than once at boot.
    try:
        account = config.load()
        connection = account.connection()
    except config.MailConfigError as error:
        logger.error('Cannot send: %s', error)
        return JsonResponse({'error': str(error)}, status=503)

    if _rate_limited(request):
        return JsonResponse({'error': 'too many requests, try again later'}, status=429)

    message = EmailMultiAlternatives(
        subject=cleaned['subject'].strip(),
        # Plain-text part is required by most clients; fall back to a stub for HTML-only mail.
        body=cleaned['text'] or 'This message is best viewed in an HTML-capable email client.',
        from_email=account.from_email,
        to=cleaned['to'],
        cc=cleaned['cc'],
        bcc=cleaned['bcc'],
        reply_to=cleaned['reply_to'],
        connection=connection,
    )
    if cleaned['html']:
        message.attach_alternative(cleaned['html'], 'text/html')

    try:
        message.send()
    except Exception:
        logger.exception('Sending mail failed (%s)', account.describe())
        return JsonResponse({'error': 'the mail provider rejected the message'}, status=502)

    logger.info('Sent %r to %s (%s)', message.subject, message.to, account.describe())
    return JsonResponse({'sent': True, 'recipients': len(message.recipients())})
