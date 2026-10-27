-- Verification, forgotten passwords, and the mailbox the mail is sent from.
--
-- Run this in the Supabase SQL editor after accounts.sql, then
-- supabase/mail_provider.sql - the one the mail service reads. Safe to run more
-- than once: every statement checks first.
--
-- What changes:
--   * players_profile.verified          - false until the link in the mail is opened
--   * players_profile.reset_password_*  - the temporary password, stored hashed,
--                                         kept apart from the real password
--   * email_tokens                      - one row per verification link
--   * email_settings                    - the mailbox: host, port, username,
--                                         password, and the provider
--
-- The app does not send mail itself any more. The service in django-mail-api/
-- reads this row with the service-role key and sends the message, and
-- mail_provider.sql takes the SMTP columns away from the app's publishable key
-- (which could otherwise read the mailbox password) while giving the app back
-- the one column it still needs, app_url.

begin;

-- ---------------------------------------------------------------------------
-- Accounts: verified + a temporary password
-- ---------------------------------------------------------------------------

do $$
begin
  -- The update only runs the first time the column is added: accounts that
  -- existed before verification did must not be locked out of their own games.
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'players_profile'
      and column_name = 'verified'
  ) then
    alter table public.players_profile
      add column verified boolean not null default false;
    update public.players_profile set verified = true;
  end if;
end $$;

alter table public.players_profile
  add column if not exists reset_password_hash text,
  add column if not exists reset_password_salt text,
  add column if not exists reset_password_iterations integer,
  add column if not exists reset_requested_at timestamptz;

-- A reset mail sets the temporary password; signing in with it is allowed and
-- forces a new real password, which clears these columns again.

-- ---------------------------------------------------------------------------
-- Verification links
-- ---------------------------------------------------------------------------

create table if not exists public.email_tokens (
  id         uuid primary key default gen_random_uuid(),
  profile_id text not null references public.players_profile (id) on delete cascade,
  purpose    text not null default 'verify',
  -- Only the SHA-256 of the token in the mail is stored. A leaked row cannot be
  -- turned back into a working link, and the raw token never touches the table.
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at    timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists email_tokens_profile_idx
  on public.email_tokens (profile_id, purpose, created_at desc);

-- ---------------------------------------------------------------------------
-- Mail account
-- ---------------------------------------------------------------------------

create table if not exists public.email_settings (
  -- Exactly one row. The mail service reads the newest enabled row, so
  -- replacing the mailbox means updating this one rather than adding a second.
  id          integer primary key default 1 check (id = 1),
  host        text not null,
  port        integer not null default 465,
  username    text not null,
  password    text not null,
  sender_name text not null default 'BankPop',
  -- The public address of the web build, used to build the verification link
  -- (for example https://bankpop.app). A phone cannot know it, so this column
  -- has to be filled in for the link in a mail opened on Android or iOS. This
  -- is the only column the app reads (through email_public_settings, which
  -- mail_provider.sql creates).
  app_url     text,
  enabled     boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create or replace function public.touch_email_settings()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists email_settings_touched on public.email_settings;
create trigger email_settings_touched
  before update on public.email_settings
  for each row execute function public.touch_email_settings();

commit;

-- ---------------------------------------------------------------------------
-- Filling the row in is described in supabase/mail_provider.sql, which adds the
-- provider and From: columns and takes the mailbox away from the app's key.
-- Run that script before adding the mailbox.
-- ---------------------------------------------------------------------------

-- If the verification mail cannot be sent (no mailbox row yet, or the mail
-- service is not running), sign-up refuses to leave an account behind that
-- nobody can enter. To verify an existing account by hand instead:
--
--   update public.players_profile set verified = true where email = 'you@example.com';
