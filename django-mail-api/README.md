# django-mail-api

The Bankpop app's mail service: a small Django API that sends the app's email (verification
links, temporary passwords) on Flutter web, Android, iOS and desktop.

Flutter packages like [`mailer`](https://pub.dev/packages/mailer) talk SMTP directly, which
browsers don't allow, so they can't work on Flutter web. Instead, the app sends one HTTPS request
to this server, and the server sends the mail:

```
Bankpop app --POST /api/send-mail/--> this service --SMTP or email API--> recipient's inbox
```

The mailbox is not in the app and not in this service's `.env`: it lives in the app's Supabase
`email_settings` row and is read at send time with a service-role key. Replacing the mailbox, or
rotating its Gmail App Password, is a row update rather than a redeploy - and no browser or phone
ever holds the password (before this service existed, the app sent the mail itself and the
password had to be readable by the app's publishable key).

Mail can go out through Gmail (or any SMTP server such as Zoho or your domain's mail server), or
through an HTTP email service via [django-anymail](https://anymail.dev/): Brevo, Resend, Mailgun
or Postmark. Which one is used is a column in the same row.

**Contents**

1. [Setup](#1-setup)
2. [Gmail configuration](#2-gmail-configuration)
3. [Run the server locally](#3-run-the-server-locally)
4. [Test it](#4-test-it): terminal, curl, Postman
5. [Use it from Flutter](#5-use-it-from-flutter)
6. [API reference](#6-api-reference)
7. [Configuration reference](#7-configuration-reference)
8. [Other providers](#8-other-providers-zoho-brevo-resend-mailgun-postmark)
9. [Security](#9-security)
10. [Deploy](#10-deploy)
11. [Troubleshooting](#11-troubleshooting)
12. [Project layout](#12-project-layout)

---

## 1. Setup

On Windows, `create-django-mail-api.bat` does all of this for you (see
`create-django-mail-api.md`). To do it by hand:

You need [uv](https://docs.astral.sh/uv/) (it installs Python 3.13 for you):

```sh
# Linux / macOS
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell or cmd)
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Then install the dependencies and create your settings file:

```sh
cd django-mail-api
uv sync
cp .env.example .env        # Windows: copy .env.example .env
```

This service's own settings live in `.env` (or the host's environment variables): the API token,
the rate limit, CORS, Django's keys. It is only for your machine: it's in `.gitignore` and is left
out of the deploy zip.

The mail account is not in there. It is read from the app's Supabase `email_settings` row, so set
these two to let the service find it:

```
SUPABASE_URL=https://<your-project>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<Project settings > API > service_role key>
```

The service-role key never leaves the server. That is the point of it: the row holds a mailbox
password, so it must not be readable by the publishable key the app ships with
(`supabase/mail_provider.sql` in the app repository takes that access away).

### The API token (`MAIL_API_TOKEN`)

This is a password **you make up**. It isn't from Google or any other service. The server and your
Flutter app share it, and every request must include it. Generate a random one:

```sh
uv run python -c "import secrets; print(secrets.token_urlsafe(32))"
```

and put it in `.env`:

```
MAIL_API_TOKEN=paste-the-generated-value-here
```

Until it is set, the API refuses every request with `401`.

## 2. Gmail configuration

Gmail won't accept your normal password from an app. You need an **App Password**:

1. Turn on **2-Step Verification** for the Google account
   (Google Account > Security > 2-Step Verification).
2. Open <https://myaccount.google.com/apppasswords>, enter a name such as `django-mail-api`, and
   click **Create**.
3. Google shows a 16-character password **once**. Copy it.

Put the account in the app's Supabase SQL editor, once. The column names come from the app: the
same row is what `supabase/mail_provider.sql` extends.

```sql
update public.email_settings set
  provider    = 'smtp',
  host        = 'smtp.gmail.com',
  port        = 587,                                     -- 465 uses SSL instead
  username    = 'yourname@gmail.com',                     -- EMAIL_HOST_USER
  password    = 'abcdefghijklmnop',                       -- EMAIL_HOST_PASSWORD
  sender_name = 'BankPop',                                -- shown as the sender
  from_email  = 'yourname@gmail.com',                     -- DEFAULT_FROM_EMAIL
  app_url     = 'https://your-app.example',               -- where verification links open
  enabled     = true
where id = 1;
```

| Row column | The same setting as `.env` |
|---|---|
| `provider` | `MAIL_PROVIDER` |
| `host` | `EMAIL_HOST` |
| `port` | `EMAIL_PORT` |
| `username` | `EMAIL_HOST_USER` |
| `password` | `EMAIL_HOST_PASSWORD` |
| `from_email` | `DEFAULT_FROM_EMAIL` (empty means `sender_name <username>`) |
| `api_key` | `MAIL_API_KEY` (HTTP providers only) |
| `sender_domain` | `MAILGUN_SENDER_DOMAIN` (Mailgun only) |

Check the row the way the service sees it (no password printed):

```sh
uv run python manage.py mail_config
```

Notes:

- Spaces in the app password don't matter.
- Gmail always sends **as the logged-in account**. To send as another address, add it under
  Gmail > Settings > Accounts > "Send mail as" first.
- Personal Gmail accounts can send roughly **500 emails a day**. That's fine for contact forms
  and notifications, but not for newsletters.
- If you change your Google password, Google revokes all app passwords. Create a new one.

**Want to try things without sending real mail?** Set `provider = 'console'` in the row, and
emails are printed in the server terminal instead. Everything else in the row is then ignored,
so a half-filled row is enough to see the flow end to end.

## 3. Run the server locally

```sh
uv run python manage.py runserver
```

The API is now at `http://127.0.0.1:8000`. Check it:

```sh
curl http://127.0.0.1:8000/api/health/
# {"status": "ok", "provider": "smtp", "source": "supabase"}
```

`source` says where the account came from: `supabase` is the app's `email_settings` row, `env`
means the service fell back to its own `EMAIL_*` variables (no Supabase configured, or it could
not be reached - the reason is in the log, and `manage.py mail_config` spells it out). A row that
exists but cannot send answers `503` with `"status": "misconfigured"` instead of sending from the
wrong mailbox.

To reach the server from a **phone on the same Wi-Fi**, bind to all interfaces and allow your
computer's LAN IP (find it with `ip addr` or `ipconfig`):

Add the IP to `DJANGO_ALLOWED_HOSTS` in `.env`, then start the server on all interfaces:

```
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,10.0.2.2,192.168.1.50
```

```sh
uv run python manage.py runserver 0.0.0.0:8000
```

On Windows, allow Python through the firewall when Windows asks.

## 4. Test it

### 4a. Check the mailbox alone

What the service will send through, password masked:

```sh
uv run python manage.py mail_config
```

It names the row (or says the environment answered instead), the provider, the From: address and
the SMTP host, so a typo in the Supabase row is visible without sending anything. Add `--refresh`
to read Supabase again instead of the cached row.

Then send one message. In fallback mode (no Supabase row) Django's own command works too:

```sh
uv run python manage.py sendtestemail yourname@gmail.com
```

If that arrives, the mailbox is configured correctly. If it fails, see
[Troubleshooting](#11-troubleshooting).

### 4b. Command line

**Linux / macOS (curl).** Load the token from `.env` into your shell, then send:

```sh
export $(grep ^MAIL_API_TOKEN .env)

curl -X POST http://127.0.0.1:8000/api/send-mail/ \
  -H "Authorization: Bearer $MAIL_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "to": "yourname@gmail.com",
        "subject": "Test from curl",
        "text": "Hello in plain text",
        "html": "<h1>Hello</h1><p>in <b>HTML</b></p>"
      }'
# {"sent": true, "recipients": 1}
```

**Windows (PowerShell):**

```powershell
$token = (Select-String '^MAIL_API_TOKEN=(.*)' .env).Matches[0].Groups[1].Value
$body = @{
    to      = 'yourname@gmail.com'
    subject = 'Test from PowerShell'
    text    = 'Hello in plain text'
    html    = '<h1>Hello</h1><p>in <b>HTML</b></p>'
} | ConvertTo-Json

Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/api/send-mail/ `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType 'application/json' -Body $body
# sent recipients
# ---- ----------
# True          1
```

### 4c. Postman

**Easiest:** import the ready-made collection.

1. In Postman, click **Import** and select `postman/django-mail-api.postman_collection.json`.
2. Open the collection and go to the **Variables** tab. Set:
   - `baseUrl`: `http://127.0.0.1:8000` (or your deployed URL)
   - `token`: the `MAIL_API_TOKEN` value from `.env`
   - `to`: the address that should receive the test email
3. Save, then run **Send plain text** or **Send HTML with cc / reply_to**.

**By hand:**

| Setting | Value |
|---|---|
| Method | `POST` |
| URL | `http://127.0.0.1:8000/api/send-mail/` |
| Authorization tab | Type **Bearer Token**, Token = your `MAIL_API_TOKEN` |
| Headers | `Content-Type: application/json` (added automatically with raw JSON) |
| Body | **raw** > **JSON**, payload below |

Minimal payload:

```json
{
  "to": "yourname@gmail.com",
  "subject": "Test from Postman",
  "text": "Hello! This is a plain-text test email."
}
```

Full payload, like a contact form would send:

```json
{
  "to": ["yourname@gmail.com"],
  "cc": [],
  "bcc": [],
  "reply_to": "customer@example.com",
  "subject": "New contact form message",
  "text": "Name: Asha\nMessage: Please call me back.",
  "html": "<h2>New contact form message</h2><p><b>Name:</b> Asha</p><p>Please call me back.</p>"
}
```

With `reply_to` set, pressing **Reply** in Gmail answers the customer, not your own address.

### 4d. Automated tests

```sh
uv run python manage.py test
```

These tests use an in-memory mail backend and never send real mail.

## 5. Use it from Flutter

### Add the client

1. Add `http` to `pubspec.yaml`:

   ```yaml
   dependencies:
     http: ^1.2.0
   ```

2. Copy `flutter_client/mail_api.dart` into your app (e.g. `lib/services/mail_api.dart`).

The Bankpop app already has it: `app/lib/services/mail_api.dart` is this client, and
`app/lib/services/email_sender.dart` turns each refusal into a sentence the account screens show.
`flutter_client/` is the standalone copy to hand to a different project, and never opens an SMTP
socket on any platform.

### Pass the URL and token at build time

Don't hard-code them. Use `--dart-define`:

```sh
flutter run -d chrome \
  --dart-define=MAIL_API_URL=http://127.0.0.1:8000 \
  --dart-define=MAIL_API_TOKEN=<your MAIL_API_TOKEN>
```

Which `MAIL_API_URL` to use while the server runs on your computer:

| Running the app on | `MAIL_API_URL` |
|---|---|
| Flutter web (`-d chrome`) | `http://127.0.0.1:8000` |
| Desktop (Linux/macOS/Windows) | `http://127.0.0.1:8000` |
| Android emulator | `http://10.0.2.2:8000` |
| iOS simulator | `http://127.0.0.1:8000` |
| Real phone on the same Wi-Fi | `http://<your computer's LAN IP>:8000` (see [section 3](#3-run-the-server-locally)) |
| Deployed server | `https://your-app.wasmer.app` |

Plain `http://` to a local server needs one extra setting on mobile:

- **Android:** add `android:usesCleartextTraffic="true"` to the `<application>` tag in
  `android/app/src/debug/AndroidManifest.xml` (debug builds only). Release builds use `https`,
  so they don't need it.
- **iOS:** add `NSAppTransportSecurity` > `NSAllowsLocalNetworking` = `YES` to
  `ios/Runner/Info.plist`.

### Send an email

```dart
import 'services/mail_api.dart';

final mailApi = MailApi();

Future<void> sendContactMessage(String name, String email, String message) async {
  try {
    await mailApi.send(
      to: ['yourname@gmail.com'],
      replyTo: [email],
      subject: 'New message from $name',
      text: 'From: $name <$email>\n\n$message',
      html: '<p><b>From:</b> $name &lt;$email&gt;</p><p>$message</p>',
    );
    // success: show a "Message sent" snackbar
  } on MailApiException catch (e) {
    // e.statusCode: 400 / 401 / 429 / 502
    // e.message:    "invalid request", "unauthorized", ...
    // e.fields:     per-field problems for 400, e.g. {"to": "invalid email address: x"}
  }
}
```

Escape user input before putting it in `html` (for example with `HtmlEscape` from `dart:convert`).
Otherwise people can inject markup into your email.

### CORS (Flutter web only)

The browser blocks requests to another origin unless the server allows it. `localhost` and
`127.0.0.1` on **any port** are allowed by default, so `flutter run -d chrome` works out of the box.
For your deployed web app, add its address:

```
CORS_ALLOWED_ORIGINS=https://myapp.example.com,https://myapp.web.app
```

Android, iOS and desktop apps aren't affected by CORS.

## 6. API reference

### `POST /api/send-mail/`

**Headers**

```
Authorization: Bearer <MAIL_API_TOKEN>
Content-Type: application/json
```

**Body**

| Field | Type | Required | Notes |
|---|---|---|---|
| `to` | string or list of strings | yes | recipient(s) |
| `subject` | string | yes | one line, max 200 characters |
| `text` | string | one of `text`/`html` | plain-text body |
| `html` | string | one of `text`/`html` | HTML body; sent alongside `text` if both are given |
| `cc` | string or list | no | |
| `bcc` | string or list | no | |
| `reply_to` | string or list | no | where replies go |

`to` + `cc` + `bcc` together can't exceed `MAIL_MAX_RECIPIENTS` (default 5). Bodies can be up to
50,000 characters. The sender is always `DEFAULT_FROM_EMAIL`, and any `from` field in the body is
ignored.

**Responses**

| Status | Body | Meaning |
|---|---|---|
| `200` | `{"sent": true, "recipients": 1}` | accepted by Gmail / the provider |
| `400` | `{"error": "invalid request", "fields": {...}}` | see the example below |
| `400` | `{"error": "body must be JSON"}` | body isn't valid JSON |
| `401` | `{"error": "unauthorized"}` | missing or wrong token, or no `MAIL_API_TOKEN` on the server |
| `405` | (empty) | used GET instead of POST |
| `404` | HTML page | wrong URL path |
| `429` | `{"error": "too many requests, try again later"}` | rate limit for this IP |
| `502` | `{"error": "the mail provider rejected the message"}` | Gmail/provider error; details in the server log |
| `503` | `{"error": "provider is smtp, so email_settings needs host, username and password."}` | the row that was read cannot send, so nothing was attempted |

Example `400`:

```json
{
  "error": "invalid request",
  "fields": {
    "to": "invalid email address: not-an-email",
    "subject": "required",
    "text": "provide text, html or both"
  }
}
```

`200` means Gmail accepted the message. It can still land in spam or bounce later.

### `GET /api/health/`

No token needed. Returns the provider and where the account was read from:
`{"status": "ok", "provider": "smtp", "source": "supabase"}`. A row that cannot send answers
`503` with `{"status": "misconfigured", "error": "..."}`. The host, username and password are
never in either answer; `manage.py mail_config` is what shows those, on the server.

## 7. Configuration reference

### The mail account: one row in the app's Supabase project

Read at send time through the REST API with the service-role key, cached for
`MAIL_CONFIG_CACHE_SECONDS` (60) so the table is not hit for every message.

| Column | Default | What it does |
|---|---|---|
| `enabled` | `true` | a disabled row is ignored, and the service falls back to its environment |
| `provider` | `smtp` | `console`, `smtp`, `brevo`, `resend`, `mailgun`, `postmark` |
| `host` | | SMTP server, e.g. `smtp.gmail.com` |
| `port` | `587` | `587` uses STARTTLS, `465` uses SSL |
| `username` | | SMTP login (your Gmail address) |
| `password` | | SMTP password (the Gmail app password) |
| `sender_name` | `BankPop` | display name, used when `from_email` is empty |
| `from_email` | | the From: address; empty means `sender_name <username>` |
| `api_key` | | API key for brevo/resend/mailgun/postmark |
| `sender_domain` | | Mailgun only |
| `app_url` | | the app's own web address, for the links in its mail (the app reads this one) |

### This service's environment

All of these go in `.env` (local) or the host's environment variables (deployed).

| Variable | Default | What it does |
|---|---|---|
| `SUPABASE_URL` | | `https://<project>.supabase.co`; unset means the fallback below is used |
| `SUPABASE_SERVICE_ROLE_KEY` | | server-side key that may read the mailbox row |
| `MAIL_CONFIG_TABLE` | `email_settings` | the table the row lives in |
| `MAIL_CONFIG_CACHE_SECONDS` | `60` | how long a read row is reused |
| `MAIL_CONFIG_TIMEOUT_SECONDS` | `10` | how long to wait for Supabase |
| `MAIL_API_TOKEN` | *(empty: all requests refused)* | shared token clients send as `Bearer` |
| `MAIL_PROVIDER` | `console` | the fallback account's provider, when there is no row |
| `DEFAULT_FROM_EMAIL` | `webmaster@localhost` | the fallback account's From: address |
| `EMAIL_HOST` | | fallback SMTP server, e.g. `smtp.gmail.com` |
| `EMAIL_PORT` | `587` | fallback port: `587` STARTTLS, `465` SSL |
| `EMAIL_HOST_USER` | | fallback SMTP login |
| `EMAIL_HOST_PASSWORD` | | fallback SMTP password |
| `MAIL_API_KEY` | | fallback API key for brevo/resend/mailgun/postmark |
| `MAILGUN_SENDER_DOMAIN` | | Mailgun only |
| `MAILGUN_API_URL` | `https://api.mailgun.net/v3` | Mailgun EU: `https://api.eu.mailgun.net/v3` |
| `MAIL_ALLOWED_RECIPIENT_DOMAINS` | *(any)* | e.g. `mycompany.com`: only these recipient domains |
| `MAIL_MAX_RECIPIENTS` | `5` | max to + cc + bcc per request |
| `MAIL_RATE_LIMIT` | `10` | sends per client IP per window |
| `MAIL_RATE_WINDOW_SECONDS` | `3600` | window length (1 hour) |
| `CORS_ALLOWED_ORIGINS` | | your Flutter web app's URL(s), comma-separated |
| `CORS_ALLOWED_ORIGIN_REGEXES` | localhost / 127.0.0.1, any port | origins matched by regex |
| `DJANGO_SECRET_KEY` | dev value | set a random value in production |
| `DJANGO_DEBUG` | `0` | `1` shows detailed error pages; never use it in production |
| `DJANGO_ALLOWED_HOSTS` | `localhost,127.0.0.1,10.0.2.2,.wasmer.app` | host names the server answers to |

## 8. Other providers (Zoho, Brevo, Resend, Mailgun, Postmark)

**Zoho Mail (SMTP):** same as Gmail, with an app-specific password from Zoho's security settings:

```sql
update public.email_settings set
  provider = 'smtp',
  host     = 'smtp.zoho.com',            -- smtp.zoho.in for India-region accounts
  port     = 587,
  username = 'you@yourdomain.com',
  password = '<app-specific password>',
  from_email = 'you@yourdomain.com'
where id = 1;
```

**HTTP email services** send over HTTPS, so they work on hosts that block SMTP ports. Create an
account, verify your sender address or domain with them, then:

```sql
update public.email_settings set
  provider   = 'brevo',                  -- or resend / postmark / mailgun
  api_key    = '<API key>',              -- Postmark: the "Server API token"
  from_email = 'My App <noreply@yourdomain.com>',
  sender_domain = 'mg.yourdomain.com'    -- Mailgun only
where id = 1;
```

Switching providers is one row. The Flutter app stays the same, and nothing is redeployed.

## 9. Security

The token is compiled into the Flutter app, and **anyone can read it from a web build** (or decompile
it from a mobile app). It keeps random traffic out, but it isn't a real secret. Assume someone
will eventually find the endpoint and try to use it for spam. These settings limit the damage:

- **`MAIL_ALLOWED_RECIPIENT_DOMAINS`**: the strongest protection. For a contact form, set it to
  your own domain (or put only your Gmail domain there), so mail can never go to strangers.
- **Rate limit**: 10 sends per IP per hour by default. The counter lives in memory, so it resets
  when the server restarts and each worker process counts separately.
- **`MAIL_MAX_RECIPIENTS`**: caps recipients per request.
- **Fixed sender**: clients can't choose the `from` address.
- Subjects can't contain line breaks, so extra email headers can't be injected.

If your app has user logins, the stronger option is to check the user's login token on this
endpoint instead of a shared token.

The mailbox password is in the app's Supabase `email_settings` row, which is now readable only
with the service-role key (`supabase/mail_provider.sql` revokes the app's access and gives it back
just the `app_url` it needs). Keep that key on the server, and keep `.env` private. If the Gmail
app password leaks, revoke it at <https://myaccount.google.com/apppasswords>, create a new one,
and update the row - the service picks it up within `MAIL_CONFIG_CACHE_SECONDS`, with no
restart and no release.

## 10. Deploy

### Wasmer Edge (zip upload)

```sh
./build-zip.sh          # Linux / macOS
build-zip.bat           # Windows
```

Both create `dist/django-mail-api.zip`.

1. Upload `dist/django-mail-api.zip` in the Wasmer dashboard.
2. Set the environment variables there: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
   `MAIL_API_TOKEN`, `DJANGO_SECRET_KEY`, `CORS_ALLOWED_ORIGINS`. `.env` isn't in the zip.
   The mailbox is already in the app's Supabase row, so there is nothing else to configure - and
   no app password to paste into a hosting dashboard.
3. Test with `https://<your-app>.wasmer.app/api/health/`, then the Postman collection
   with `baseUrl` set to that URL.

The WSGI entrypoint is `config.wsgi:app`, and `*.wasmer.app` hosts are allowed by default.
Wasmer's free tier lists SMTP as a Pro feature. If Gmail sends fail there with a `502` and a
connection error in the logs, switch to an HTTP provider ([section 8](#8-other-providers-zoho-brevo-resend-mailgun-postmark)).

### Docker

```sh
docker build -t django-mail-api .
docker run -p 8000:8000 --env-file .env -e DJANGO_DEBUG=0 django-mail-api
```

## 11. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `401 unauthorized` | Token missing or different from `MAIL_API_TOKEN` in `.env`. The header must be `Authorization: Bearer <token>`. Restart the server after editing `.env`. |
| `502`, and the log shows `SMTPAuthenticationError: (535, ... Username and Password not accepted)` | You used your normal Gmail password, or the app password is wrong or revoked. Create a new app password ([section 2](#2-gmail-configuration)). |
| `502`, and the log shows `Connection refused` / `timed out` / `Network is unreachable` | The network or host blocks SMTP (common on free hosting and some office networks). Try port `465`, or switch to an HTTP provider. |
| `400 Bad Request` HTML page, and the log shows `DisallowedHost` | The host name you're calling isn't in `DJANGO_ALLOWED_HOSTS` (e.g. your LAN IP). |
| Flutter web: `XMLHttpRequest error` / `ClientException`, and the browser console mentions CORS | Add your web app's origin to `CORS_ALLOWED_ORIGINS` (exact scheme + host + port, no trailing slash). |
| Android: `Cleartext HTTP traffic not permitted` | Add `usesCleartextTraffic` for debug builds ([section 5](#5-use-it-from-flutter)). |
| Android emulator can't connect to `127.0.0.1` | Use `http://10.0.2.2:8000`; inside the emulator, `127.0.0.1` is the emulator itself. |
| `429 too many requests` | Rate limit hit. Wait, raise `MAIL_RATE_LIMIT`, or restart the dev server to reset it. |
| `405` | The request was a GET. Use `POST .../api/send-mail/`. |
| `200` but no email | Check the spam folder, and the recipient address. With `MAIL_PROVIDER=console`, nothing is actually sent. |
| `ImproperlyConfigured: Unknown MAIL_PROVIDER` | Typo in the `MAIL_PROVIDER` fallback variable; the allowed values are in [section 7](#7-configuration-reference). A typo in the row's `provider` answers `503` instead. |
| `503` "provider is smtp, so email_settings needs host, username and password" | The row exists but has no mailbox password (or no host/username). Fill it in as in [section 2](#2-gmail-configuration); nothing was sent. |
| `/api/health/` says `"source": "env"` although the row is filled in | `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` are not set on the server, or Supabase answered with an error - the reason is logged as a warning. `uv run python manage.py mail_config --refresh` prints the same, and reads the row again instead of the cached copy. |
| Mail still arrives from the old address after editing the row | The previous row is reused for up to `MAIL_CONFIG_CACHE_SECONDS` (60 by default). Wait, or lower that setting. |
| `200` but the mail is printed in the server log | `provider` is still `console` in the row (or in `MAIL_PROVIDER` when there is no row). Nothing is sent in that mode, by design. |

When a send fails, the full error is printed in the terminal running `runserver` (or the host's logs),
and every message logs the account it went out through, with the password masked.

## 12. Project layout

```
config/settings.py        this service's own settings (reads .env / environment variables)
config/urls.py            URL routes
config/wsgi.py            WSGI entrypoint (`app`, used by gunicorn and Wasmer)
mailer/config.py          the mail account: reads the app's email_settings row from Supabase,
                          with the environment as the fallback
mailer/providers.py       the provider names, as backend paths, shared with settings
mailer/views.py           the API: auth, validation, rate limit, sending
mailer/management/commands/mail_config.py
                          prints the account in use, password masked
mailer/tests.py           automated tests (nothing is sent, nothing is fetched)
flutter_client/           the Dart client, for a project that is not Bankpop
postman/                  Postman collection (import into Postman)
.env.example              template for .env
build-zip.sh / .bat       builds dist/django-mail-api.zip for Wasmer
Dockerfile                container image (gunicorn)
```

In the Bankpop repository the app itself is one level up, in `app/`: its copy of the client is
`app/lib/services/mail_api.dart`, and the Supabase scripts that create the row and close it to the
app's key are in `supabase/email.sql` and `supabase/mail_provider.sql`.
