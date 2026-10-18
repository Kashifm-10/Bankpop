-- Cards mode, shared with every device in the game.
--
-- The switch is flipped once, on the banker's "Enter Bank Value" screen, and is
-- written onto the bank row of `players_test`. Players read it from there, so
-- "My Cards" / "Buy Card" only appear in a game that was actually started with
-- cards on. Without this column those buttons never appear on a player device;
-- the banker's own screen still works from its local copy.
--
-- Safe to run more than once.

alter table public.players_test
  add column if not exists play_with_cards boolean not null default false;
