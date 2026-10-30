// The first-run profile sheet used to draw a tick on the first avatar while
// storing nothing, so a player who saved without tapping a face closed the
// dialog and kept the app icon. Now nothing is ticked until it is picked, and
// Save keeps the sheet open until it is.

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

Finder _avatarTiles() => find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(GestureDetector),
    );

void main() {
  testWidgets('the first setup stays open until an avatar is picked',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(_dialog(first: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Tester Smith');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileDialog), findsOneWidget,
        reason: 'nothing may close the setup before an avatar is chosen');
    expect(find.text('Pick an avatar to continue.'), findsOneWidget);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('profile_name'), isNull);
    expect(prefs.getString('avatar_path'), isNull);
  });

  testWidgets('a picked avatar and a name with a space are both saved',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(_dialog(first: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Tester Smith');
    await tester.tap(_avatarTiles().at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('profile_name'), 'Tester Smith');
    expect(prefs.getString('avatar_path'), ProfileAvatar.choices[1]);
    expect(prefs.getInt('selected_avatar_index'), 1);
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
