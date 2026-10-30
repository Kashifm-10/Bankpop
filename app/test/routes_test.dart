import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/pages/game_rules_screen.dart';
import 'package:mon/routes.dart';
import 'package:mon/widgets/app_frame.dart';

void main() {
  group('AppRoutes', () {
    test('a game address carries the role and the id', () {
      expect(AppRoutes.banker('LBNSA'), '/game/LBNSA/banker?bank=0');
      expect(AppRoutes.player('LBNSA', bankValue: 1000),
          '/game/LBNSA/player?bank=1000');
      expect(AppRoutes.scanPay('LBNSA'), '/game/LBNSA/scan-pay');
      expect(
        AppRoutes.history('LBNSA', playerId: 'p1', showAllPlayers: true),
        '/game/LBNSA/history?playerId=p1&all=1',
      );
    });

    test('an id that needs escaping is escaped once', () {
      expect(AppRoutes.player('A B'), '/game/A%20B/player?bank=0');
    });

    test('a verification link points at the verify route', () {
      expect(AppRoutes.verify('abc.def'), '/verify?token=abc.def');
    });

    test('a refused game URL carries the reason and the original location', () {
      final String location = AppRoutes.denied(
        gameId: 'LBNSA',
        reason: 'wrongRole',
        role: 'banker',
        from: '/game/LBNSA/banker?bank=0',
      );
      final Uri uri = Uri.parse(location);

      expect(uri.path, AppRoutes.gameDenied);
      expect(uri.queryParameters['game'], 'LBNSA');
      expect(uri.queryParameters['reason'], 'wrongRole');
      expect(uri.queryParameters['role'], 'banker');
      expect(uri.queryParameters['from'], '/game/LBNSA/banker?bank=0');
    });
  });

  group('Game rules', () {
    testWidgets('renders the rules on a small phone without overflowing',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              AppFrame(child: child ?? const SizedBox.shrink()),
          home: const GameRulesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Game rules'), findsOneWidget);
      expect(
        find.textContaining('These are the rules this app follows'),
        findsOneWidget,
      );

      // The first rule card is under the header on a phone, so the page is
      // scrolled to it: the header is worth the room it takes.
      await tester.dragUntilVisible(
        find.text('Setting up'),
        find.byType(ListView).last,
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      expect(find.text('Setting up'), findsOneWidget);
    });
  });
}
