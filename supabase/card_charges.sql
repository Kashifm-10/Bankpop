-- Card charges: the players' side of a "Collect £10 from each player" card.
--
-- The banker draws the card and writes one row per other player. Each of those
-- players sees the charge waiting on their own screen and confirms it, which
-- pays the receiver directly; the banker's dialog counts the rows until every
-- one is settled.
--
-- Safe to run more than once.

create table if not exists public.card_charges (
  id            serial primary key,
  game_id       text not null,
  -- The card as it was drawn, so the payer's dialog can say what it is for.
  description   text not null,
  receiver_id   text not null,
  receiver_name text not null,
  payer_id      text not null,
  payer_name    text not null,
  amount        numeric not null,
  status        text not null default 'pending'
                check (status in ('pending', 'paid')),
  date          text not null,
  time          text not null
);

create index if not exists card_charges_payer_idx
  on public.card_charges (game_id, payer_id, status);

create index if not exists card_charges_receiver_idx
  on public.card_charges (game_id, receiver_id);

-- Live delivery, so a charge reaches a player without waiting for the poll.
-- The app also polls, so this is an optimisation rather than a requirement.
do $$
begin
  alter publication supabase_realtime add table public.card_charges;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
