"""The mail providers this service can send through.

Plain data, imported by both the settings module (to build the environment
fallback) and `mailer.config` (to build the account read from Supabase), so the
list of providers has one home.
"""

# Prints the message to the server log instead of sending it. The default.
CONSOLE_BACKEND = 'django.core.mail.backends.console.EmailBackend'

# Any SMTP server: Gmail, Zoho, a domain's own mail server.
SMTP_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'

# HTTP email services, through django-anymail. They work where SMTP ports are
# blocked. Each one is authenticated with a single API key.
ANYMAIL_BACKENDS = {
    'brevo': 'anymail.backends.brevo.EmailBackend',
    'resend': 'anymail.backends.resend.EmailBackend',
    'mailgun': 'anymail.backends.mailgun.EmailBackend',
    'postmark': 'anymail.backends.postmark.EmailBackend',
}

PROVIDERS = ('console', 'smtp', *ANYMAIL_BACKENDS)


def backend_for(provider):
    """The Django email backend a provider name means, or None if unknown."""
    if provider == 'console':
        return CONSOLE_BACKEND
    if provider == 'smtp':
        return SMTP_BACKEND
    return ANYMAIL_BACKENDS.get(provider)


def describe():
    """The provider names, for an error message."""
    return ', '.join(PROVIDERS)
