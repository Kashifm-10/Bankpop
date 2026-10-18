-- Houses and hotels, and the requests that buy them.
--
-- A player asks for one building on a card they own; the banker approves it, and
-- only then does the money move. The count of buildings lives on the card row so
-- every device reads the same board.
--
-- Safe to run more than once.

-- 1. What is built on each card. 0-4 houses, and a hotel once 4 houses are up.
alter table public.player_cards
  add column if not exists houses integer not null default 0;
alter table public.player_cards
  add column if not exists hotels integer not null default 0;

-- 2. The queue the banker works through.
create table if not exists public.card_requests (
  id serial not null primary key,
  game_id text not null,
  card_index integer not null,
  player_id text not null,
  player_name text not null,
  kind text not null, -- 'house' | 'hotel'
  amount numeric not null,
  status text not null default 'pending', -- 'pending' | 'approved' | 'rejected'
  date text not null,
  time text not null
) TABLESPACE pg_default;

create index if not exists idx_card_requests_game_status
  on public.card_requests using btree (game_id, status)
  TABLESPACE pg_default;

-- 3. Live delivery, so the banker's dialog appears without waiting for the poll.
--    The app also polls, so this is an optimisation rather than a requirement.
do $$
begin
  alter publication supabase_realtime add table public.card_requests;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
