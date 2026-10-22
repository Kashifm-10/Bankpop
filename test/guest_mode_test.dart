// Signing in is optional. These pin the parts a guest depends on: no account
// means no account state, the introduction is remembered, and signing out
// leaves the local player (and therefore its games) in place.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/pages/auth/auth_screen.dart';
import 'package:mon/services/account.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The screens are laid out through the responsive frame, exactly as `main.dart`
/// does it, because their sizes come from it.
Widget _screen(Widget home) => MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          AppFrame(child: child ?? const SizedBox.shrink()),
      home: home,
    );

void main() {
  test('a fresh install is a guest, not a signed-in account', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(await Account.isSignedIn(), isFalse);
    expect(await Account.signedInEmail(), isNull);
  });

  test('an account email is what makes the device signed in', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'account_email': 'player@example.com',
      'account_id': 'abc',
    });
    expect(await Account.isSignedIn(), isTrue);
    expect(await Account.signedInEmail(), 'player@example.com');
  });

  test('the introduction is remembered once it has been shown', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(Account.onboardingDoneKey), isNull);

    await Account.markOnboarded();

    expect(prefs.getBool(Account.onboardingDoneKey), isTrue);
  });

  test('signing out keeps the local player so its games stay reachable',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'playerID': 'local-player',
      'account_id': 'local-player',
      'account_email': 'player@example.com',
      'profile_name': 'Ameen',
    });

    await Account.signOut();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account_email'), isNull);
    expect(prefs.getString('account_id'), isNull);
    expect(prefs.getString('playerID'), 'local-player');
    expect(prefs.getString('profile_name'), 'Ameen');
  });

  testWidgets('the auth screen offers a way in without an account',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(_screen(const AuthScreen()));
    await tester.pump();

    expect(find.text('Continue without an account'), findsOneWidget);
    expect(
      find.textContaining('Guest games stay on this device'),
      findsOneWidget,
      reason: 'the guest path has to say what a guest gives up',
    );
  });

  testWidgets('the sign-in screen keeps the guest button available',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(_screen(const AuthScreen()));
    await tester.pump();

    // Flip to sign-up and back: a player who opened the account screen by
    // mistake can still leave without creating one.
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('I already have an account'), findsOneWidget);

    expect(find.text('Continue without an account'), findsOneWidget);
  });
}
