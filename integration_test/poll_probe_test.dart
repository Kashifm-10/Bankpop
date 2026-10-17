// Dev-only probe that measures how much traffic the polling screens generate.
//
// Start the mock server first, then run on a device/emulator:
//
//   dart run tool/mock_supabase.dart
//   flutter test integration_test/poll_probe_test.dart -d <device>
//
// It pumps the real screens, lets the real timers run for a fixed window, and
// prints the request counters collected by the mock server.

import 'dart:convert';
import 'dart:io';

import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mon/pages/banker/banker_screen.dart';
import 'package:mon/pages/player/player_screen.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Reached through `adb reverse tcp:8787 tcp:8787`, which forwards the device's
// loopback to the host's mock server. 10.0.2.2 works too when the host firewall
// allows inbound connections from the emulator.
const String mockBase = 'http://127.0.0.1:8787';

// Long enough to show the reconciliation cadence doing its job. The screens are
// event-driven now, so this window measures the safety net, not the update path.
const Duration window = Duration(seconds: 30);

bool _initialised = false;

// Every helper is timeout-bounded: a wedged mock server must never hang a run.
const Duration _httpTimeout = Duration(seconds: 5);

Future<String?> _get(String url) async {
  final HttpClient client = HttpClient()..connectionTimeout = _httpTimeout;
  try {
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    final HttpClientResponse response =
        await request.close().timeout(_httpTimeout);
    return await response.transform(utf8.decoder).join().timeout(_httpTimeout);
  } catch (error) {
    debugPrint('PROBE http get failed: $error');
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> _post(String url) async {
  final HttpClient client = HttpClient()..connectionTimeout = _httpTimeout;
  try {
    final HttpClientRequest request = await client.postUrl(Uri.parse(url));
    final HttpClientResponse response =
        await request.close().timeout(_httpTimeout);
    await response.drain<void>().timeout(_httpTimeout);
  } catch (error) {
    debugPrint('PROBE http post failed: $error');
  } finally {
    client.close(force: true);
  }
}

Future<void> _useMockBackend() async {
  if (!_initialised) {
    await Supabase.initialize(url: mockBase, anonKey: 'probe-key');
    _initialised = true;
  }
  await _post('$mockBase/__reset');
}

Future<Map<String, dynamic>?> _stats() async {
  final String? body = await _get('$mockBase/__stats');
  if (body == null) return null;
  return jsonDecode(body) as Map<String, dynamic>;
}

void _report(String label, Map<String, dynamic>? stats) {
  if (stats == null) {
    debugPrint('PROBE $label stats unavailable (see mock server stdout)');
    return;
  }
  final int total = stats['total'] as int;
  final num elapsed = stats['elapsedSeconds'] as num;
  final num perSecond = stats['requestsPerSecond'] as num;
  debugPrint('PROBE $label total=$total elapsed=${elapsed}s '
      'reqPerSec=${perSecond.toStringAsFixed(1)}');
  final Map<String, dynamic> buckets =
      Map<String, dynamic>.from(stats['perSecond'] as Map);
  final List<MapEntry<String, dynamic>> entries = buckets.entries.toList()
    ..sort((MapEntry<String, dynamic> a, MapEntry<String, dynamic> b) =>
        int.parse(a.key).compareTo(int.parse(b.key)));
  debugPrint('PROBE $label perSecond='
      '${entries.map((MapEntry<String, dynamic> e) => '${e.key}s=${e.value}').join(' ')}');
  final Map<String, dynamic> byPath =
      Map<String, dynamic>.from(stats['byPath'] as Map);
  debugPrint('PROBE $label byPath='
      '${byPath.entries.map((MapEntry<String, dynamic> e) => '${e.key.replaceAll('/rest/v1/', '')}=${e.value}').join(' ')}');
  // Proves the screen tried the socket first and kept working without it.
  debugPrint('PROBE $label realtimeSocketAttempts='
      '${stats['realtimeAttempts'] ?? 0}');
}

/// The real app wraps everything in ResponsiveSizer (see main.dart), which is
/// what initialises the `Device` metrics the screens use for `.sp`/`.h` sizes.
Widget _app(Widget home) => ResponsiveSizer(
      builder: (BuildContext context, Orientation orientation, ScreenType type) =>
          MaterialApp(home: home),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Must contain at least four digits: the wallet card slices the id with
    // replaceAll(RegExp(r'\D'), '').substring(0, 4).
    SharedPreferences.setMockInitialValues(<String, Object>{
      'playerID': 'p1r2o3b4e5',
      'profile_name': 'Probe',
      'gameID': 'ABC12',
      'playerValue': 1000.0,
      'advance': 200.0,
    });
  });

  testWidgets('banker screen polling load', (WidgetTester tester) async {
    await tester.runAsync(_useMockBackend);

    await tester.pumpWidget(_app(
      const BankerGameScreen(bankValue: 10000, gameId: 'ABC12'),
    ));

    await tester.runAsync(() => Future<void>.delayed(window));

    // runAsync lets real timers fire but pumps no frames, so flush the setState
    // work the polls queued before reading the tree.
    await tester.pump(const Duration(milliseconds: 50));

    Map<String, dynamic>? stats;
    await tester.runAsync(() async => stats = await _stats());
    _report('banker', stats);

    // The header label only exists once the screen has built, and the counter
    // proves the polled bank wallet reached the UI.
    expect(find.textContaining('Bankpop Union'), findsWidgets);
    expect(
      tester
          .widgetList<AnimatedFlipCounter>(find.byType(AnimatedFlipCounter))
          .any((AnimatedFlipCounter c) => c.value == 8888.0),
      isTrue,
      reason: 'polled bank wallet should be rendered',
    );
  });

  testWidgets('player screen polling load', (WidgetTester tester) async {
    await tester.runAsync(_useMockBackend);

    await tester.pumpWidget(_app(
      const PlayersScreen(bankValue: 10000, gameId: 'ABC12'),
    ));

    await tester.runAsync(() => Future<void>.delayed(window));

    // runAsync lets real timers fire but pumps no frames, so flush the setState
    // work the polls queued before reading the tree.
    await tester.pump(const Duration(milliseconds: 50));

    Map<String, dynamic>? stats;
    await tester.runAsync(() async => stats = await _stats());
    _report('player', stats);

    // A spinner replaces the list while isLoading, so the list being built
    // proves the roster poll landed; the counter proves the wallet derived from
    // that same roster reached the UI.
    expect(find.byType(ListView), findsWidgets);
    expect(
      tester
          .widgetList<AnimatedFlipCounter>(find.byType(AnimatedFlipCounter))
          .any((AnimatedFlipCounter c) => c.value == 7777.0),
      isTrue,
      reason: 'wallet derived from the roster should be rendered',
    );
  });
}
