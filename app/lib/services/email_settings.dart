import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where this build's web app lives, which is what a mail link has to open.
///
/// The `email_settings` row (see `supabase/email.sql` and
/// `supabase/mail_provider.sql`) also holds the mailbox the mail service sends
/// through. The app is not allowed to read those columns any more - the
/// publishable key it carries is public, and the password is not - so it reads
/// the `email_public_settings` view, which exposes `app_url` and nothing else.
///
/// A verification link has to open the web app from a mail client, which is a
/// different origin from the one a phone is running in, and a phone cannot work
/// out its own public address: this column is what makes the link work on
/// Android and iOS. The browser falls back to its own address bar.
class EmailSettings {
  const EmailSettings({required this.appUrl});

  /// The public address of the web build, e.g. `https://bankpop.app`.
  final String appUrl;

  /// The same address without a trailing slash, or empty when it is unset.
  String get resolvedAppUrl {
    final String configured = appUrl.trim();
    if (configured.isNotEmpty) {
      return configured.replaceAll(RegExp(r'/+$'), '');
    }
    if (kIsWeb) return Uri.base.origin;
    return '';
  }

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

  static EmailSettings fromRow(Map<String, dynamic> row) =>
      EmailSettings(appUrl: row['app_url']?.toString() ?? '');
}
