# send-mail

The web build's only way to send mail. The browser has no sockets, so
`package:mailer` — which the Android and iOS builds use directly — cannot run
there. This function reads the SMTP row from `email_settings` and sends the
message with nodemailer.

## One-time setup

1. Run [`supabase/email.sql`](../../email.sql) in the Supabase SQL editor.
2. Add the mailbox row (the SQL file has a ready-to-edit `insert`):

   ```sql
   insert into public.email_settings
     (host, port, username, password, sender_name, app_url)
   values
     ('smtp.gmail.com', 465, 'noreplyoraction@gmail.com',
      'the-app-password', 'BankPop', 'https://your-app.example')
   on conflict (id) do update set
     host = excluded.host,
     port = excluded.port,
     username = excluded.username,
     password = excluded.password,
     sender_name = excluded.sender_name,
     app_url = excluded.app_url,
     enabled = true;
   ```

   Gmail needs 2-Step Verification and an **App Password**; the account
   password will be refused. Use port **465**: Supabase Edge Functions block
   outbound ports 25 and 587, and the app's own mailer also uses 465 as
   implicit TLS, so one row works for both paths.
3. Deploy the function:

   ```bash
   supabase functions deploy send-mail --no-verify-jwt
   ```

   `--no-verify-jwt` is deliberate: this app has its own `players_profile`
   accounts and no Supabase Auth session, so the browser only carries the
   publishable key. The function still reads `email_settings` with the service
   role, and its response never includes the mailbox password.

## Checking it

```bash
curl -i -X POST \
  "https://<project-ref>.supabase.co/functions/v1/send-mail" \
  -H "apikey: <publishable-key>" \
  -H "Content-Type: application/json" \
  -d '{"to":"you@example.com","subject":"BankPop test","text":"It works.","html":"<p>It works.</p>"}'
```

A 200 with `{"ok":true}` means the row and the mailbox are both good.

## Notes

- The app reads `email_settings` too, because that is where it learns whether
  mail is configured and what `app_url` to put in a verification link. Because
  of that, the publishable key can read the SMTP password. Use a mailbox that
  exists only for BankPop, with a revocable app password.
- This endpoint sends what it is told to, to anyone. It is intended for a
  small private game, not a public relay; if the app grows, move mail behind a
  signed request and keep the credentials server-only.
