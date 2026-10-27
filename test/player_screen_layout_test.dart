// The player screen is the densest layout in the app (wallet card, action
// row, roster). These pump it through the responsive frame at the sizes the app
// has to fit and fail on any overflow. The backend is a closed port, so every
// request fails immediately and the screen draws its empty/loading state - the
// layout around it is what is being measured.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/pages/player/player_screen.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool _supabaseReady = false;

Widget _screen() => MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          AppFrame(child: child ?? const SizedBox.shrink()),
      home: const PlayersScreen(gameId: 'ABC12', bankValue: 1500),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (!_supabaseReady) {
      // A URL that refuses connections: the screen's reads fail, are caught,
      // and it keeps the layout it builds before any data arrives.
      await Supabase.initialize(
        url: 'http://127.0.0.1:9',
        anonKey: 'test-anon-key',
      );
      _supabaseReady = true;
    }
  });

  testWidgets('the player screen fits every window', (WidgetTester tester) async {
    for (final Size size in <Size>[
      const Size(320, 568),
      const Size(390, 844),
      const Size(800, 400),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'playerID': 'p1r2o3b4e5',
        'profile_name': 'Ameen',
        'display_name': 'Ameen',
        'name': 'Ameen',
      });

      await tester.pumpWidget(_screen());
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.takeException(),
        isNull,
        reason: 'the player screen overflowed at ${size.width}x${size.height}',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
