import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/game_status_banner.dart';

/// The band and the dialog are how a player learns that the table has stopped
/// and why the pay, trade and building controls have gone. They are drawn from
/// the session row, so the same two tests stand in for the banker's screen and
/// the players' screen.
Widget _host(Widget child) => MaterialApp(
      builder: (BuildContext context, Widget? inner) =>
          AppFrame(child: inner ?? const SizedBox.shrink()),
      home: Scaffold(body: child),
    );

GameSession _session(String status, {DateTime? endedAt}) => GameSession(
      gameId: 'VGHTH',
      bankerId: 'bank-1',
      bankerName: 'Aisha',
      status: status,
      paymentOption: 'InstantPay',
      playWithCards: true,
      playerValue: 1500,
      advanceValue: 200,
      endedAt: endedAt,
    );

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('GameStatusBanner', () {
    testWidgets('a paused table names the banker who can resume it',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        GameStatusBanner(
          session: _session(GameSession.suspended),
          onDetails: () {},
        ),
      ));

      expect(find.textContaining('Paused by Aisha'), findsOneWidget);
      expect(find.textContaining('Only the banker can resume'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
    });

    testWidgets('the banker sees the resume control on their own pause',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        GameStatusBanner(
          session: _session(GameSession.suspended),
          bankerView: true,
          onResume: () {},
        ),
      ));

      expect(find.textContaining('until you resume'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('an ended game says nothing can move and offers no resume',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        GameStatusBanner(
          session: _session(GameSession.ended),
          bankerView: true,
          onResume: () {},
          onDetails: () {},
        ),
      ));

      expect(find.textContaining('has ended'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
    });

    testWidgets('an ended game says when it ended',
        (WidgetTester tester) async {
      final DateTime endedAt = DateTime(2026, 10, 23, 14, 15);
      await tester.pumpWidget(_host(
        GameStatusBanner(
          session: _session(GameSession.ended, endedAt: endedAt),
        ),
      ));

      expect(
        find.textContaining('This game was ended on 23 Oct 2026, 2:15 PM'),
        findsOneWidget,
      );
    });

    testWidgets('the banker name is not shown to the banker',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        GameStatusBanner(
          session: _session(GameSession.suspended),
          bankerView: true,
          onResume: () {},
        ),
      ));

      expect(find.textContaining('Paused by Aisha'), findsNothing);
    });

    testWidgets('fits a narrow phone without overflowing',
        (WidgetTester tester) async {
      await _setSize(tester, const Size(320, 568));
      await tester.pumpWidget(_host(
        Column(
          children: <Widget>[
            GameStatusBanner(
              session: _session(GameSession.suspended),
              onDetails: () {},
            ),
            GameStatusBanner(
              session: _session(GameSession.ended),
              onDetails: () {},
            ),
          ],
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('Details'), findsNWidgets(2));
    });
  });

  group('Game paused dialog', () {
    testWidgets('cannot be dismissed by tapping outside, and returns to title',
        (WidgetTester tester) async {
      bool wentHome = false;

      await tester.pumpWidget(_host(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showGameStatusDialog(
              context,
              session: _session(GameSession.suspended),
              onReturnToTitle: () => wentHome = true,
            ),
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Game paused'), findsOneWidget);
      expect(find.textContaining('The banker (Aisha) paused'), findsOneWidget);

      // A tap on the barrier is ignored: the pause is not a notification.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Game paused'), findsOneWidget);

      // Staying keeps the player at the table.
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Game paused'), findsNothing);
      expect(wentHome, isFalse);

      // Reopening and choosing the one way out goes to the title screen.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return to title screen'));
      await tester.pumpAndSettle();
      expect(find.text('Game paused'), findsNothing);
      expect(wentHome, isTrue);
    });

    testWidgets('an ended game offers a look at the holdings, not a resume',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showGameStatusDialog(
              context,
              session: _session(GameSession.ended),
              onReturnToTitle: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Game ended'), findsOneWidget);
      expect(find.text('View holdings'), findsOneWidget);
      expect(find.text('Return to title screen'), findsOneWidget);
      expect(find.text('Stay'), findsNothing);
    });
  });
}
