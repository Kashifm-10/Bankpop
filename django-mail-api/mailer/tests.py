import io
import json
import urllib.error
from unittest import mock

from django.core import mail
from django.core.cache import cache
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase, override_settings

from mailer import config

TOKEN = 'test-token'

# A row as supabase/mail_provider.sql writes one.
ROW = {
    'id': 1,
    'enabled': True,
    'provider': 'smtp',
    'host': 'smtp.gmail.com',
    'port': 587,
    'username': 'bankpop@gmail.com',
    'password': 'sixteen-char-app-password',
    'sender_name': 'BankPop',
    'from_email': '',
    'app_url': 'https://bankpop.example',
}

SUPABASE = dict(
    SUPABASE_URL='https://project.supabase.co',
    SUPABASE_SERVICE_ROLE_KEY='service-role-key',
    MAIL_CONFIG_TABLE='email_settings',
    MAIL_CONFIG_CACHE_SECONDS=60,
)


class _Response:
    """Enough of an http.client.HTTPResponse for the loader."""

    def __init__(self, payload):
        self._payload = payload

    def read(self):
        return self._payload

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def setUpModule():
    """No test may touch the network.

    A developer's .env holds a real Supabase project and a real mailbox, so
    without this the suite would read that row and try to send through Gmail.
    Classes that want a Supabase row set their own URL on top of this and stub
    the request, so this only removes the accident.
    """
    global _offline
    _offline = override_settings(SUPABASE_URL='', SUPABASE_SERVICE_ROLE_KEY='')
    _offline.enable()


def tearDownModule():
    _offline.disable()


_offline = None


def _stub(rows):
    """A urlopen replacement serving `rows`, plus the requests it was asked."""
    payload = json.dumps(rows).encode('utf-8')
    calls = []

    def urlopen(request, timeout=None):
        calls.append(request)
        return _Response(payload)

    return urlopen, calls


