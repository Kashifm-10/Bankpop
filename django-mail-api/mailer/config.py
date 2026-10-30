"""The mail account the service sends through.

The mailbox belongs to the app, not to this service. It lives in the app's
`email_settings` row in Supabase (see supabase/mail_provider.sql), so replacing
the mailbox or rotating a Gmail app password is a row update rather than a
redeploy:

    host / port / username / password   the SMTP account (provider 'smtp')
    provider                            console, smtp, brevo, resend, mailgun, postmark
    from_email                          the From: address (DEFAULT_FROM_EMAIL)
    api_key                             HTTP providers only

It is read over the Supabase REST API with a service-role key, which is the only
secret this service holds:

    SUPABASE_URL=https://<project>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY=<service-role key>

The row is cached for MAIL_CONFIG_CACHE_SECONDS (60 by default), so a busy table
does not become a busy database, and a rotated password takes effect within the
minute without a restart.

The environment is the fallback: it is used when Supabase is not configured or
cannot be reached (a warning is logged), and it is the only source in a test run.
Which of the two answered is in every message's log line, in `/api/health/`, and
in `manage.py mail_config`.
"""

from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

from django.conf import settings
from django.core.mail import get_connection
from django.core.mail.backends.base import BaseEmailBackend

from .providers import ANYMAIL_BACKENDS, CONSOLE_BACKEND, SMTP_BACKEND, backend_for, describe

logger = logging.getLogger(__name__)

# Which of the two places this configuration came from.
SOURCE_SUPABASE = 'supabase'
SOURCE_ENV = 'env'

# Port 465 is implicit TLS; anything else (587, 25) uses STARTTLS.
SSL_PORT = 465


class MailConfigError(Exception):
    """The mail account is configured, but not completely enough to send with.

    Raised for a row that exists and cannot be used - a missing password, an
    unknown provider. The API answers 503 rather than quietly sending from
    somewhere else, because the From: address is what the recipient trusts.
    """


@dataclass(frozen=True)
class MailConfig:
    """One mail account, and where it was read from."""

    provider: str
    from_email: str
    source: str = SOURCE_ENV
    host: str = ''
    port: int = 0
    username: str = ''
    password: str = ''
    api_key: str = ''
    sender_domain: str = ''

    @property
    def where(self) -> str:
        """The place this account was read from, for logs and the status command."""
        return (
            'the email_settings row'
            if self.source == SOURCE_SUPABASE
            else 'the environment'
        )

    def connection_kwargs(self) -> dict:
        """Keyword arguments for the Django backend, or {} for Django's settings.

        An environment configuration answers {} on purpose: `EMAIL_BACKEND` and
        the `EMAIL_*` settings already carry it, and `override_settings()` in a
        test has to keep working. Anything else is passed explicitly, because the
        account was chosen at request time rather than at boot.
        """
        if self.source == SOURCE_ENV:
            return {}
        if self.provider == 'console':
            return {'backend': CONSOLE_BACKEND}
        if self.provider == 'smtp':
            if not (self.host and self.username and self.password):
                raise MailConfigError(
                    'provider is smtp, so email_settings needs host, username and '
                    'password (a Gmail App Password, not the account password).'
                )
            return {
                'backend': SMTP_BACKEND,
                'host': self.host,
                'port': self.port,
                'username': self.username,
                'password': self.password,
                'timeout': getattr(settings, 'EMAIL_TIMEOUT', 20),
                # Both flags, always. Django fills whichever one is left out
                # from EMAIL_USE_TLS / EMAIL_USE_SSL, so a row on 465 (implicit
                # TLS) would inherit the environment's STARTTLS flag and the
                # backend would refuse the pair with "EMAIL_USE_TLS/
                # EMAIL_USE_SSL are mutually exclusive".
                'use_ssl': self.port == SSL_PORT,
                'use_tls': self.port != SSL_PORT,
            }
        if self.provider in ANYMAIL_BACKENDS:
            if not self.api_key:
                raise MailConfigError(
                    f'provider is {self.provider}, so email_settings needs api_key.'
                )
            kwargs = {
                'backend': ANYMAIL_BACKENDS[self.provider],
                'api_key': self.api_key,
            }
            if self.provider == 'mailgun':
                kwargs['sender_domain'] = self.sender_domain or getattr(
                    settings, 'MAILGUN_SENDER_DOMAIN', ''
                )
            return kwargs
        raise MailConfigError(
            f'Unknown provider {self.provider!r}; use {describe()}.'
        )

    def connection(self) -> BaseEmailBackend:
        """An email connection for this account."""
        return get_connection(**self.connection_kwargs())

    def describe(self) -> str:
        """The account as one log line, without the password."""
        parts = [
            f'provider={self.provider}',
            f'from={self.from_email}',
            f'source={self.source}',
        ]
        if self.host:
            parts.append(f'host={self.host}:{self.port}')
        if self.username:
            parts.append(f'user={self.username}')
        parts.append('password=set' if self.password else 'password=empty')
        return ' '.join(parts)


@dataclass
class _Cache:
    """The last row read, and when."""

    config: MailConfig | None = None
    read_at: float = field(default=0.0)


_cache = _Cache()


def clear_cache() -> None:
    """Forget the cached row: the next load() reads Supabase again."""
    _cache.config = None
    _cache.read_at = 0.0


