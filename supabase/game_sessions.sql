-- Game sessions.
--
-- Everything that describes a *game* rather than a person now lives here:
-- which payment mode it was started with, whether it plays with cards, the
-- per-player stake and the round advance, plus its lifecycle (active,
-- suspended, ended) and when that lifecycle started and finished.
--
-- It used to live on the banker's row in `players_test`, which meant a player
-- device had to read the banker's wallet to learn the rules, and no device
-- could say when a game began or ended. `players_test` is now only about
-- people: name, wallet, role, game.
--
-- Safe to run more than once.

-- The older optional columns, so the backfill below works on any project.
alter table public.players_test
  add column if not exists play_with_cards boolean not null default false;
alter table public.players_test
  add column if not exists player_value numeric;
alter table public.players_test
  add column if not exists advance_value numeric;

create table if not exists public.game_sessions (
  id            serial primary key,
  -- One row per game. `players_test` and every other table already key off
  -- this string, so the session joins to them without a second id.
  game_id       text not null unique,
  banker_id     text not null,
  banker_name   text not null default 'Bank',
  -- 'active'    : being played
  -- 'suspended' : paused by the banker, resumable exactly where it stopped
  -- 'ended'     : finished; ended_at is set and nothing may change it
  status        text not null default 'active'
                check (status in ('active', 'suspended', 'ended')),
  payment_option text not null default 'InstantPay',
  play_with_cards boolean not null default false,
  player_value  numeric not null default 0,
  advance_value numeric not null default 0,
  started_at    timestamptz not null default now(),
  ended_at      timestamptz,
  updated_at    timestamptz not null default now()
);

-- The home screen asks for one device's games, newest first; the player screen
-- asks for one game's status.
create index if not exists game_sessions_status_started_idx
  on public.game_sessions (status, started_at desc);

create index if not exists game_sessions_banker_idx
  on public.game_sessions (banker_id, started_at desc);

-- Live delivery, so a suspension reaches every player device immediately.
-- Guarded: adding a table twice raises, and that must not abort the script.
do $$
begin
  alter publication supabase_realtime add table public.game_sessions;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

-- One-time backfill of games that were started before this table existed.
-- They come out active, with the settings their bank row still carries.
insert into public.game_sessions (
  game_id, banker_id, banker_name, status, payment_option,
  play_with_cards, player_value, advance_value, started_at
)
select
  b.game_id,
  coalesce(b.player_id, ''),
  coalesce(b.name, 'Bank'),
  'active',
  coalesce(b."SP/IP", 'InstantPay'),
  coalesce(b.play_with_cards, false),
  coalesce(b.player_value, 0),
  coalesce(b.advance_value, 0),
  now()
from public.players_test b
where b.role = 'banker'
on conflict (game_id) do nothing;