@override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
    MAIL_API_TOKEN=TOKEN,
    DEFAULT_FROM_EMAIL='App <noreply@example.com>',
    MAIL_ALLOWED_RECIPIENT_DOMAINS=[],
    MAIL_MAX_RECIPIENTS=5,
    MAIL_RATE_LIMIT=3,
)
class SendMailTests(SimpleTestCase):
    url = '/api/send-mail/'

    def setUp(self):
        cache.clear()
        config.clear_cache()

    def post(self, payload, token=TOKEN, **extra):
        headers = {'Authorization': f'Bearer {token}'} if token else {}
        return self.client.post(
            self.url, json.dumps(payload), content_type='application/json', headers=headers, **extra
        )

    def valid(self, **overrides):
        return {'to': 'alice@example.com', 'subject': 'Hi', 'text': 'Hello', **overrides}

    def test_sends_text_and_html(self):
        response = self.post(self.valid(html='<b>Hello</b>', reply_to='bob@example.org'))
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json(), {'sent': True, 'recipients': 1})
        [sent] = mail.outbox
        self.assertEqual(sent.from_email, 'App <noreply@example.com>')
        self.assertEqual(sent.to, ['alice@example.com'])
        self.assertEqual(sent.reply_to, ['bob@example.org'])
        self.assertEqual(sent.alternatives[0].content, '<b>Hello</b>')

    def test_client_cannot_set_from_address(self):
        self.post(self.valid(from_email='ceo@bank.com'))
        self.assertEqual(mail.outbox[0].from_email, 'App <noreply@example.com>')

    def test_requires_token(self):
        self.assertEqual(self.post(self.valid(), token=None).status_code, 401)
        self.assertEqual(self.post(self.valid(), token='wrong').status_code, 401)
        self.assertEqual(mail.outbox, [])

    @override_settings(MAIL_API_TOKEN='')
    def test_refuses_everything_when_token_unset(self):
        self.assertEqual(self.post(self.valid(), token='').status_code, 401)

    @override_settings(DEBUG=True)
    def test_a_local_build_sends_without_a_token_in_debug(self):
        """A web build served from localhost carries no token; DEBUG accepts it.

        The test client's peer is 127.0.0.1, which is the phone-side of the
        same case: `flutter run` on this computer posting to the service on
        this computer.
        """
        response = self.post(self.valid(), token=None, REMOTE_ADDR='127.0.0.1')
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(len(mail.outbox), 1)

    @override_settings(DEBUG=True)
    def test_a_local_build_with_an_empty_token_still_sends_in_debug(self):
        # The app sends `Authorization: Bearer ` when the build had no token.
        response = self.post(self.valid(), token='', REMOTE_ADDR='127.0.0.1')
        self.assertEqual(response.status_code, 200, response.content)

    @override_settings(DEBUG=True)
    def test_another_machine_still_needs_the_token_in_debug(self):
        response = self.post(self.valid(), token=None, REMOTE_ADDR='203.0.113.7')
        self.assertEqual(response.status_code, 401)

    @override_settings(DEBUG=True)
    def test_a_forwarded_loopback_address_does_not_authorize(self):
        response = self.post(
            self.valid(), token=None, REMOTE_ADDR='203.0.113.7',
            HTTP_X_FORWARDED_FOR='127.0.0.1',
        )
        self.assertEqual(response.status_code, 401)

    def test_a_local_build_still_needs_the_token_without_debug(self):
        # DEBUG off is a deployed service, where the token is the only gate.
        response = self.post(self.valid(), token=None, REMOTE_ADDR='127.0.0.1')
        self.assertEqual(response.status_code, 401)

    def test_rejects_get(self):
        response = self.client.get(self.url, headers={'Authorization': f'Bearer {TOKEN}'})
        self.assertEqual(response.status_code, 405)

    def test_validation_errors(self):
        response = self.post({'to': 'not-an-email', 'subject': 'a\nBcc: x@y.com'})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(set(response.json()['fields']), {'to', 'subject', 'text'})
        self.assertEqual(mail.outbox, [])

    def test_bad_json(self):
        response = self.client.post(
            self.url, 'nope', content_type='application/json',
            headers={'Authorization': f'Bearer {TOKEN}'},
        )
        self.assertEqual(response.status_code, 400)

    def test_recipient_cap(self):
        response = self.post(self.valid(to=[f'u{i}@example.com' for i in range(6)]))
        self.assertEqual(response.status_code, 400)

    @override_settings(MAIL_ALLOWED_RECIPIENT_DOMAINS=['example.com'])
    def test_recipient_domain_allowlist(self):
        self.assertEqual(self.post(self.valid(to='x@other.com')).status_code, 400)
        self.assertEqual(self.post(self.valid(bcc='x@other.com')).status_code, 400)
        self.assertEqual(self.post(self.valid(to='x@EXAMPLE.com')).status_code, 200)

    def test_rate_limit_per_ip(self):
        for _ in range(3):
            self.assertEqual(self.post(self.valid()).status_code, 200)
        self.assertEqual(self.post(self.valid()).status_code, 429)
        other = self.post(self.valid(), HTTP_X_FORWARDED_FOR='10.0.0.9')
        self.assertEqual(other.status_code, 200)

    def test_provider_failure_returns_502(self):
        with override_settings(EMAIL_BACKEND='mailer.tests.FailingBackend'):
            response = self.post(self.valid())
        self.assertEqual(response.status_code, 502)

    def test_cors_preflight_for_flutter_web(self):
        response = self.client.options(
            self.url,
            headers={
                'Origin': 'http://localhost:53211',
                'Access-Control-Request-Method': 'POST',
                'Access-Control-Request-Headers': 'authorization,content-type',
            },
        )
        self.assertEqual(response['Access-Control-Allow-Origin'], 'http://localhost:53211')

    def test_health(self):
        self.assertEqual(self.client.get('/api/health/').json()['status'], 'ok')


class FailingBackend:
    def __init__(self, *args, **kwargs):
        pass

    def send_messages(self, messages):
        raise ConnectionRefusedError('smtp down')


@override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend', MAIL_API_TOKEN=TOKEN
)
class UrlTests(SimpleTestCase):
    def setUp(self):
        cache.clear()
        config.clear_cache()

    def test_send_without_trailing_slash(self):
        cache.clear()
        response = self.client.post(
            '/api/send-mail',
            json.dumps({'to': 'a@example.com', 'subject': 'Hi', 'text': 'x'}),
            content_type='application/json',
            headers={'Authorization': f'Bearer {TOKEN}'},
        )
        self.assertEqual(response.status_code, 200)


