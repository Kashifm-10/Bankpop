-- Player accounts.
--
-- A profile is the thing that survives a reinstall or a new device: the row's
-- `id` is the stable player id the game rows already use, and signing in on a
-- new phone adopts it, so the games played under that account are still that
-- player's games.
--
-- Passwords are never stored. The app derives a salted PBKDF2-HMAC-SHA256 hash
-- on the device and stores only the hash, its salt and the iteration count, so
-- a login can re-derive and compare. The publishable key ships with the app, so
-- this table is readable by any client - the hash format is what keeps the
-- passwords themselves out of reach. If accounts ever need to resist a
-- determined attacker rather than a curious player, move this table behind a
-- server function (or Supabase Auth) instead of loosening anything here.
--
-- Safe to run more than once.

create table if not exists public.players_profile (
  -- The stable player id. Matches players_test.player_id, which is what links
  -- this account to every game it has played.
  id            text primary key,
  email         text not null,
  password_hash text not null,
  password_salt text not null,
  iterations    integer not null default 20000,
  name          text,
  avatar        text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Login is a lookup by address. Emails are normalised to lower case by the app
-- before they are written or read, so a plain unique index is enough.
create unique index if not exists players_profile_email_idx
  on public.players_profile (email);

-- Profiles are read once at login rather than live, so they are deliberately
-- left out of the realtime publication.
