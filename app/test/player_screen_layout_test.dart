// The player screen is the densest layout in the app (wallet card, action
// row, roster). These pump it through the responsive frame at the sizes the app
// has to fit and fail on any overflow. The backend is a closed port, so every
// request fails immediately and the screen draws its empty/loading state - the
// layout around it is what is being measured.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/pages/player/player_screen.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/game_controls.dart';
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

  // The wallet card used to fill the content column at every width, which left
  // its action stickers in a row of their own at the far right of a wide
  // window. A wide window now narrows the card and puts the actions beside it;
  // a phone keeps them stacked underneath.
  testWidgets('a wide window puts the wallet actions beside the card',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
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
    expect(tester.takeException(), isNull);

    final Rect card = tester.getRect(find.byType(Card).first);
    expect(card.width, lessThan(760),
        reason: 'the card should no longer fill a 1440 px window');

    final List<Rect> stickers = <Rect>[
      for (final Element element in find.byType(GameIconButton).evaluate())
        tester.getRect(find.byWidget(element.widget)),
    ];
    final Iterable<Rect> beside = stickers.where(
      (Rect sticker) =>
          sticker.center.dx > card.right && sticker.center.dy > card.top,
    );
    expect(beside, isNotEmpty,
        reason: 'the wallet actions should sit to the right of the card');

    // The right-hand side is a grid whose shape follows the game's buttons,
    // sized from the space the card leaves: the stickers grow past their phone
    // size and stack in rows rather than trailing off in one long line.
    final List<Rect> grid = beside.toList();
    final double widest =
        grid.map((Rect sticker) => sticker.width).reduce((a, b) => a > b ? a : b);
    expect(widest, greaterThan(60),
        reason: 'stickers should grow into the right-hand space');
    final int rows = grid.map((Rect s) => s.top.round()).toSet().length;
    expect(rows, greaterThan(1),
        reason: 'three buttons should make a two-row grid, not one line');
    final int columns = grid.map((Rect s) => s.left.round()).toSet().length;
    expect(columns, 2, reason: 'three buttons tile two columns of two');

    // The grid fills the block instead of sitting in the middle of it: the
    // first cell starts where the card ends, and the last one runs to the
    // right-hand gutter of the content column.
    final double leftmost =
        grid.map((Rect s) => s.left).reduce((a, b) => a < b ? a : b);
    final double rightmost =
        grid.map((Rect s) => s.right).reduce((a, b) => a > b ? a : b);
    expect(leftmost - card.right, lessThanOrEqualTo(8),
        reason: 'the grid should start at the card, not float away from it');
    expect(rightmost - card.right, greaterThan(190),
        reason: 'the grid should reach across the space beside the card');
  });

  testWidgets('a phone keeps the wallet actions under the card',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
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
    expect(tester.takeException(), isNull);

    final Rect card = tester.getRect(find.byType(Card).first);
    final List<Rect> stickers = <Rect>[
      for (final Element element in find.byType(GameIconButton).evaluate())
        tester.getRect(find.byWidget(element.widget)),
    ];
    expect(
      stickers.any((Rect sticker) => sticker.center.dy > card.bottom),
      isTrue,
      reason: 'a phone stacks the actions under the card',
    );
  });
}