@override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
    DEFAULT_FROM_EMAIL='env@localhost',
)
class MailConfigRowTests(SimpleTestCase):
    """The email_settings row is the account the service sends with."""

    def setUp(self):
        config.clear_cache()

    def kwargs(self, **overrides):
        return config.from_row({**ROW, **overrides}).connection_kwargs()

    def test_smtp_row_sets_host_port_user_and_password(self):
        kwargs = self.kwargs()
        self.assertEqual(kwargs['backend'], 'django.core.mail.backends.smtp.EmailBackend')
        self.assertEqual(kwargs['host'], 'smtp.gmail.com')
        self.assertEqual(kwargs['port'], 587)
        self.assertEqual(kwargs['username'], 'bankpop@gmail.com')
        self.assertEqual(kwargs['password'], 'sixteen-char-app-password')
        # 587 is STARTTLS; only 465 is implicit TLS. Both flags are always set:
        # Django reads whichever is missing from the environment.
        self.assertTrue(kwargs['use_tls'])
        self.assertFalse(kwargs['use_ssl'])

    def test_port_465_uses_ssl_instead(self):
        kwargs = self.kwargs(port=465)
        self.assertTrue(kwargs['use_ssl'])
        self.assertFalse(kwargs['use_tls'])

    def test_a_465_row_is_not_dragged_back_to_the_environment_starttls(self):
        # The environment is 587/STARTTLS. A row on 465 used to pass only
        # use_ssl, inherit EMAIL_USE_TLS from the environment, and make Django
        # raise "EMAIL_USE_TLS/EMAIL_USE_SSL are mutually exclusive" at send
        # time - a 500 with a dimmed screen behind it on the app side.
        with override_settings(EMAIL_USE_TLS=True, EMAIL_USE_SSL=False):
            connection = config.from_row({**ROW, 'port': 465}).connection()
        self.assertTrue(connection.use_ssl)
        self.assertFalse(connection.use_tls)

    def test_from_email_is_the_username_with_the_sender_name(self):
        self.assertEqual(config.from_row(ROW).from_email, 'BankPop <bankpop@gmail.com>')

    def test_from_email_column_wins_when_it_is_filled_in(self):
        account = config.from_row({**ROW, 'from_email': 'Bankpop <noreply@bankpop.example>'})
        self.assertEqual(account.from_email, 'Bankpop <noreply@bankpop.example>')

    def test_a_row_written_before_the_provider_column_is_smtp(self):
        row = {key: value for key, value in ROW.items() if key != 'provider'}
        self.assertEqual(config.from_row(row).provider, 'smtp')

    def test_console_row_needs_no_mailbox(self):
        account = config.from_row({'provider': 'console', 'from_email': 'a@example.com'})
        self.assertEqual(account.connection_kwargs(), {'backend': config.CONSOLE_BACKEND})

    def test_anymail_row_carries_its_api_key(self):
        account = config.from_row(
            {'provider': 'brevo', 'from_email': 'a@example.com', 'api_key': 'key-123'}
        )
        kwargs = account.connection_kwargs()
        self.assertEqual(kwargs['backend'], 'anymail.backends.brevo.EmailBackend')
        self.assertEqual(kwargs['api_key'], 'key-123')

    def test_smtp_row_without_a_password_is_refused(self):
        with self.assertRaises(config.MailConfigError):
            self.kwargs(password='')

    def test_unknown_provider_is_refused(self):
        with self.assertRaises(config.MailConfigError):
            config.from_row({**ROW, 'provider': 'sendgrid'})

    def test_row_with_nothing_to_send_from_is_refused(self):
        with self.assertRaises(config.MailConfigError):
            config.from_row({'username': '', 'from_email': '', 'port': 587})

    def test_describe_never_shows_the_password(self):
        described = config.from_row(ROW).describe()
        self.assertIn('smtp.gmail.com:587', described)
        self.assertIn('password=set', described)
        self.assertNotIn('sixteen-char-app-password', described)


