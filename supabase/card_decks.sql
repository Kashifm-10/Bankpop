-- The Chance and Community Chest packs, once per game.
--
-- Both packs are shuffled when the banker starts the game and kept on the
-- game's row, so every device deals the same card in the same order and a
-- reopened game carries on where the table stopped rather than starting a new
-- shuffle.
--
-- A pack is stored as {"cards": ["...", "..."], "drawn": 3}: the order drawn
-- when it was last shuffled, and how many cards of that order have been seen.
-- When every card has been seen the next draw shuffles the pack again.
--
-- Safe to run more than once.

alter table public.game_sessions
  add column if not exists chance_deck jsonb;

alter table public.game_sessions
  add column if not exists chest_deck jsonb;
