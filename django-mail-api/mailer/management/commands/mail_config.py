"""Prints the mail account this service will send through.

The account normally lives in the app's Supabase `email_settings` row, one
network hop away from the person setting it up. This command is how to check the
row without sending a message (and without printing the password):

    uv run python manage.py mail_config
"""

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from mailer import config


class Command(BaseCommand):
    help = 'Show the mail account the service sends through, password masked.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--refresh',
            action='store_true',
            help='Ignore the cached row and read Supabase again.',
        )

    def handle(self, *args, **options):
        try:
            account = config.load(force=options['refresh'])
        except config.MailConfigError as error:
            raise CommandError(f'The mail account cannot be used: {error}')

        self.stdout.write(f'Read from:   {account.where}')
        self.stdout.write(f'Provider:    {account.provider}')
        self.stdout.write(f'From:        {account.from_email}')
        if account.host:
            self.stdout.write(f'SMTP host:   {account.host}:{account.port}')
        if account.username:
            self.stdout.write(f'SMTP user:   {account.username}')
        if account.api_key:
            self.stdout.write('API key:     set')
        self.stdout.write(
            'Password:    ' + ('set' if account.password else 'empty (nothing to log in with)')
        )

        if account.source == config.SOURCE_ENV:
            if config._supabase_configured():
                self.stdout.write(
                    self.style.WARNING(
                        'Supabase could not answer, so the service fell back to its own '
                        'environment variables. Check the warning above, and '
                        'SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.'
                    )
                )
            else:
                self.stdout.write(
                    self.style.WARNING(
                        'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are not set, so the '
                        'account is read from this service\'s environment. Set both to '
                        'use the app\'s email_settings row.'
                    )
                )

        try:
            kwargs = account.connection_kwargs()
        except config.MailConfigError as error:
            raise CommandError(f'The mail account cannot be used: {error}')
        # No backend in the kwargs means "whatever Django's settings say", which
        # is the case for an account read from the environment.
        backend = kwargs.get('backend') or getattr(settings, 'EMAIL_BACKEND', '')
        self.stdout.write(f'Backend:     {backend}')
