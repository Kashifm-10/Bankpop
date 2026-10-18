-- Mortgages and trades.
--
-- Both work the way buildings already do: the ask is written down first, nothing
-- moves, and the person on the other side settles it. A mortgage or a sale of
-- buildings is settled by the bank (the banker's screen), a trade by the other
-- player, and in both cases the money and the cards move together at that point.
--
-- Safe to run more than once.

-- 1. A mortgaged card still belongs to its owner; it just cannot collect rent,
--    be built on, or move in a trade without the interest being paid.
alter table public.player_cards
  add column if not exists mortgaged boolean not null default false;

-- 2. One queue for every deal.
--
--    kind: 'mortgage' | 'unmortgage' | 'sell_house' | 'sell_hotel' | 'trade'
--    cards: comma-separated board indexes this side puts on the table
--    wants: comma-separated board indexes this side asks for
--    cash / wants_cash: the money side of the same deal
--    to_id: the bank's player_id for a bank deal, the other player's for a trade
create table if not exists public.deal_requests (
  id serial not null primary key,
  game_id text not null,
  kind text not null,
  from_id text not null,
  from_name text not null,
  to_id text not null,
  to_name text not null,
  cards text not null default '',
  wants text not null default '',
  cash numeric not null default 0,
  wants_cash numeric not null default 0,
  status text not null default 'pending', -- 'pending' | 'approved' | 'rejected' | 'cancelled'
  date text not null,
  time text not null
) TABLESPACE pg_default;

create index if not exists idx_deal_requests_game_status
  on public.deal_requests using btree (game_id, status)
  TABLESPACE pg_default;

-- 3. Live delivery so a request appears without waiting for the poll.
--    The app also polls, so this is an optimisation rather than a requirement.
do $$
begin
  alter publication supabase_realtime add table public.deal_requests;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
