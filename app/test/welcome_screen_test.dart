import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/pages/welcome_screen.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// The cover's tap hint breathes on a repeating animation, so a test that
  /// waited for the tree to settle would never finish: every wait here is an
  /// explicit pump.
  Future<GoRouter> pumpCover(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.welcome,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.welcome,
          builder: (BuildContext context, GoRouterState state) =>
              const WelcomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('the story')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (BuildContext context, Widget? child) =>
            AppFrame(child: child ?? const SizedBox.shrink()),
      ),
    );
    await tester.pump();
    return router;
  }

  testWidgets('the cover names the app and offers one way on',
      (WidgetTester tester) async {
    await pumpCover(tester);

    expect(find.text('BankPop'), findsOneWidget);
    expect(find.text('Tap anywhere to begin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the cover records it and opens the story',
      (WidgetTester tester) async {
    await pumpCover(tester);

    await tester.tap(find.text('Tap anywhere to begin'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('the story'), findsOneWidget);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(Account.welcomeDoneKey), isTrue);
    expect(tester.takeException(), isNull);
  });
}
