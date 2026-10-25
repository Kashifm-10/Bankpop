-- The money symbol a board's prices are written in.
--
-- The numbers on the board are the game's, but the symbol belongs to the place
-- the board is named after: an Indian board reads ₹200 where the American one
-- reads $200. A player's own board stores the symbol they picked for it. A
-- board with no symbol falls back to its country's currency in the app, so this
-- script can be run at any time.
--
-- Safe to run more than once.

alter table public.game_boards
  add column if not exists currency text not null default '';

update public.game_boards set currency = '₹' where board_id = 'india' and currency = '';
update public.game_boards set currency = '$' where board_id = 'usa' and currency = '';
update public.game_boards set currency = '£' where board_id = 'uk' and currency = '';
update public.game_boards set currency = '€' where board_id in ('france', 'germany', 'italy', 'spain') and currency = '';
update public.game_boards set currency = '¥' where board_id in ('japan', 'china') and currency = '';
update public.game_boards set currency = 'R$' where board_id = 'brazil' and currency = '';
update public.game_boards set currency = 'A$' where board_id = 'australia' and currency = '';
update public.game_boards set currency = 'C$' where board_id = 'canada' and currency = '';
update public.game_boards set currency = 'E£' where board_id = 'egypt' and currency = '';
update public.game_boards set currency = 'AED' where board_id = 'uae' and currency = '';
