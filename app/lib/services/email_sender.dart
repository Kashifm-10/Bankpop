import 'package:flutter/foundation.dart';
import 'package:mon/services/mail_api.dart';

/// What happened to one mail.
class EmailResult {
  const EmailResult.ok(this.message) : ok = true;
  const EmailResult.failure(this.message) : ok = false;

  final bool ok;
  final String message;
}

/// Sends one message through the Bankpop mail service (the Django project in
/// `django-mail-api/`).
///
/// The mailbox is not in the app and not in this build: the service reads it
/// from the `email_settings` row in Supabase (see `supabase/mail_provider.sql`)
/// and sends the message. Replacing the mailbox, or rotating its app password,
/// is therefore a row update rather than a new release - and no install ever
/// holds the password.
///
/// The build needs the service's address and token:
///
/// ```
/// flutter run --dart-define=MAIL_API_URL=https://mail.example \
///             --dart-define=MAIL_API_TOKEN=<MAIL_API_TOKEN of the service>
/// ```
class EmailSender {
  const EmailSender._();

  /// Sends the message, and turns a refusal into a sentence an account screen
  /// can show. [via] is for tests: the real call uses the build's own service.
  static Future<EmailResult> send({
    required String to,
    required String subject,
    required String text,
    required String html,
    MailApi? via,
  }) async {
    final MailApi service = via ?? MailApi();
    if (!service.configured) {
      return const EmailResult.failure(
        'This build has no mail service. Build it with '
        '--dart-define=MAIL_API_URL=<the django-mail-api address> and '
        '--dart-define=MAIL_API_TOKEN=<that service\'s MAIL_API_TOKEN>.',
      );
    }

    try {
      await service.send(to: to, subject: subject, text: text, html: html);
      return const EmailResult.ok('Email sent.');
    } on MailApiException catch (error) {
      debugPrint('The mail service refused the message: $error');
      return EmailResult.failure(_sentence(error, hasToken: service.token.isNotEmpty));
    } catch (error) {
      debugPrint('Could not send mail: $error');
      return const EmailResult.failure(
        'Could not send the email. Check your connection and try again.',
      );
    }
  }

  /// The refusal, in the words of the screen that asked.
  static String _sentence(MailApiException error, {required bool hasToken}) {
    if (error.unreachable) {
      return 'Could not reach the mail service (${error.message}). Check '
          'MAIL_API_URL and that the service is running.';
    }
    switch (error.statusCode) {
      case 400:
        final String problems = error.fields.entries
            .map((MapEntry<String, String> field) =>
                '${field.key}: ${field.value}')
            .join(', ');
        return problems.isEmpty
            ? 'The mail service refused the message: ${error.message}.'
            : 'The mail service refused the message ($problems).';
      case 401:
        // Two very different mistakes produce the same 401, and the screen
        // used to name only the first: a build that carries no token at all,
        // and one whose token the service does not recognise.
        return hasToken
            ? 'The mail service refused this build\'s token. Check '
                'MAIL_API_TOKEN against the service\'s own value.'
            : 'This build has no mail token, so the service turned the message '
                'away. Run the app with ./dev.sh (it passes the token), or '
                'build with --dart-define=MAIL_API_TOKEN=<the service value>.';
      case 429:
        return 'Too many emails were sent a moment ago. Try again later.';
      case 502:
        return 'The mail service could not send the message: the mailbox in '
            'email_settings may be wrong, or its app password has been '
            'revoked.';
      case 503:
        return 'The mail service has no usable mail account yet: '
            '${error.message}';
      default:
        return 'Could not send the email: ${error.message}.';
    }
  }
}
