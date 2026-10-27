import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The SMTP account the app sends its own mail with.
///
/// It lives in `email_settings` (see supabase/email.sql) rather than in the
/// build, so the mailbox and its app password can be changed without shipping
/// a new release. The row is read at the moment a mail is sent, not cached:
/// rotating the password takes effect on the next message.
///
/// The publishable key can read this row, which is the price of sending
/// straight from the app on a phone (there is no server in that path). Use a
/// mailbox made only for this app, with an app password that can be revoked,
/// and prefer the `send-mail` edge function on web where the browser cannot
/// open an SMTP connection at all.
class EmailSettings {
  const EmailSettings({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.senderName,
    required this.appUrl,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String senderName;

  /// Where the verification link should point, e.g. `https://bankpop.app`.
  /// Empty means "work it out": the browser knows its own origin, a phone
  /// asks for this column to be filled in.
  final String appUrl;

  bool get usable =>
      host.trim().isNotEmpty &&
      port > 0 &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  /// The mailbox the mail comes from. Kept as the username: Gmail, and most
  /// providers, reject a From that is not the authenticated account.
  String get fromAddress => username.trim();

  /// The public address of this build, without a trailing slash.
  ///
  /// The verification link has to open the web app from a mail client, which
  /// is a different origin from the one a phone is running in - so the web
  /// build answers this with the address bar, and a phone falls back to the
  /// configured `app_url`.
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
          .from('email_settings')
          .select()
          .eq('enabled', true)
          .order('updated_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      return fromRow((rows.first as Map).cast<String, dynamic>());
    } on PostgrestException catch (error) {
      debugPrint('Could not read email_settings: ${error.message}');
      return null;
    } catch (error) {
      debugPrint('Could not read email_settings: $error');
      return null;
    }
  }

  static EmailSettings fromRow(Map<String, dynamic> row) => EmailSettings(
        host: row['host']?.toString() ?? '',
        port: (row['port'] as num?)?.toInt() ?? 0,
        username: row['username']?.toString() ?? '',
        password: row['password']?.toString() ?? '',
        senderName: (row['sender_name']?.toString().trim().isNotEmpty ?? false)
            ? row['sender_name'].toString().trim()
            : 'BankPop',
        appUrl: row['app_url']?.toString() ?? '',
      );
}
