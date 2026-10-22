// Regression: the profile sheet drew a tick on the first avatar but stored no
// avatar at all, so a player who saved without tapping a face kept the app icon.
// The first avatar has to be the real selection from the moment the sheet opens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/pages/profile_edit.dart';
import 'package:mon/services/profile_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _dialog({required bool first}) => MaterialApp(
      home: Scaffold(
        body: ProfileDialog(first: first, prevIndex: 0),
      ),
    );

void main() {
  testWidgets('saving without tapping an avatar stores the one shown as picked',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(_dialog(first: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Tester');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('profile_name'), 'Tester');
    expect(
      prefs.getString('avatar_path'),
      ProfileAvatar.choices.first,
      reason: 'the avatar carrying the tick must be the saved one',
    );
    expect(prefs.getInt('selected_avatar_index'), 0);
  });

  testWidgets('an avatar saved earlier opens selected and survives a save',
      (WidgetTester tester) async {
    const String saved = 'assets/avatars/boy3.jpg';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'profile_name': 'Tester',
      'avatar_path': saved,
      'selected_avatar_index': 9,
    });

    await tester.pumpWidget(_dialog(first: false));
    await tester.pumpAndSettle();

    expect(find.text('Tester'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('avatar_path'), saved);
    expect(prefs.getInt('selected_avatar_index'), 9);
  });
}
