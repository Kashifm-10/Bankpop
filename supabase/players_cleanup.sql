-- One seat, one standing.
--
-- Run this after supabase/player_status.sql - or on a project that already ran
-- it. Two things changed in the app:
--
--   * presence is gone. There is no heartbeat, no OFFLINE badge and no LEFT
--     state, so `last_seen` has no reader and no writer any more.
--   * `status` no longer distinguishes "quit the screen" from "removed". A seat
--     is either the player's ('active') or gone ('kicked'); leaving the screen
--     changes nothing, and coming back needs no write.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. Presence: dropped, not merely unused.
-- ---------------------------------------------------------------------------
alter table public.players_test
  drop column if exists last_seen;

-- ---------------------------------------------------------------------------
-- 2. Any row left in the old 'left' state becomes an ordinary seated player.
-- ---------------------------------------------------------------------------
update public.players_test
   set status = 'active'
 where status is null
    or status not in ('active', 'kicked');

alter table public.players_test
  alter column status set default 'active';

alter table public.players_test
  alter column status set not null;

-- The old constraint allowed 'left'; replace it with the two states the app
-- understands. Dropped first so re-running cannot fail on a duplicate name.
alter table public.players_test
  drop constraint if exists players_test_status_check;

alter table public.players_test
  add constraint players_test_status_check
  check (status in ('active', 'kicked'));

-- ---------------------------------------------------------------------------
-- 3. Your Games reads every row this device has, across all of its games.
--    Without this it was a sequential scan of the whole table.
-- ---------------------------------------------------------------------------
create index if not exists players_test_player_idx
  on public.players_test (player_id);

create index if not exists players_test_game_player_idx
  on public.players_test (game_id, player_id);

-- ---------------------------------------------------------------------------
-- 4. The (game_id, status) index existed for the heartbeat's "who is offline"
--    read, which no longer exists; a kick looks a single row up by id.
-- ---------------------------------------------------------------------------
drop index if exists public.players_test_game_status_idx;

-- ---------------------------------------------------------------------------
-- 5. Hand-over writes the bank row's device id and the session together. The
--    app does both as plain updates, so there is nothing to install here - this
--    is only the sanity check that both are in place:
--
--      select game_id, banker_id, banker_name from public.game_sessions;
--      select game_id, player_id, name, role from public.players_test
--       where role = 'banker';
-- ---------------------------------------------------------------------------

-- Verify the new shape:
--   \d public.players_test
--   select status, count(*) from public.players_test group by status;
