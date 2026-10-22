-- Player status and presence.
--
-- Historical: supabase/players_cleanup.sql supersedes parts of this file. Run
-- this one first, then that one. It added two things:
--
--   * is this player still at the table? (`last_seen`)
--   * was this player removed from the game, or did they leave? (`status`)
--
-- Presence was removed from the app afterwards, and the 'left' state went with
-- it; the cleanup drops `last_seen` and narrows `status` to active/kicked.
--
-- `players_test` only had `role`, so removing a player meant deleting the row,
-- which also deleted the record of the cash and the cards they had. Instead the
-- row stays, is marked `kicked` (or `left`), and the assets it held are moved to
-- the bank by the app - the badge then stays next to the name for the rest of
-- the game.
--
-- 'active' is the default, so every existing row is a live player the moment
-- this runs. A project that has not run this file still works: the app treats a
-- missing `status` as 'active' and simply never shows the badges, and a kick
-- falls back to marking the row with role = 'kicked'.
--
-- Safe to run more than once.

alter table public.players_test
  add column if not exists status text not null default 'active';

alter table public.players_test
  add column if not exists last_seen timestamptz;

-- The banker asks for one game's roster on every tick, and every player device
-- stamps its own row every 20 seconds. Both are keyed on the game.
create index if not exists players_test_game_status_idx
  on public.players_test (game_id, status);

-- Only the three states the app understands.
do $$
begin
  alter table public.players_test
    add constraint players_test_status_check
    check (status in ('active', 'kicked', 'left'));
exception
  when duplicate_object then null;
end $$;

-- Live delivery of a kick / leave, so a removed player's device finds out on the
-- same tick the banker taps. Additive and guarded: adding the table twice raises,
-- and that must not abort the script.
do $$
begin
  alter publication supabase_realtime add table public.players_test;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
