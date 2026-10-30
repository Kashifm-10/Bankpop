-- The mailbox the mail service sends from, and who is allowed to read it.
--
-- Run this after email.sql. Safe to run more than once.
--
-- Where the mail goes changed: the app no longer opens an SMTP connection (a
-- browser cannot) and no longer posts to a Supabase edge function. It calls the
-- Django service in django-mail-api/, which reads this row over the Supabase
-- REST API with the *service-role* key and sends the message itself.
--
-- What that means for this table:
--
--   * The row now carries a provider too, so the service can be switched
--     between Gmail, Zoho, an HTTP email API or console output by editing the
--     row rather than redeploying anything.
--   * The parameters the service sends with, column by column:
--
--         provider       MAIL_PROVIDER         console|smtp|brevo|resend|mailgun|postmark
--         host           EMAIL_HOST            smtp.gmail.com
--         port           EMAIL_PORT            587 (STARTTLS) or 465 (SSL)
--         username       EMAIL_HOST_USER       you@gmail.com
--         password       EMAIL_HOST_PASSWORD   the 16-character Gmail App Password
--         from_email     DEFAULT_FROM_EMAIL    who the mail comes from
--         api_key        MAIL_API_KEY          HTTP providers only
--         sender_domain  MAILGUN_SENDER_DOMAIN  Mailgun only
--
--   * The app only ever needs app_url (for the verification link), so the
--     SMTP columns are taken away from it: reading the row with the app's
--     publishable key used to hand anybody the mailbox password. Django reads
--     the row with the service-role key, which is server-side only.
--
-- The service's own settings are still environment variables: MAIL_API_TOKEN,
-- the rate limit, CORS, DJANGO_SECRET_KEY.

begin;

-- ---------------------------------------------------------------------------
-- Provider columns
-- ---------------------------------------------------------------------------

-- The row written before this script is an SMTP account, which is what the app
-- sent from; `smtp` is therefore the default rather than `console`.
alter table if exists public.email_settings
  add column if not exists provider      text not null default 'smtp',
  add column if not exists from_email    text,
  add column if not exists api_key       text,
  add column if not exists sender_domain text,
  -- Where this service is reachable. Public, so the app reads it through the
  -- view below; see supabase/mail_api_url.sql for the migration that adds it
  -- to an existing project.
  add column if not exists mail_api_url  text;

-- A provider this service cannot use would be accepted here and then refused
-- at send time with a clear message; catching the typo at write time is nicer.
do $$
begin
  if to_regclass('public.email_settings') is null then
    raise notice 'email_settings does not exist yet - run supabase/email.sql first';
    return;
  end if;

  alter table public.email_settings
    drop constraint if exists email_settings_provider_check;
  execute $sql$
    alter table public.email_settings
      add constraint email_settings_provider_check
      check (provider in ('console', 'smtp', 'brevo', 'resend', 'mailgun', 'postmark'))
  $sql$;

  -- -------------------------------------------------------------------------
  -- What the app may read: the address of its own web build, and nothing else
  -- -------------------------------------------------------------------------

  execute $sql$
    create or replace view public.email_public_settings as
      select id, app_url, enabled, updated_at, mail_api_url
        from public.email_settings
  $sql$;

  -- The app reads the view with the publishable key...
  execute 'grant select on public.email_public_settings to anon, authenticated';

  -- ...and can no longer read the row itself, where the password sits.
  execute 'revoke select, insert, update, delete on public.email_settings from anon, authenticated';

  -- Belt and braces: with RLS on, a grant that comes back later still reads
  -- nothing. The service-role key bypasses this, and the view is owned by the
  -- role that owns the table, so both keep working.
  execute 'alter table public.email_settings enable row level security';
end $$;

comment on column public.email_settings.provider is
  'console | smtp | brevo | resend | mailgun | postmark; read by django-mail-api.';
comment on column public.email_settings.from_email is
  'The From: address. Empty means the service uses sender_name <username>.';
comment on column public.email_settings.api_key is
  'MAIL_API_KEY for the HTTP providers (brevo, resend, mailgun, postmark).';
comment on column public.email_settings.sender_domain is
  'Mailgun sender domain (Mailgun only).';
comment on column public.email_settings.mail_api_url is
  'Public base URL of the django-mail-api service (e.g. https://mail.example). '
  'Empty means the app falls back to its build setting.';
comment on view public.email_public_settings is
  'The two public columns the app needs: where its web build lives, and where the mail service lives.';

commit;

-- ---------------------------------------------------------------------------
-- Fill the row in once, in the SQL editor. Gmail needs 2-Step Verification and
-- an App Password (https://myaccount.google.com/apppasswords), not the account
-- password. Port 587 uses STARTTLS; 465 uses SSL (both work from a server, which
-- is the reason mail no longer has to go out through Supabase).
-- ---------------------------------------------------------------------------
--
-- update public.email_settings set
--   provider      = 'smtp',
--   host          = 'smtp.gmail.com',
--   port          = 587,
--   username      = 'you@gmail.com',
--   password      = 'your-16-char-app-password',
--   sender_name   = 'BankPop',
--   from_email    = 'you@gmail.com',
--   app_url       = 'https://your-app.example',
--   enabled       = true
-- where id = 1;
--
-- Check it without sending anything (password masked):
--
--   select id, provider, host, port, username, sender_name, from_email,
--          app_url, enabled, updated_at,
--          case when password = '' then 'empty' else 'set' end as password
--     from public.email_settings;
--
-- Then, from the service (django-mail-api/), which reads this row:
--
--   uv run python manage.py mail_config
--   curl http://127.0.0.1:8000/api/health/
