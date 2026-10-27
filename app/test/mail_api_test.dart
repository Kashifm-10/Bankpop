// The app posts one message to the Bankpop mail service (django-mail-api/) and
// reads its answer. These pin the request that leaves the app and what each
// answer means, without a network or a server.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mon/services/mail_api.dart';

MailApi _service(Future<http.Response> Function(http.Request) answer,
        {String baseUrl = 'https://mail.example', String token = 'token-123'}) =>
    MailApi(baseUrl: baseUrl, token: token, client: MockClient(answer));

void main() {
  test('posts the message to the service, with the token', () async {
    late http.Request sent;
    final MailApi api = _service((http.Request request) async {
      sent = request;
      return http.Response('{"sent":true,"recipients":1}', 200);
    });

    await api.send(
      to: 'alice@example.com',
      subject: 'Verify your BankPop account',
      text: 'plain body',
      html: '<b>html body</b>',
    );

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://mail.example/api/send-mail/');
    expect(sent.headers['Authorization'], 'Bearer token-123');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), <String, dynamic>{
      'to': 'alice@example.com',
      'subject': 'Verify your BankPop account',
      'text': 'plain body',
      'html': '<b>html body</b>',
    });
  });

  test('a trailing slash in the address does not double up', () async {
    late http.Request sent;
    final MailApi api = _service(
      (http.Request request) async {
        sent = request;
        return http.Response('{"sent":true}', 200);
      },
      baseUrl: 'https://mail.example//',
    );

    await api.send(to: 'a@b.com', subject: 'Hi', text: 'x', html: 'y');

    expect(sent.url.toString(), 'https://mail.example/api/send-mail/');
  });

  test('a build without an address is not configured', () {
    expect(MailApi(baseUrl: '', token: 'token').configured, isFalse);
    // Nothing was passed with --dart-define either.
    expect(MailApi().configured, isFalse);
  });

  test('a refusal keeps the status and the service\'s own words', () async {
    final MailApi api =
        _service((_) async => http.Response('{"error":"unauthorized"}', 401));

    await expectLater(
      api.send(to: 'a@b.com', subject: 'Hi', text: 'x', html: 'y'),
      throwsA(
        isA<MailApiException>()
            .having((MailApiException e) => e.statusCode, 'statusCode', 401)
            .having((MailApiException e) => e.message, 'message', 'unauthorized')
            .having((MailApiException e) => e.unreachable, 'unreachable', isFalse),
      ),
    );
  });

  test('a 400 keeps the per-field problems', () async {
    final MailApi api = _service(
      (_) async => http.Response(
        '{"error":"invalid request","fields":{"to":"invalid email address: nope"}}',
        400,
      ),
    );

    await expectLater(
      api.send(to: 'nope', subject: 'Hi', text: 'x', html: 'y'),
      throwsA(
        isA<MailApiException>()
            .having((MailApiException e) => e.statusCode, 'statusCode', 400)
            .having((MailApiException e) => e.fields['to'], 'fields[to]',
                'invalid email address: nope'),
      ),
    );
  });

  test('an unanswered request is unreachable, not a refusal', () async {
    final MailApi api = _service((_) async => throw Exception('connection reset'));

    await expectLater(
      api.send(to: 'a@b.com', subject: 'Hi', text: 'x', html: 'y'),
      throwsA(
        isA<MailApiException>()
            .having((MailApiException e) => e.unreachable, 'unreachable', isTrue)
            .having((MailApiException e) => e.statusCode, 'statusCode', 0),
      ),
    );
  });

  test('an answer that is not JSON still names the status', () async {
    final MailApi api = _service(
      (_) async => http.Response('<html>Bad gateway</html>', 502),
    );

    await expectLater(
      api.send(to: 'a@b.com', subject: 'Hi', text: 'x', html: 'y'),
      throwsA(
        isA<MailApiException>()
            .having((MailApiException e) => e.statusCode, 'statusCode', 502)
            .having((MailApiException e) => e.message, 'message',
                contains('HTTP 502')),
      ),
    );
  });
}
