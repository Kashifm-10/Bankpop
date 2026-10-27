-- Play with Cards - hardening for public.player_cards.
--
-- The table, its indexes and the populate_pcard_ids trigger are created by the
-- game schema; this file only adds what the client relies on when two devices
-- try to buy the same property at the same instant.
--
-- Run once in the Supabase SQL editor. Safe to run again.

-- A board index can only be sold once per game. Without this, two players
-- scanning the same "Sell <property>" QR at the same moment can both insert a
-- row and both be charged; the client checks first, and this index is what makes
-- that check decisive. The client reads the resulting 23505 as "already sold"
-- and never takes the money.
create unique index if not exists pcard_game_index_unique
  on public.player_cards using btree (game_id, card_index) TABLESPACE pg_default;

-- Note: if a game already contains two rows for the same (game_id, card_index),
-- this statement fails with a duplicate-key error. Delete the extra rows and run
-- it again; the app keeps working without the index, it is just no longer
-- race-proof.
