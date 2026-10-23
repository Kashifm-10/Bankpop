import 'package:flutter/foundation.dart';
import 'package:mon/services/direct_mailer.dart';
import 'package:mon/services/email_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What happened to one mail.
class EmailResult {
  const EmailResult.ok(this.message) : ok = true;
  const EmailResult.failure(this.message) : ok = false;

  final bool ok;
  final String message;
}

/// Sends one message with the credentials in `email_settings`.
///
/// Two roads, one table:
///  * Android, iOS and desktop open an SMTP connection from the app with
///    `package:mailer` - the fastest path, and the one that works offline from
///    any server.
///  * The browser has no sockets at all, so the web build posts the message to
///    the `send-mail` edge function, which reads the same row and sends it
///    with nodemailer. Deploy it once with
///    `supabase functions deploy send-mail --no-verify-jwt`.
class EmailSender {
  const EmailSender._();

  static Future<EmailResult> send({
    required String to,
    required String subject,
    required String text,
    required String html,
  }) async {
    final EmailSettings? settings = await EmailSettings.load();
    if (settings == null || !settings.usable) {
      return const EmailResult.failure(
        'Email is not set up yet. Run supabase/email.sql and add your SMTP '
        'details to the email_settings table, then try again.',
      );
    }

    try {
      if (kIsWeb) {
        final FunctionResponse response =
            await Supabase.instance.client.functions.invoke(
          'send-mail',
          body: <String, dynamic>{
            'to': to,
            'subject': subject,
            'text': text,
            'html': html,
          },
        );
        final dynamic data = response.data;
        final bool sent = data is Map && data['ok'] == true;
        if (response.status != 200 || !sent) {
          final String reason = data is Map
              ? (data['error']?.toString() ?? 'the mail service refused it')
              : 'the mail service refused it';
          return EmailResult.failure('Could not send the email: $reason');
        }
        return const EmailResult.ok('Email sent.');
      }

      await DirectMailer.send(
        host: settings.host,
        port: settings.port,
        username: settings.username,
        password: settings.password,
        senderName: settings.senderName,
        to: to,
        subject: subject,
        text: text,
        html: html,
      );
      return const EmailResult.ok('Email sent.');
    } on FunctionException catch (error) {
      debugPrint('send-mail function failed: ${error.details}');
      return const EmailResult.failure(
        'The web mail service is not deployed yet. Run '
        '`supabase functions deploy send-mail --no-verify-jwt`, then try again.',
      );
    } catch (error) {
      debugPrint('Could not send mail: $error');
      return EmailResult.failure(
        'Could not send the email. Check the SMTP details in email_settings. '
        '($error)',
      );
    }
  }
}
