-- Where the app finds the Django mail service, kept in the database.
--
-- Run this in the Supabase SQL editor after supabase/email.sql and
-- supabase/mail_provider.sql. Safe to run more than once.
--
-- The app used to learn the service's address from the build
-- (--dart-define=MAIL_API_URL=...) or from a constant compiled in, so hosting
-- the service meant cutting a new build. This column moves that address into
-- the row the app already reads: the same email_settings row that holds the
-- mailbox and app_url now also says where the service lives.
--
-- How one build finds the service, in order:
--
--   * --dart-define=MAIL_API_URL=... wins, for a staging build;
--   * a page on localhost / 127.0.0.1 posts to http://127.0.0.1:8000, so
--     ./dev.sh and docker compose keep working with no setting at all;
--   * everywhere else - the deployed site, a phone - the app reads
--     mail_api_url from this table;
--   * if the row has no address, --dart-define=MAIL_API_HOSTED_URL=... is the
--     last fallback.
--
-- mail_api_url is a public address, not a secret, so it is exposed through
-- email_public_settings beside app_url. The mailbox columns stay readable only
-- with the service-role key.

begin;

alter table public.email_settings
  add column if not exists mail_api_url text;

comment on column public.email_settings.mail_api_url is
  'Public base URL of the django-mail-api service (e.g. https://mail.example). '
  'Empty means the app falls back to its build setting.';

-- The app reads the view, never the row. Appending a column is the one change
-- CREATE OR REPLACE VIEW allows, so the four columns it already had keep their
-- positions and mail_api_url arrives at the end.
create or replace view public.email_public_settings as
  select id, app_url, enabled, updated_at, mail_api_url
    from public.email_settings;

grant select on public.email_public_settings to anon, authenticated;

commit;

-- Fill it in once, after the Django service is deployed, then nothing has to be
-- rebuilt when the address changes:
--
--   update public.email_settings
--      set mail_api_url = 'https://mail.your-host.example'
--    where id = 1;
--
-- Check what the app will read (this view has no password):
--
--   select id, app_url, mail_api_url, enabled
--     from public.email_public_settings;
--
-- The address is used exactly as written, so no path: `https://mail.example`,
-- not `https://mail.example/api/`. The client appends `api/send-mail/` itself.
-- A trailing slash is harmless; the app strips it.
