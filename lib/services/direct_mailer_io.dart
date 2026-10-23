import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';

/// Sends one message over SMTP with the credentials from `email_settings`.
///
/// Port 465 is implicit TLS (`ssl: true`), which is what Gmail's app-password
/// flow expects and the only SMTP port Supabase Edge Functions allow. Any
/// other port starts plain and upgrades with STARTTLS; `allowInsecure` stays
/// false, so a server that cannot upgrade fails instead of sending the
/// password in the clear.
class DirectMailer {
  const DirectMailer._();

  static Future<void> send({
    required String host,
    required int port,
    required String username,
    required String password,
    required String senderName,
    required String to,
    required String subject,
    required String text,
    required String html,
  }) async {
    final SmtpServer server = SmtpServer(
      host,
      port: port,
      ssl: port == 465,
      username: username,
      password: password,
      allowInsecure: false,
    );

    final mailer.Message message = mailer.Message()
      ..from = mailer.Address(username, senderName)
      ..recipients.add(to)
      ..subject = subject
      ..text = text
      ..html = html;

    await mailer.send(message, server, timeout: const Duration(seconds: 25));
  }
}
