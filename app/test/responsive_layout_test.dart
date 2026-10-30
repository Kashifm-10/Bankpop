import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/pages/home.dart';
import 'package:mon/pages/role.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/bankpop_space_card.dart';
import 'package:mon/widgets/trade_builder_dialog.dart';
import 'package:mon/widgets/app_metrics.dart';

/// The sizes the app has to survive: a small phone, a normal phone, a phone in
/// landscape, a tablet in portrait and a desktop browser window.
const List<Size> _sizes = <Size>[
  Size(320, 568),
  Size(390, 844),
  Size(800, 400),
  Size(1024, 768),
  Size(1440, 900),
  Size(1920, 1080),
];

/// Puts the app in the responsive frame, exactly as `main.dart` does.
Widget _framed(Widget home) {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) =>
        AppFrame(child: child ?? const SizedBox.shrink()),
    home: home,
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const BankpopSpace _brown = BankpopSpace(
  index: 1,
  name: "Beggar's Alley",
  type: 'Property',
  price: 60,
  rent: <int>[2, 10, 30, 90, 160, 250],
  color: 'Brown',
  houseCost: 50,
  hotelCost: 50,
);

/// Shows the number the sizing layer produces, so a test can prove the frame
/// hands every screen the real window.
class _MetricsProbe extends StatelessWidget {
  const _MetricsProbe();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          '${20.w.toStringAsFixed(1)} / ${20.h.toStringAsFixed(1)} / '
          '${MediaQuery.sizeOf(context).width.toStringAsFixed(1)} / '
          '${18.sp.toStringAsFixed(1)}',
        ),
      ),
    );
  }
}

void main() {
  testWidgets('a desktop window is used in full, with text capped',
      (WidgetTester tester) async {
    await _setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(_framed(const _MetricsProbe()));
    await tester.pump();

    // 20% of the 1000 px design width, 20% of the window's height, a
    // MediaQuery that agrees with the window, and text at the 1.2x cap rather
    // than the package's 2x.
    expect(find.text('200.0 / 180.0 / 1440.0 / 21.6'), findsOneWidget);
  });

  testWidgets('a landscape phone fills its short height',
      (WidgetTester tester) async {
    await _setSize(tester, const Size(800, 400));
    await tester.pumpWidget(_framed(const _MetricsProbe()));
    await tester.pump();

    expect(find.text('160.0 / 80.0 / 800.0 / 18.5'), findsOneWidget);
  });

  testWidgets('a small phone keeps its own width', (WidgetTester tester) async {
    await _setSize(tester, const Size(320, 568));
    await tester.pumpWidget(_framed(const _MetricsProbe()));
    await tester.pump();

    // 18 * 0.85 (the floor of the text scale) = 15.3
    expect(find.text('64.0 / 113.6 / 320.0 / 15.3'), findsOneWidget);
  });

  testWidgets('a home button fills the content column, not the window',
      (WidgetTester tester) async {
    await _setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(_framed(
      Scaffold(
        body: AppContent(
          maxWidth: 1120,
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: ButtonCard(
            title: 'Start Game',
            gradientColors: const <Color>[Colors.green, Colors.green],
            textColor: Colors.white,
            onTap: () {},
          ),
        ),
      ),
    ));
    await tester.pump();

    // The content column is 1120 wide (minus the gutters and the card margin),
    // so the card fills it without running to the edges of a 1440 px window.
    final double width = tester.getSize(find.byType(ButtonCard)).width;
    expect(width, greaterThan(900));
    expect(width, lessThan(1120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the role picker lays out at every size without overflowing',
      (WidgetTester tester) async {
    for (final Size size in _sizes) {
      await _setSize(tester, size);
      await tester.pumpWidget(_framed(const SelectRoleScreen()));
      // Lottie animations repeat, so this cannot use pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.takeException(),
        isNull,
        reason: 'role picker overflowed at ${size.width}x${size.height}',
      );
      expect(find.text('Time to Pick a Role!'), findsOneWidget);

      // Drop the screen so its animations and timers are disposed before the
      // next size is pumped.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('the deed dialog fits a small phone and a landscape window',
      (WidgetTester tester) async {
    for (final Size size in <Size>[
      const Size(320, 568),
      const Size(800, 400),
      const Size(1440, 900),
    ]) {
      await _setSize(tester, size);
      await tester.pumpWidget(_framed(
        Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () => showBankpopSpaceCard(context, _brown),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'deed overflowed at ${size.width}x${size.height}',
      );
      expect(find.text("Beggar's Alley"), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }
  });

  // Regression: the frame used to compute its design size from a
  // LayoutBuilder, which runs during layout. A window resize while a dialog
  // was animating in rebuilt the Navigator from inside that layout pass and
  // tripped its `!_debugLocked` assertion, leaving the app stuck on a red
  // error screen in the browser. Dragging a desktop window is exactly this
  // sequence, so the test drags the size mid-transition and then proves the
  // app can still navigate.
  testWidgets('resizing while a dialog opens keeps the navigator usable',
      (WidgetTester tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_framed(
      Builder(
        builder: (BuildContext context) => Center(
          child: TextButton(
            onPressed: () => showBankpopSpaceCard(context, _brown),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    // One frame in: the route transition has started but not finished.
    await tester.pump(const Duration(milliseconds: 40));

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("Beggar's Alley"), findsOneWidget);

    // The navigator still works after the resize: close one route and open
    // another.
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text("Beggar's Alley"), findsOneWidget);
  });

  testWidgets('the trade builder fits a small phone',
      (WidgetTester tester) async {
    await _setSize(tester, const Size(320, 568));
    await tester.pumpWidget(_framed(
      TradeBuilderDialog(
        gameId: 'TEST',
        myId: 'me',
        myName: 'Me',
        myCards: const <PlayerCard>[],
        spaces: const <int, BankpopSpace>{},
        players: const <Map<String, dynamic>>[],
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Trade Builder'), findsOneWidget);
    expect(find.text('Send Offer'), findsOneWidget);
  });
}
