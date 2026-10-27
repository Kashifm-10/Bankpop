// The banker screen keeps the board in view instead of behind a button, so the
// screen reads: the bank's own row (balance and the QR a player pays), then the
// board with the players beside it on a wide window and under it on a phone.
// These pin that order and check the layout still fits the window sizes the app
// runs in. The backend is a closed port, so every request fails immediately and
// the screen draws its empty/loading state - the layout around it is what is
// being measured.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/pages/banker/banker_screen.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/banker_board_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The half of the screen the players are drawn in.
Finder get _players => find.byKey(const ValueKey<String>('banker-players'));

Widget _screen() => MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          AppFrame(child: child ?? const SizedBox.shrink()),
      home: const BankerGameScreen(bankValue: 1500, gameId: 'ABC12'),
    );

/// Sets the window the test draws in.
void _window(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Leaves the screen so its periodic board refresh is cancelled before the test
/// ends.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'playerID': 'banker1',
      'profile_name': 'Banker',
    });
    // A URL that refuses connections: the screen's reads fail, are caught, and
    // it keeps the layout it builds before any data arrives.
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('a phone reads bank row, board, players', (WidgetTester tester) async {
    _window(tester, const Size(390, 844));

    await tester.pumpWidget(_screen());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Bankpop Union'), findsOneWidget);
    expect(find.byType(BankerBoardPanel), findsOneWidget);

    final double bank = tester.getRect(find.text('Bankpop Union')).top;
    final Rect board = tester.getRect(find.byType(BankerBoardPanel));
    final Rect players = tester.getRect(_players);

    expect(bank, lessThan(board.top), reason: 'the bank row is above the board');
    expect(board.bottom, lessThanOrEqualTo(players.top + 1),
        reason: 'the players are under the board on a phone');
    // The board is exactly as wide as a row of the list, so no empty paper is
    // left down either side of it: the same inset, either side.
    expect(board.width, moreOrLessEquals(players.width - 32, epsilon: 1));
    // A square, and a region cut to its own size.
    expect(board.width, moreOrLessEquals(board.height, epsilon: 1));

    await _unmount(tester);
  });

  testWidgets('a wide window puts the players beside the board',
      (WidgetTester tester) async {
    _window(tester, const Size(1440, 900));

    await tester.pumpWidget(_screen());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BankerBoardPanel), findsOneWidget);

    final Rect board = tester.getRect(find.byType(BankerBoardPanel));
    final Rect players = tester.getRect(_players);

    expect(players.left, greaterThanOrEqualTo(board.right - 1),
        reason: 'the players are to the right of the board on a wide window');
    // Side by side, and both starting at the top of the band they share: the
    // board used to hang below a strip of empty paper the players did not have.
    expect(board.top, moreOrLessEquals(players.top, epsilon: 1));

    // What the board panel is showing sits at its top, not in the middle of it.
    final Finder shown = find.descendant(
      of: find.byType(BankerBoardPanel),
      matching: find.byWidgetPredicate(
        (Widget widget) =>
            widget is Text || widget is CircularProgressIndicator,
      ),
    );
    expect(shown, findsOneWidget);
    expect(tester.getRect(shown).top, moreOrLessEquals(board.top, epsilon: 2));

    await _unmount(tester);
  });

  for (final Size size in <Size>[
    const Size(320, 568),
    const Size(390, 844),
    const Size(800, 400),
    const Size(1440, 900),
  ]) {
    testWidgets('the banker screen fits ${size.width}x${size.height}',
        (WidgetTester tester) async {
      _window(tester, size);

      await tester.pumpWidget(_screen());
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull,
          reason: 'the banker screen overflowed at ${size.width}x${size.height}');

      await _unmount(tester);
    });
  }
}
