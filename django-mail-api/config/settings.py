"""
Settings for the mail API.

Deploy-specific settings come from environment variables; see .env.example.

The one exception is the mail account itself: it lives in the app's Supabase
`email_settings` row, read at send time by mailer/config.py. The EMAIL_*
settings below are the fallback for a machine where Supabase is not configured
(or is unreachable), and the only source in a test run.
"""

import os
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv

from mailer.providers import ANYMAIL_BACKENDS

BASE_DIR = Path(__file__).resolve().parent.parent

# Local development reads .env; real environment variables win.
load_dotenv(BASE_DIR / '.env')


def env_list(name, default=''):
    return [item.strip() for item in os.environ.get(name, default).split(',') if item.strip()]


SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', 'django-insecure-dev-only-change-me')
DEBUG = os.environ.get('DJANGO_DEBUG', '0') == '1'
ALLOWED_HOSTS = env_list('DJANGO_ALLOWED_HOSTS', 'localhost,127.0.0.1,10.0.2.2,.wasmer.app')

INSTALLED_APPS = [
    'corsheaders',
    'anymail',
    'mailer',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'
APPEND_SLASH = False
WSGI_APPLICATION = 'config.wsgi.app'

# No models, so no database.
DATABASES = {}

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = False
USE_TZ = True

# Behind Wasmer/Render/etc. the TLS terminates at the proxy.
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

# --- CORS (needed for Flutter web; mobile apps ignore it) -------------------

CORS_ALLOWED_ORIGINS = env_list('CORS_ALLOWED_ORIGINS')
# `flutter run -d chrome` serves from a random localhost port.
CORS_ALLOWED_ORIGIN_REGEXES = env_list(
    'CORS_ALLOWED_ORIGIN_REGEXES', r'^http://localhost:\d+$,^http://127\.0\.0\.1:\d+$'
)
CORS_ALLOW_METHODS = ['POST', 'OPTIONS']
CORS_URLS_REGEX = r'^/api/.*$'

# --- Where the mail account comes from ---------------------------------------
#
# The account is read from the app's `email_settings` row through the Supabase
# REST API. Deploy once with these two set:
#
#   SUPABASE_URL=https://<project>.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY=<service-role key>
#
# The service-role key never leaves this server, and it is the reason the row
# no longer has to be readable by the app's publishable key.
SUPABASE_URL = os.environ.get('SUPABASE_URL', '').strip()
SUPABASE_SERVICE_ROLE_KEY = os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '').strip()
# The table the row lives in (supabase/mail_provider.sql).
MAIL_CONFIG_TABLE = os.environ.get('MAIL_CONFIG_TABLE', 'email_settings').strip()
# How long a read row is reused before Supabase is asked again. A rotated
# password therefore takes effect within this many seconds, without a restart.
MAIL_CONFIG_CACHE_SECONDS = int(os.environ.get('MAIL_CONFIG_CACHE_SECONDS', '60'))
MAIL_CONFIG_TIMEOUT_SECONDS = int(os.environ.get('MAIL_CONFIG_TIMEOUT_SECONDS', '10'))

# --- Email (the fallback) ----------------------------------------------------
#
# MAIL_PROVIDER picks how mail leaves the server:
#   console  - print to stdout (default; nothing is sent)
#   smtp     - any SMTP server (Gmail, Zoho, your domain's server)
#   brevo / resend / mailgun / postmark
#            - an HTTP email API via django-anymail (works where SMTP ports are blocked)

# Provider -> the anymail setting that holds its key.
ANYMAIL_PROVIDERS = {
    'brevo': 'BREVO_API_KEY',
    'resend': 'RESEND_API_KEY',
    'mailgun': 'MAILGUN_API_KEY',
    'postmark': 'POSTMARK_SERVER_TOKEN',
}

MAIL_PROVIDER = os.environ.get('MAIL_PROVIDER', 'console').strip().lower()

if MAIL_PROVIDER == 'console':
    EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'
elif MAIL_PROVIDER == 'smtp':
    EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
    EMAIL_HOST = os.environ.get('EMAIL_HOST', '')
    EMAIL_PORT = int(os.environ.get('EMAIL_PORT', '587'))
    EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER', '')
    EMAIL_HOST_PASSWORD = os.environ.get('EMAIL_HOST_PASSWORD', '')
    # Port 465 is implicit TLS; everything else uses STARTTLS.
    EMAIL_USE_SSL = EMAIL_PORT == 465
    EMAIL_USE_TLS = not EMAIL_USE_SSL
    EMAIL_TIMEOUT = 20
elif MAIL_PROVIDER in ANYMAIL_BACKENDS:
    EMAIL_BACKEND = ANYMAIL_BACKENDS[MAIL_PROVIDER]
    ANYMAIL = {ANYMAIL_PROVIDERS[MAIL_PROVIDER]: os.environ.get('MAIL_API_KEY', '')}
    if MAIL_PROVIDER == 'mailgun':
        ANYMAIL['MAILGUN_SENDER_DOMAIN'] = os.environ.get('MAILGUN_SENDER_DOMAIN', '')
        # EU-region Mailgun accounts use https://api.eu.mailgun.net/v3
        ANYMAIL['MAILGUN_API_URL'] = os.environ.get('MAILGUN_API_URL', 'https://api.mailgun.net/v3')
else:
    raise ImproperlyConfigured(
        f'Unknown MAIL_PROVIDER {MAIL_PROVIDER!r}; use console, smtp or one of '
        + ', '.join(sorted(ANYMAIL_BACKENDS))
    )

# Mail always goes out from this address; clients cannot change it.
DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', 'webmaster@localhost')

# --- Mail API ----------------------------------------------------------------

# Shared secret clients send as "Authorization: Bearer <token>". Requests are
# refused until it is set.
MAIL_API_TOKEN = os.environ.get('MAIL_API_TOKEN', '')
# Empty means any recipient domain is accepted.
MAIL_ALLOWED_RECIPIENT_DOMAINS = [d.lower() for d in env_list('MAIL_ALLOWED_RECIPIENT_DOMAINS')]
MAIL_MAX_RECIPIENTS = int(os.environ.get('MAIL_MAX_RECIPIENTS', '5'))
# Sends allowed per client IP per window.
MAIL_RATE_LIMIT = int(os.environ.get('MAIL_RATE_LIMIT', '10'))
MAIL_RATE_WINDOW_SECONDS = int(os.environ.get('MAIL_RATE_WINDOW_SECONDS', '3600'))

# Per-process memory cache backs the rate limiter.
CACHES = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {'console': {'class': 'logging.StreamHandler'}},
    'root': {'handlers': ['console'], 'level': 'INFO'},
}
