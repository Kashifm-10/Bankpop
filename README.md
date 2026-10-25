# Bankpop

A multiplayer property-trading board game, played around one phone. The banker's
device holds the bank and the board; every other player joins it and plays from
their own screen.

Flutter app (`lib/`) with Supabase as the backend for the game state.

## Running

```
flutter pub get
flutter run
```

## Database

The app expects these scripts to have been run once, in order, in the Supabase
SQL editor:

| Script | What it adds |
| --- | --- |
| `supabase/boards.sql` | The country boards and the board a game plays on |
| `supabase/game_sessions.sql` | The game's row: rules, lifecycle, board choice |
| `supabase/accounts.sql`, `supabase/email.sql` | Player accounts, and the mailbox the app sends from |
| `supabase/player_cards.sql` | Properties bought during a cards game |
| `supabase/buildings.sql` | Houses and hotels on those cards |
| `supabase/mortgage_trades.sql` | Mortgages and the trade ledger |
| `supabase/card_decks.sql` | The shuffled Chance and Community Chest packs |
| `supabase/card_charges.sql` | Each player's share of a "collect from everyone" card |
| `supabase/board_currency.sql` | The money symbol a board's prices are written in |
| `supabase/hardening.sql` | The atomic money-transfer functions |
| `supabase/player_status.sql`, `supabase/players_cleanup.sql` | Presence, and one seat with one standing |

Every script is safe to run more than once. Where a script is missing the app
still opens and tells the banker which one to run, rather than failing quietly.

## Tests

```
flutter analyze
flutter test
```
