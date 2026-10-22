// The game screens are icon-only now, so two things have to hold: the icon
// carries its name for tooltips and screen readers, and the info button always
// explains exactly the buttons it was handed. These tests pin both, and the
// small-phone layout of the legend sheet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/game_controls.dart';

Widget _host(Widget child) => MaterialApp(
      builder: (BuildContext context, Widget? inner) =>
          AppFrame(child: inner ?? const SizedBox.shrink()),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('an action is an icon with its name kept for tooltips',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    int taps = 0;

    await tester.pumpWidget(_host(
      GameIconButton(
        control: GameControls.trade,
        onPressed: () => taps++,
      ),
    ));

    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    expect(
      find.text('Trade'),
      findsNothing,
      reason:
          'the label belongs in the tooltip and the legend, not on the tile',
    );
    expect(find.bySemanticsLabel('Trade'), findsOneWidget);

    await tester.tap(find.byType(GameIconButton));
    await tester.pump();
    expect(taps, 1);

    handle.dispose();
  });

  testWidgets('a disabled action looks disabled and does nothing',
      (WidgetTester tester) async {
    int taps = 0;

    await tester.pumpWidget(_host(
      GameIconButton(
        control: GameControls.scan,
        enabled: false,
        onPressed: () => taps++,
      ),
    ));

    await tester.tap(find.byType(GameIconButton), warnIfMissed: false);
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('the info button lists the controls the screen passed in',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(
      GameInfoButton(
        title: 'Player controls',
        controls: <GameControl>[
          GameControls.history,
          GameControls.myCards,
          GameControls.scan,
        ],
      ),
    ));

    await tester.tap(find.byType(GameInfoButton));
    await tester.pumpAndSettle();

    expect(find.text('Player controls'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('My cards'), findsOneWidget);
    expect(find.text(GameControls.myCards.detail), findsOneWidget);
    expect(
      find.text('Trade'),
      findsNothing,
      reason: 'a control that is not on the screen must not be listed',
    );
  });

  testWidgets('the legend fits a small phone', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(
      GameInfoButton(
        title: 'Banker controls',
        controls: <GameControl>[
          GameControls.history,
          GameControls.board,
          GameControls.showBankQr,
          GameControls.suspend,
          GameControls.leave,
          GameControls.receive,
          GameControls.giveCard,
        ],
      ),
    ));

    await tester.tap(find.byType(GameInfoButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Banker controls'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);

    // The last rows can be below the fold on a 568 px window; they have to be
    // reachable by scrolling, which is the point of the sheet's list.
    await tester.scrollUntilVisible(
      find.text('Give card'),
      80,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Give card'), findsOneWidget);
  });
}