def load(force: bool = False) -> MailConfig:
    """The account to send with: the Supabase row, or the environment.

    Raises [MailConfigError] only for a row that is present and unusable. A
    Supabase that cannot be reached, has no row, or a project where the scripts
    have not been run falls back to the environment with a warning, so a
    half-finished setup still tells you what is wrong instead of refusing to
    boot.
    """
    now = time.monotonic()
    if not force and _cache.config is not None:
        if now - _cache.read_at < getattr(settings, 'MAIL_CONFIG_CACHE_SECONDS', 60):
            return _cache.config

    config = _read_supabase() if _supabase_configured() else None
    if config is None:
        config = from_env()
    else:
        logger.info('Sending mail with the account in %s', config.where)

    _cache.config = config
    _cache.read_at = now
    return config


def from_env() -> MailConfig:
    """The account in the service's own environment.

    `EMAIL_BACKEND`, `EMAIL_HOST`, `ANYMAIL` and friends are already built from
    the environment by config/settings.py, and sending leaves them to Django
    (see [connection_kwargs]). They are read here as well so that
    `manage.py mail_config` and `/api/health/` describe the account that will
    really be used, rather than an empty one.
    """
    provider = getattr(settings, 'MAIL_PROVIDER', 'console')
    return MailConfig(
        provider=provider,
        from_email=settings.DEFAULT_FROM_EMAIL,
        source=SOURCE_ENV,
        host=getattr(settings, 'EMAIL_HOST', ''),
        port=_as_port(getattr(settings, 'EMAIL_PORT', 0)),
        username=getattr(settings, 'EMAIL_HOST_USER', ''),
        password=getattr(settings, 'EMAIL_HOST_PASSWORD', ''),
        api_key=_env_api_key(provider),
        sender_domain=getattr(settings, 'MAILGUN_SENDER_DOMAIN', ''),
    )


def _env_api_key(provider: str) -> str:
    """The environment's API key for an HTTP provider, if it has one."""
    setting = getattr(settings, 'ANYMAIL_PROVIDERS', {}).get(provider)
    if not setting:
        return ''
    return (getattr(settings, 'ANYMAIL', {}) or {}).get(setting, '')


def from_row(row: dict) -> MailConfig:
    """The account in one `email_settings` row.

    Raises [MailConfigError] when the row cannot send mail. A row written before
    the provider column existed is an SMTP account, which is what the app had
    before the mail service took over.
    """
    username = str(row.get('username') or '').strip()
    sender_name = str(row.get('sender_name') or '').strip()
    from_email = str(row.get('from_email') or '').strip()

    if not from_email and username:
        # Gmail and most providers reject a From: that is not the authenticated
        # account, so the address wins over a display name.
        from_email = f'{sender_name} <{username}>' if sender_name else username

    config = MailConfig(
        provider=str(row.get('provider') or 'smtp').strip().lower(),
        from_email=from_email,
        source=SOURCE_SUPABASE,
        host=str(row.get('host') or '').strip(),
        port=_as_port(row.get('port')),
        username=username,
        password=str(row.get('password') or ''),
        api_key=str(row.get('api_key') or '').strip(),
        sender_domain=str(row.get('sender_domain') or '').strip(),
    )

    if not config.from_email:
        raise MailConfigError(
            'The email_settings row has no from_email and no username to send '
            'from, so every message would be rejected by the provider.'
        )
    if backend_for(config.provider) is None:
        raise MailConfigError(
            f'The email_settings row says provider={config.provider!r}; '
            f'use {describe()}.'
        )
    return config


def _as_port(value) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _supabase_configured() -> bool:
    return bool(
        getattr(settings, 'SUPABASE_URL', '') and getattr(settings, 'SUPABASE_SERVICE_ROLE_KEY', '')
    )


def _read_supabase() -> MailConfig | None:
    """Read the row, or None when Supabase cannot answer.

    [MailConfigError] travels out untouched: it means the row itself is wrong,
    and falling back to a different mailbox would be worse than failing.
    """
    table = getattr(settings, 'MAIL_CONFIG_TABLE', 'email_settings')
    url = f'{settings.SUPABASE_URL.rstrip("/")}/rest/v1/{table}?' + urllib.parse.urlencode(
        {
            'select': '*',
            'enabled': 'eq.true',
            'order': 'updated_at.desc',
            'limit': 1,
        }
    )
    request = urllib.request.Request(
        url,
        headers={
            # PostgREST wants both; the service-role key is what lifts the row's
            # protection from the app's own publishable key.
            'apikey': settings.SUPABASE_SERVICE_ROLE_KEY,
            'Authorization': f'Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}',
            'Accept': 'application/json',
        },
    )

    try:
        with urllib.request.urlopen(
            request, timeout=getattr(settings, 'MAIL_CONFIG_TIMEOUT_SECONDS', 10)
        ) as response:
            rows = json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as error:
        # 404 is the ordinary "supabase/mail_provider.sql has not been run".
        try:
            detail = error.read().decode('utf-8', 'replace').strip()[:200]
        except Exception:  # a proxy that closed the body, or a bare test stub
            detail = ''
        logger.warning(
            'Could not read %s from Supabase (HTTP %s: %s); using the environment instead',
            table,
            error.code,
            detail,
        )
        return None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as error:
        logger.warning(
            'Could not reach Supabase to read %s (%s); using the environment instead',
            table,
            error,
        )
        return None

    if not isinstance(rows, list) or not rows:
        logger.warning(
            'Supabase has no enabled row in %s; using the environment instead', table
        )
        return None
    return from_row(rows[0])
