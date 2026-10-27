import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the mail service said when it would not take a message.
class MailApiException implements Exception {
  const MailApiException(
    this.message, {
    this.statusCode = 0,
    this.fields = const <String, String>{},
  });

  /// The `error` in the service's answer, or the failure to reach it.
  final String message;

  /// The HTTP status, or 0 when the service could not be reached at all.
  final int statusCode;

  /// Per-field problems from a 400, e.g. `{'to': 'invalid email address: x'}`.
  final Map<String, String> fields;

  /// True when nothing answered: a wrong address, or the service is down.
  bool get unreachable => statusCode == 0;

  @override
  String toString() => 'MailApiException($statusCode): $message';
}

/// The Bankpop mail service: the Django project in `django-mail-api/`.
///
/// The app never opens an SMTP connection. A browser has no sockets at all, and
/// a phone that holds the mailbox would mean every install holds its password.
/// The service keeps the mailbox, reads it from the `email_settings` row in
/// Supabase, and this client posts one message to it.
///
/// Its address and shared token are build settings rather than constants, so a
/// deployed service can move without the app guessing:
///
/// ```
/// flutter run -d chrome \
///   --dart-define=MAIL_API_URL=https://mail.bankpop.example \
///   --dart-define=MAIL_API_TOKEN=<the service's MAIL_API_TOKEN>
/// ```
///
/// Anything compiled into a web build can be read by whoever opens it, so the
/// token is a speed bump rather than a secret. What stops abuse is on the
/// server: the recipient allowlist, the rate limit and the fixed sender.
class MailApi {
  MailApi({String? baseUrl, String? token, http.Client? client})
      : baseUrl = (baseUrl ?? _configuredUrl).trim().replaceAll(
            RegExp(r'/+$'),
            '',
          ),
        token = (token ?? _configuredToken).trim(),
        _client = client ?? http.Client();

  /// The address given at build time with `--dart-define=MAIL_API_URL=...`.
  static const String _configuredUrl = String.fromEnvironment('MAIL_API_URL');
  static const String _configuredToken =
      String.fromEnvironment('MAIL_API_TOKEN');

  /// How long to wait for the service before giving up. Sending is a small
  /// request; a service that takes longer than this is not coming back.
  static const Duration timeout = Duration(seconds: 30);

  final String baseUrl;
  final String token;
  final http.Client _client;

  /// False when the build was made without a service address.
  bool get configured => baseUrl.isNotEmpty;

  /// Sends one message, or throws [MailApiException].
  Future<void> send({
    required String to,
    required String subject,
    required String text,
    required String html,
  }) async {
    if (!configured) {
      throw const MailApiException('no mail service in this build');
    }

    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$baseUrl/api/send-mail/'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'to': to,
              'subject': subject,
              'text': text,
              'html': html,
            }),
          )
          .timeout(timeout);
    } catch (error) {
      // Nothing answered: a wrong address, no network, or a service that is
      // not running. The screen's job is to say so, not to show a stack trace.
      throw MailApiException('could not reach $baseUrl ($error)');
    }

    if (response.statusCode == 200) return;

    throw MailApiException(
      _readMessage(response),
      statusCode: response.statusCode,
      fields: _readFields(response),
    );
  }

  /// The service's own wording, or a plain fallback when the answer was not
  /// JSON (a proxy's error page, say).
  static String _readMessage(http.Response response) {
    try {
      final dynamic body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) return body['error'].toString();
    } catch (_) {
      // Not JSON: fall through to the status line.
    }
    return 'the mail service answered HTTP ${response.statusCode}';
  }

  static Map<String, String> _readFields(http.Response response) {
    try {
      final dynamic body = jsonDecode(response.body);
      final dynamic fields = body is Map ? body['fields'] : null;
      if (fields is Map) {
        return <String, String>{
          for (final MapEntry<dynamic, dynamic> field in fields.entries)
            field.key.toString(): field.value.toString(),
        };
      }
    } catch (_) {
      // No per-field detail to report.
    }
    return const <String, String>{};
  }
}
