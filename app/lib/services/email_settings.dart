import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The two public addresses the app needs from the `email_settings` row: where
/// its own web build lives, and where the Django mail service lives.
///
/// The same row also holds the mailbox the service sends through
/// (`supabase/email.sql`, `supabase/mail_provider.sql`). The app is not allowed
/// to read those columns any more - the publishable key it carries is public,
/// and the password is not - so it reads the `email_public_settings` view,
/// which exposes `app_url` and `mail_api_url` and nothing else.
///
/// A verification link has to open the web app from a mail client, which is a
/// different origin from the one a phone is running in, and a phone cannot work
/// out its own public address: `app_url` is what makes the link work on
/// Android and iOS. The browser falls back to its own address bar.
///
/// `mail_api_url` is how a hosted build finds the mail service without a
/// `--dart-define`; hosting the service is a row update rather than a new
/// release. See `supabase/mail_api_url.sql`.
class EmailSettings {
  const EmailSettings({required this.appUrl, this.mailApiUrl = ''});

  /// The public address of the web build, e.g. `https://bankpop.app`.
  final String appUrl;

  /// The public base URL of the mail service, e.g. `https://mail.bankpop.app`.
  /// Empty until the service is hosted and this column is filled in.
  final String mailApiUrl;

  /// The same address without a trailing slash, or empty when it is unset.
  String get resolvedAppUrl {
    final String configured = appUrl.trim();
    if (configured.isNotEmpty) {
      return configured.replaceAll(RegExp(r'/+$'), '');
    }
    if (kIsWeb) return Uri.base.origin;
    return '';
  }

  /// The mail service's address without a trailing slash, or empty when the row
  /// has none yet.
  String get resolvedMailApiUrl =>
      mailApiUrl.trim().replaceAll(RegExp(r'/+$'), '');

  static Future<EmailSettings?> load() async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('email_public_settings')
          .select()
          .eq('enabled', true)
          .order('updated_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      return fromRow((rows.first as Map).cast<String, dynamic>());
    } on PostgrestException catch (error) {
      debugPrint('Could not read email_public_settings: ${error.message}');
      return null;
    } catch (error) {
      debugPrint('Could not read email_public_settings: $error');
      return null;
    }
  }

  /// Columns a project that has not run `supabase/mail_api_url.sql` yet does
  /// not have are simply absent, which reads as "unset" rather than failing.
  static EmailSettings fromRow(Map<String, dynamic> row) => EmailSettings(
        appUrl: row['app_url']?.toString() ?? '',
        mailApiUrl: row['mail_api_url']?.toString() ?? '',
      );
}