@override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
    DEFAULT_FROM_EMAIL='env@localhost',
)
class MailConfigSourceTests(SimpleTestCase):
    """Supabase answers first; the environment answers when it cannot."""

    def setUp(self):
        config.clear_cache()

    def load(self, rows=None, error=None, **overrides):
        stub, calls = _stub([ROW] if rows is None else rows)
        with override_settings(**{**SUPABASE, **overrides}):
            with mock.patch('mailer.config.urllib.request.urlopen', side_effect=error or stub):
                return config.load(), calls

    def test_the_supabase_row_is_used(self):
        account, calls = self.load()
        self.assertEqual(account.source, 'supabase')
        self.assertEqual(account.host, 'smtp.gmail.com')
        self.assertEqual(account.from_email, 'BankPop <bankpop@gmail.com>')
        self.assertEqual(account.where, 'the email_settings row')

        request = calls[0]
        self.assertIn('/rest/v1/email_settings?', request.full_url)
        self.assertIn('enabled=eq.true', request.full_url)
        self.assertEqual(request.headers['Apikey'], 'service-role-key')
        self.assertEqual(request.headers['Authorization'], 'Bearer service-role-key')

    def test_the_row_is_reused_until_it_is_asked_for_again(self):
        stub, calls = _stub([ROW])
        with override_settings(**SUPABASE):
            with mock.patch('mailer.config.urllib.request.urlopen', side_effect=stub):
                config.load()
                config.load()
                self.assertEqual(len(calls), 1)
                config.load(force=True)
                self.assertEqual(len(calls), 2)
                config.clear_cache()
                config.load()
                self.assertEqual(len(calls), 3)

    def test_an_unreachable_supabase_falls_back_to_the_environment(self):
        account, _ = self.load(error=urllib.error.URLError('no route to host'))
        self.assertEqual(account.source, 'env')
        self.assertEqual(account.from_email, 'env@localhost')
        self.assertEqual(account.connection_kwargs(), {})

    def test_a_missing_table_falls_back_to_the_environment(self):
        error = urllib.error.HTTPError(
            'https://project.supabase.co',
            404,
            'Not Found',
            None,
            io.BytesIO(b'{"message":"relation does not exist"}'),
        )
        account, _ = self.load(error=error)
        self.assertEqual(account.source, 'env')

    def test_no_enabled_row_falls_back_to_the_environment(self):
        account, _ = self.load(rows=[])
        self.assertEqual(account.source, 'env')

    def test_a_broken_row_is_not_papered_over(self):
        with self.assertRaises(config.MailConfigError):
            self.load(rows=[{**ROW, 'provider': 'sendgrid'}])

    def test_without_supabase_settings_the_environment_answers(self):
        with mock.patch('mailer.config.urllib.request.urlopen') as urlopen:
            with override_settings(SUPABASE_URL='', SUPABASE_SERVICE_ROLE_KEY=''):
                account = config.load()
        self.assertEqual(account.source, 'env')
        urlopen.assert_not_called()

    def test_health_names_the_source(self):
        stub, _ = _stub([{**ROW, 'provider': 'console'}])
        with override_settings(**SUPABASE):
            with mock.patch('mailer.config.urllib.request.urlopen', side_effect=stub):
                body = self.client.get('/api/health/').json()
        self.assertEqual(body, {'status': 'ok', 'provider': 'console', 'source': 'supabase'})

    def test_health_reports_a_broken_row(self):
        stub, _ = _stub([{**ROW, 'provider': 'sendgrid'}])
        with override_settings(**SUPABASE):
            with mock.patch('mailer.config.urllib.request.urlopen', side_effect=stub):
                response = self.client.get('/api/health/')
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()['status'], 'misconfigured')


@override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
    MAIL_API_TOKEN=TOKEN,
    DEFAULT_FROM_EMAIL='webmaster@localhost',
    MAIL_ALLOWED_RECIPIENT_DOMAINS=[],
    MAIL_MAX_RECIPIENTS=5,
    MAIL_RATE_LIMIT=10,
    **SUPABASE,
)
class SendMailWithRowTests(SimpleTestCase):
    """A message leaves through the row's mailbox, not the service's own."""

    def setUp(self):
        cache.clear()
        config.clear_cache()

    def test_the_row_decides_the_from_address(self):
        row = {**ROW, 'from_email': 'BankPop <noreply@bankpop.example>'}
        stub, _ = _stub([row])
        local = mail.get_connection('django.core.mail.backends.locmem.EmailBackend')
        with mock.patch('mailer.config.MailConfig.connection', return_value=local):
            with mock.patch('mailer.config.urllib.request.urlopen', side_effect=stub):
                response = self.client.post(
                    '/api/send-mail/',
                    json.dumps({'to': 'alice@example.com', 'subject': 'Hi', 'text': 'Hello'}),
                    content_type='application/json',
                    headers={'Authorization': f'Bearer {TOKEN}'},
                )
        self.assertEqual(response.status_code, 200, response.content)
        [sent] = mail.outbox
        self.assertEqual(sent.from_email, 'BankPop <noreply@bankpop.example>')
        self.assertEqual(sent.to, ['alice@example.com'])


class MailConfigCommandTests(SimpleTestCase):
    """manage.py mail_config: check the account without sending anything."""

    def setUp(self):
        config.clear_cache()

    def test_it_prints_the_environment_account_without_the_password(self):
        out = io.StringIO()
        with override_settings(
            SUPABASE_URL='',
            SUPABASE_SERVICE_ROLE_KEY='',
            MAIL_PROVIDER='smtp',
            EMAIL_BACKEND='django.core.mail.backends.smtp.EmailBackend',
            EMAIL_HOST='smtp.gmail.com',
            EMAIL_PORT=587,
            EMAIL_HOST_USER='bankpop@gmail.com',
            EMAIL_HOST_PASSWORD='sixteen-char-app-password',
            DEFAULT_FROM_EMAIL='bankpop@gmail.com',
        ):
            call_command('mail_config', stdout=out)

        text = out.getvalue()
        self.assertIn('Read from:   the environment', text)
        self.assertIn('Password:    set', text)
        self.assertIn('smtp.gmail.com:587', text)
        self.assertNotIn('sixteen-char-app-password', text)

    def test_it_refuses_a_row_that_cannot_send(self):
        stub, _ = _stub([{**ROW, 'password': ''}])
        with override_settings(**SUPABASE):
            with mock.patch('mailer.config.urllib.request.urlopen', side_effect=stub):
                with self.assertRaises(CommandError):
                    call_command('mail_config', stdout=io.StringIO())
