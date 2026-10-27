-- The board a game is played on.
--
-- A board is only the names of the spaces (see supabase/boards.sql): prices,
-- rents, colour groups and the order of the tiles are the same on every board,
-- so this column decides which names the whole table sees. The banker picks it
-- when the game starts - a built-in country or one of their own - and every
-- device reads it back from here: a player who joined by scanning a QR code has
-- no local copy of the choice.
--
-- The value is `game_boards.board_id`: a country id (`india`, `usa`, ...) or
-- `custom_<uuid>` for a board a signed-in player made. The default is for games
-- created before boards existed; they keep playing on the board they started
-- with.
--
-- Safe to run more than once.

alter table public.game_sessions
  add column if not exists board_id text not null default 'usa';

comment on column public.game_sessions.board_id is
  'Board this game plays on: a country id or custom_<uuid> from game_boards.';
