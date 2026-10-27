// The web build's way out to SMTP.
//
// A browser cannot open a TCP socket, so `package:mailer` (which the app uses
// on Android and iOS) cannot run there. This function is the bridge: it reads
// the same `email_settings` row and sends the message with nodemailer.
//
// Deploy with:
//   supabase functions deploy send-mail --no-verify-jwt
//
// `--no-verify-jwt` is required because this app has its own accounts and no
// Supabase Auth session; the anon key is all the browser sends. The function
// still uses the service role to read email_settings, so the SMTP password is
// never part of a response.
//
// Port 465 is the sane choice: Supabase blocks outbound 25 and 587.

import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function escapeName(value: string): string {
  return value.replace(/["\\]/g, "");
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "Use POST." }, 405);
  }

  let body: { to?: string; subject?: string; text?: string; html?: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "The request body is not JSON." }, 400);
  }

  const to = (body.to ?? "").trim();
  const subject = (body.subject ?? "").trim();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(to)) {
    return json({ ok: false, error: "The recipient is not an email address." }, 400);
  }
  if (subject.length === 0 || subject.length > 200) {
    return json({ ok: false, error: "The subject is missing or too long." }, 400);
  }
  if ((body.text ?? "").length > 20000 || (body.html ?? "").length > 60000) {
    return json({ ok: false, error: "The message is too long." }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );

  const { data: settings, error } = await admin
    .from("email_settings")
    .select("host, port, username, password, sender_name, enabled")
    .eq("enabled", true)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error("email_settings could not be read", error);
    return json({ ok: false, error: "Email settings could not be read." }, 500);
  }
  if (!settings) {
    return json(
      { ok: false, error: "Email is not configured yet. Run supabase/email.sql and add the SMTP row." },
      503,
    );
  }

  const port = Number(settings.port) || 465;
  const transport = nodemailer.createTransport({
    host: settings.host,
    port,
    secure: port === 465,
    auth: {
      user: settings.username,
      pass: settings.password,
    },
    connectionTimeout: 15000,
    greetingTimeout: 12000,
    socketTimeout: 25000,
  });

  try {
    await transport.sendMail({
      from: `"${escapeName(settings.sender_name || "BankPop")}" <${settings.username}>`,
      to,
      subject,
      text: body.text ?? "",
      html: body.html ?? body.text ?? "",
    });
    return json({ ok: true });
  } catch (sendError) {
    console.error("SMTP send failed", sendError);
    return json(
      {
        ok: false,
        error: "The mail server refused the message. Check the SMTP details and port 465.",
      },
      502,
    );
  } finally {
    transport.close();
  }
});
