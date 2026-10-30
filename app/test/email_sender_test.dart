// An account screen has to say what happened in words a player can act on: a
// message that did not go out must never read as sent, and a build without a
// mail service has to name the settings that are missing. These pin the
// sentence for each answer the service can give.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mon/services/email_sender.dart';
import 'package:mon/services/mail_api.dart';

MailApi _service(
  int status,
  String body, {
  String baseUrl = 'https://mail.example',
}) =>
    MailApi(
      baseUrl: baseUrl,
      token: 'token-123',
      client: MockClient((_) async => http.Response(body, status)),
    );

Future<EmailResult> _send(MailApi service) => EmailSender.send(
      to: 'alice@example.com',
      subject: 'Verify your BankPop account',
      text: 'plain body',
      html: '<b>html body</b>',
      via: service,
    );

void main() {
  test('a delivered message reports success', () async {
    final EmailResult result =
        await _send(_service(200, '{"sent":true,"recipients":1}'));

    expect(result.ok, isTrue);
    expect(result.message, 'Email sent.');
  });

  test('a build without a mail service names the settings it needs', () async {
    final EmailResult result =
        await _send(MailApi(baseUrl: '', token: 'token-123'));

    expect(result.ok, isFalse);
    expect(result.message, contains('MAIL_API_URL'));
    expect(result.message, contains('MAIL_API_TOKEN'));
  });

  test('a token the service does not recognise is called out as such', () async {
    final EmailResult result =
        await _send(_service(401, '{"error":"unauthorized"}'));

    expect(result.ok, isFalse);
    expect(result.message, contains('MAIL_API_TOKEN'));
  });

  test('a row the service cannot send with is reported, not swallowed', () async {
    final EmailResult result = await _send(
      _service(
        503,
        '{"error":"provider is smtp, so email_settings needs host, username and password."}',
      ),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('mail account'));
    expect(result.message, contains('email_settings'));
  });

  test('a refused message says which field was wrong', () async {
    final EmailResult result = await _send(
      _service(400, '{"error":"invalid request","fields":{"to":"invalid email address: nope"}}'),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('to: invalid email address: nope'));
  });

  test('the rate limit asks for patience instead of failing silently', () async {
    final EmailResult result = await _send(
      _service(429, '{"error":"too many requests, try again later"}'),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('Too many emails'));
  });

  test('a mailbox the provider rejected is not blamed on the player', () async {
    final EmailResult result = await _send(
      _service(502, '{"error":"the mail provider rejected the message"}'),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('app password'));
  });

  test('a service that cannot be reached is not reported as sent', () async {
    final EmailResult result = await _send(
      MailApi(
        baseUrl: 'https://mail.example',
        token: 'token-123',
        client: MockClient((_) async => throw Exception('connection refused')),
      ),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('Could not reach the mail service'));
  });
}
