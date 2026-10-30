import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
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
/// The address follows the page the app is running on, so one local build
/// finds the service `./dev.sh` starts and a deployed build finds the hosted
/// one (see [resolveBaseUrl]); `--dart-define=MAIL_API_URL=...` overrides that
/// when a build has to point somewhere else.
///
/// ```
/// flutter run -d chrome \
///   --dart-define=MAIL_API_TOKEN=<the service's MAIL_API_TOKEN>
/// ```
///
/// Anything compiled into a web build can be read by whoever opens it, so the
/// token is a speed bump rather than a secret. What stops abuse is on the
/// server: the recipient allowlist, the rate limit and the fixed sender.
class MailApi {
  MailApi({
    String? baseUrl,
    String? token,
    http.Client? client,
    String? origin,
  })  : baseUrl = _normalise(baseUrl ?? resolveBaseUrl(origin: origin)),
        token = (token ?? _configuredToken).trim(),
        _client = client ?? http.Client();

  /// The address given at build time with `--dart-define=MAIL_API_URL=...`.
  static const String _configuredUrl = String.fromEnvironment('MAIL_API_URL');
  static const String _configuredToken =
      String.fromEnvironment('MAIL_API_TOKEN');

  /// Where `./dev.sh` and `docker compose up` put the mail service.
  static const String localService = 'http://127.0.0.1:8000';

  /// Where the deployed service will live once it is hosted.
  ///
  /// The deployed app is https://bankpop.netlify.app, so any page that is not
  /// on loopback posts here. Fill this in (or build with
  /// `--dart-define=MAIL_API_HOSTED_URL=...`) and the deployed app finds its
  /// service without any other setting; empty until then, which makes a hosted
  /// build say it has no mail service instead of posting into nothing.
  static const String hostedService = '';

  /// `--dart-define=MAIL_API_HOSTED_URL=...`, or [hostedService].
  static const String _configuredHostedUrl = String.fromEnvironment(
    'MAIL_API_HOSTED_URL',
    defaultValue: hostedService,
  );

  /// The address to talk to, chosen from where the app is running.
  ///
  /// Three places disagree about where the service is, and one build has to
  /// work in all of them:
  ///
  ///   * on the developer's machine (`localhost` or `127.0.0.1`, any port) it
  ///     is the loopback service the dev script starts;
  ///   * on the deployed site it is the hosted service;
  ///   * on a phone it is the hosted service too - a phone's own localhost is
  ///     the phone, not the computer the service runs on.
  ///
  /// A `--dart-define=MAIL_API_URL` wins over all of that, which is how a
  /// staging build points at a staging service.
  static String resolveBaseUrl({
    String? origin,
    String buildUrl = _configuredUrl,
    String hostedUrl = _configuredHostedUrl,
    String localUrl = localService,
  }) {
    final String explicit = buildUrl.trim();
    if (explicit.isNotEmpty) return explicit;
    // Outside a browser there is no page to read an origin from, and a
    // handset cannot reach the developer's loopback address anyway.
    final String page = origin ?? (kIsWeb ? Uri.base.origin : '');
    if (_isLoopback(page)) return localUrl;
    return hostedUrl.trim();
  }

  /// True for `http://localhost:5180`, `http://127.0.0.1:8000`, `[::1]:...`.
  static bool _isLoopback(String origin) {
    if (origin.isEmpty) return false;
    final String host = Uri.tryParse(origin)?.host ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  static String _normalise(String url) =>
      url.trim().replaceAll(RegExp(r'/+$'), '');

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
