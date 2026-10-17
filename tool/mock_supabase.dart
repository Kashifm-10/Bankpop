// Dev-only mock of the Supabase REST (PostgREST) endpoints used by the app.
//
// Purpose: measure how much network traffic the app's polling loops generate,
// without touching production Supabase. It answers the handful of queries the
// banker/player screens issue and counts every request.
//
//   dart run tool/mock_supabase.dart     # listens on 0.0.0.0:8787
//
// It prints a `STATS` line once per second that has traffic, so the counters can
// be read straight from its stdout log:
//   STATS second=3 requests=41 total=123
// GET /__stats returns the same counters as JSON; POST /__reset zeroes them.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int port = 8787;
const String gameId = 'ABC12';

final DateTime startedAt = DateTime.now();
int total = 0;
int realtimeAttempts = 0;
final Map<String, int> byPath = <String, int>{};
final Map<String, int> perSecond = <String, int>{};

int _bucket() => DateTime.now().difference(startedAt).inSeconds;

Map<String, dynamic> bankerRow() => <String, dynamic>{
      'id': 1,
      'game_id': gameId,
      'role': 'banker',
      'name': 'Bank',
      // Differs from the probe's initial bankValue so the probe can prove the
      // polled wallet replaced it.
      'wallet': 8888,
      'player_id': 'banker-player-id',
      'SP/IP': 'InstantPay',
      'avatar': 'assets/avatars/boy1.jpg',
    };

List<Map<String, dynamic>> playerRows() => <Map<String, dynamic>>[
      for (int i = 0; i < 4; i++)
        <String, dynamic>{
          'id': 10 + i,
          'game_id': gameId,
          'role': 'player',
          'name': 'Player $i',
          // The first row matches the probe's device id (at least four digits,
          // which the wallet card requires) and gets a distinctive wallet so the
          // probe can assert the polled value actually reached the UI.
          'wallet': i == 0 ? 7777 : 1000 - i * 100,
          'player_id': i == 0 ? 'p1r2o3b4e5' : 'probe-player-$i',
          'SP/IP': 'InstantPay',
          'avatar': 'assets/avatars/boy${i + 1}.jpg',
        },
    ];

Future<void> main() async {
  final HttpServer server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('mock supabase listening on ${server.address.address}:$port');

  // One STATS line per second of traffic, so the counters survive a client that
  // never reads /__stats.
  Timer.periodic(const Duration(seconds: 1), (_) {
    final String key = '${_bucket() - 1}';
    final int count = perSecond[key] ?? 0;
    if (count > 0) {
      stdout.writeln('STATS second=$key requests=$count total=$total');
    }
  });

  // listen() rather than `await for` so one malformed request can never take
  // the server down.
  server.listen((HttpRequest request) {
    unawaited(_handle(request).catchError((Object error) {
      stderr.writeln('request error: $error');
    }));
  });
}

Future<void> _handle(HttpRequest request) async {
  final String path = request.uri.path;

  // Never block on a body: drain it in the background and answer immediately.
  unawaited(request.drain<void>().catchError((Object _) {}));

  if (path == '/__stats') {
    await _respond(request, HttpStatus.ok, <String, dynamic>{
      'total': total,
      'elapsedSeconds': _bucket(),
      'requestsPerSecond': _bucket() == 0 ? total : total / _bucket(),
      'byPath': byPath,
      'perSecond': perSecond,
      'realtimeAttempts': realtimeAttempts,
    });
    return;
  }
  if (path == '/__reset') {
    total = 0;
    realtimeAttempts = 0;
    byPath.clear();
    perSecond.clear();
    await _respond(request, HttpStatus.ok, <String, dynamic>{'reset': true});
    return;
  }

  // The Realtime socket is a separate channel from REST traffic: the app tries
  // it first and falls back to polling when it cannot connect. Count the
  // attempts, but keep them out of the request totals.
  if (path.startsWith('/realtime')) {
    realtimeAttempts++;
    await _respond(request, HttpStatus.badRequest,
        <String, dynamic>{'message': 'no realtime server here'});
    return;
  }

  total++;
  byPath[path] = (byPath[path] ?? 0) + 1;
  final String key = '${_bucket()}';
  perSecond[key] = (perSecond[key] ?? 0) + 1;

  final String accept = request.headers.value('accept') ?? '';
  final bool wantsSingle = accept.contains('vnd.pgrst.object');
  final Map<String, String> qp = request.uri.queryParameters;
  // PostgREST encodes operators in the value, e.g. role=eq.player.
  String filter(String key) =>
      (qp[key] ?? '').replaceFirst(RegExp(r'^(eq|neq|like|ilike)\.'), '');

  if (path.startsWith('/rest/v1/players_test')) {
    if (wantsSingle) {
      // Mirrors PostgREST returning PGRST116 when a single()/maybeSingle()
      // matches no row; the client maps that to null.
      if (qp.containsKey('player_id') &&
          filter('player_id') != 'banker-player-id') {
        await _respond(request, HttpStatus.notAcceptable, <String, dynamic>{
          'code': 'PGRST116',
          'details': 'Results contain 0 rows',
          'hint': null,
          'message': 'JSON object requested, multiple (or no) rows returned',
        });
        return;
      }
      await _respond(request, HttpStatus.ok, bankerRow());
      return;
    }
    if (filter('role') == 'banker') {
      await _respond(request, HttpStatus.ok, <dynamic>[bankerRow()]);
      return;
    }
    if (filter('role') == 'player') {
      await _respond(request, HttpStatus.ok, playerRows());
      return;
    }
    await _respond(request, HttpStatus.ok, <dynamic>[bankerRow()]);
    return;
  }

  if (request.method == 'GET') {
    await _respond(request, HttpStatus.ok, <dynamic>[]);
    return;
  }
  // insert / update / delete / rpc
  await _respond(request, HttpStatus.created, null);
}

Future<void> _respond(HttpRequest request, int status, Object? body) async {
  try {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.persistentConnection = false;
    if (body != null) request.response.write(jsonEncode(body));
    await request.response.close();
  } catch (error) {
    stderr.writeln('response error: $error');
  }
}
