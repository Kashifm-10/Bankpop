# Bankpop

A multiplayer property-trading board game, played around one phone. The banker's
device holds the bank and the board; every other player joins it and plays from
their own screen.

Flutter app with Supabase as the backend for the game state, and a small Django
service that sends the app's email.

## Layout

```
Bankpop/
├── app/               the Flutter game (lib/, android/, ios/, web/, test/, tool/)
├── django-mail-api/   the mail service the app posts verification and reset mail to
├── supabase/          the SQL to run once in the Supabase project
├── .agents/           design reference used while building screens
└── .github/           the workflow that builds the release APK (from app/)
```

`app/` and `django-mail-api/` are independent: neither builds the other, and the
only thing they share is one row in Supabase (see [Mail](#mail)).

## The app

```
cd app
flutter pub get
flutter run
```

Android, iOS, desktop and web all build from `app/`. The release APK workflow in
`.github/` builds from there too.

## The mail service

Verification links and temporary passwords are sent by `django-mail-api/`, not by
the app: a browser cannot open an SMTP connection, and a phone that holds the
mailbox password means every install holds it.

```
cd django-mail-api
uv sync
cp .env.example .env        # Windows: copy .env.example .env
uv run python manage.py runserver
```

Its README covers Gmail, other providers, testing and deploying. In short:

- The **mailbox** (provider, host, port, username, password, From: address) lives
  in the app's Supabase `email_settings` row, so it can be changed without a
  redeploy and without shipping the password in the app.
- The service reads that row with a Supabase **service-role key**
  (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` in its `.env`).
- The app only needs the service's address and its `MAIL_API_TOKEN`, passed at
  build time:

  ```
  flutter run -d chrome \
    --dart-define=MAIL_API_URL=http://127.0.0.1:8000 \
    --dart-define=MAIL_API_TOKEN=<the service's MAIL_API_TOKEN>
  ```

  Without them the account screens say so instead of failing quietly.

## Database

Run these once, in order, in the Supabase SQL editor:

| Script | What it adds |
| --- | --- |
| `supabase/boards.sql` | The country boards and the board a game plays on |
| `supabase/game_sessions.sql` | The game's row: rules, lifecycle, board choice |
| `supabase/accounts.sql`, `supabase/email.sql` | Player accounts, verification links, and the mailbox |
| `supabase/mail_provider.sql` | The provider and From: columns the mail service reads, and who may read the mailbox |
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
cd app && flutter analyze && flutter test
cd django-mail-api && uv run python manage.py test
```

The Dart tests cover the screens, the board, rent and the mail client; the Python
tests cover the API and the row it sends through, with nothing sent and nothing
fetched from the network.
