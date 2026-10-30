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

## Running

One command starts both halves - the mail service in the background, then the
Flutter app, with the service's token passed in from `django-mail-api/.env`:

```
bash dev.sh
```

Its other commands, for when one half is already running:

```
bash dev.sh app       # the app alone
bash dev.sh mail      # the mail service alone, in this terminal, for its logs
bash dev.sh status    # ask the mail service whether it can send
bash dev.sh stop      # stop a mail service left running by dev.sh
```

On Windows that is Git Bash: the script uses `flutter`, the
`django-mail-api/.venv` interpreter and `curl`. `MAIL_PORT=8001 bash dev.sh`
moves the service (the app follows it), and `DEVICE=web-server bash dev.sh`
serves the app on a port instead of opening Chrome.

The same two halves in containers, for a machine without Flutter or Python set
up:

```
docker compose up          # mail service on :8000, app on :8080
docker compose up mail     # or one at a time
docker compose up app
docker compose down
```

The first `up` pulls the Flutter SDK image, which is a large download. `dev.sh`
is the quicker loop once Flutter is installed, because it does not rebuild
dependencies inside a container.

### Where the app finds the mail service

The address follows the page the app is running on, so one build works
everywhere:

| The app is open on | It posts to |
| --- | --- |
| `localhost` / `127.0.0.1`, on any port (`dev.sh`, `flutter run`) | `http://127.0.0.1:8000` |
| the deployed site, or a phone | the hosted service |

The hosted service's address lives in the database, in `mail_api_url` on the
`email_settings` row - `supabase/mail_api_url.sql` adds the column and exposes it
through `email_public_settings`, and the app already reads that row for
`app_url`. Hosting the service is therefore a row update, not a new build:

```sql
update public.email_settings
   set mail_api_url = 'https://mail.your-host.example'
 where id = 1;
```

Two build settings remain as fallbacks for a row that is still empty:
`--dart-define=MAIL_API_HOSTED_URL=https://...`, or `MailApi.hostedService` in
[`app/lib/services/mail_api.dart`](app/lib/services/mail_api.dart). Until one of
the three is set, a hosted build says it has no mail service instead of posting
into nothing. `--dart-define=MAIL_API_URL=https://...` overrides all of them,
which is how a staging build points at a staging service.

For a hosted build the token is a build setting - `MAIL_API_TOKEN` from
`django-mail-api/.env`, passed by `dev.sh` and by the compose file. A web build
cannot keep a secret, so the token is a speed bump; what stops abuse is on the
server (recipient allowlist, rate limit, fixed sender).

On this computer it is not needed at all: a service running with
`DJANGO_DEBUG=1` accepts requests from localhost, so a plain `flutter run` or a
`flutter build web` served locally on any port can send mail without a
`--dart-define`. A deployed service runs with `DEBUG` off, where the token is
required again.

## The app

```
cd app
flutter pub get
flutter run
```

Android, iOS, desktop and web all build from `app/`. The release APK workflow in
`.github/` builds from there too.

Money is written in one sign everywhere - BankPop's own heavy-bar B, not a
national currency. It is a glyph in `app/assets/fonts/BankpopMark.ttf`, listed
as `fontFamilyFallback` on every text style, so a price is still one plain
string (`BoardCurrencies.format`) and the app, the deeds and the printed board
all draw the same character.

The font carries the sign twice:

| Codepoint | Cut | Used for |
|-----------|-----|----------|
| `U+E000` (`BoardCurrencies.mark`) | heavy | balances, prices, totals, the coin |
| `U+E001` (`BoardCurrencies.markLight`) | light | small print: rent tables, house costs, ledger rows |

`app/tool/make_currency_font.py` rebuilds the font from the drawing in
`design/currency-glyphs.html`, centring each cut in its own advance width so the
sign sits in the middle of a coin and of its own space in a line.

The action icons are SVG in `design/app-icons.html`; `app/tool/make_icons.py`
renders them to `app/assets/Icons/` (trimmed and squared), so a change to a
drawing is one command rather than a hand export.

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
- The app only needs the service's address and its `MAIL_API_TOKEN`; see
  [Where the app finds the mail service](#where-the-app-finds-the-mail-service).
  `bash dev.sh` does both. Without them the account screens say so instead of
  failing quietly.

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
| `supabase/board_currency.sql` | The `currency` column a board's prices are stored with (the app now writes BankPop's own sign into it) |
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
