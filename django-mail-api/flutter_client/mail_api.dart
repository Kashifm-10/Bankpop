// Client for the Django mail API. Works on Flutter web, Android, iOS and desktop.
//
// pubspec.yaml:
//   dependencies:
//     http: ^1.2.0
//
// Pass the URL and token at build time instead of hard-coding them:
//   flutter run -d chrome \
//     --dart-define=MAIL_API_URL=https://your-app.wasmer.app \
//     --dart-define=MAIL_API_TOKEN=xxxx
//
// Anything compiled into an app (especially a web app) can be read by its
// users, so treat the token as a speed bump, not a secret. The server's
// recipient allowlist and rate limit are what stop abuse.

import 'dart:convert';

import 'package:http/http.dart' as http;

class MailApiException implements Exception {
  MailApiException(this.statusCode, this.message, [this.fields = const {}]);

  final int statusCode;
  final String message;
  final Map<String, dynamic> fields;

  @override
  String toString() => 'MailApiException($statusCode): $message $fields';
}

class MailApi {
  MailApi({String? baseUrl, String? token, http.Client? client})
      : baseUrl = baseUrl ?? const String.fromEnvironment('MAIL_API_URL'),
        token = token ?? const String.fromEnvironment('MAIL_API_TOKEN'),
        _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _client;

  /// Sends an email. Throws [MailApiException] if the server refuses it.
  Future<void> send({
    required List<String> to,
    required String subject,
    String? text,
    String? html,
    List<String> cc = const [],
    List<String> bcc = const [],
    List<String> replyTo = const [],
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/send-mail/'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'to': to,
        'subject': subject,
        if (text != null) 'text': text,
        if (html != null) 'html': html,
        if (cc.isNotEmpty) 'cc': cc,
        if (bcc.isNotEmpty) 'bcc': bcc,
        if (replyTo.isNotEmpty) 'reply_to': replyTo,
      }),
    );

    if (response.statusCode == 200) return;

    var message = 'HTTP ${response.statusCode}';
    var fields = <String, dynamic>{};
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      message = body['error'] as String? ?? message;
      fields = (body['fields'] as Map<String, dynamic>?) ?? {};
    } on FormatException {
      // Non-JSON error page from a proxy; keep the status code message.
    }
    throw MailApiException(response.statusCode, message, fields);
  }
}

// Example:
//
//   final api = MailApi();
//   try {
//     await api.send(
//       to: ['someone@example.com'],
//       subject: 'Hello from Flutter',
//       text: 'Plain text body',
//       html: '<p>HTML <b>body</b></p>',
//     );
//   } on MailApiException catch (e) {
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
//   }
