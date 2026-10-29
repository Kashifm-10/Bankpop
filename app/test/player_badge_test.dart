import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/pages/how_to_use_screen.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/player_badge.dart';

Widget _host(Widget child) => MaterialApp(
      builder: (BuildContext context, Widget? inner) =>
          AppFrame(child: inner ?? const SizedBox.shrink()),
      home: Scaffold(body: Center(child: child)),
    );

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('PlayerStandingBadge', () {
    testWidgets('a live player carries no badge', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const PlayerStandingBadge(standing: PlayerStanding.active),
      ));

      expect(find.text('REMOVED'), findsNothing);
      expect(find.text('LEFT'), findsNothing);
      expect(find.text('OFFLINE'), findsNothing);
    });

    testWidgets('a removed player is the only badge there is',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const PlayerStandingBadge(standing: PlayerStanding.kicked),
      ));

      expect(find.text('REMOVED'), findsOneWidget);
      expect(find.text('LEFT'), findsNothing);
      expect(find.text('OFFLINE'), findsNothing);
    });

    testWidgets('fits a narrow banker row without overflowing',
        (WidgetTester tester) async {
      await _setSize(tester, const Size(320, 568));
      await tester.pumpWidget(_host(
        const Row(
          children: <Widget>[
            Flexible(
              child: Text('A very long player name here',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            PlayerStandingBadge(standing: PlayerStanding.kicked, compact: true),
          ],
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('REMOVED'), findsOneWidget);
    });
  });

  group('How to use', () {
    testWidgets('the page opens with both roles and no overflow on a phone',
        (WidgetTester tester) async {
      await _setSize(tester, const Size(320, 568));
      await tester.pumpWidget(_host(const HowToUseScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('How to use'), findsOneWidget);
      expect(find.text('As a player'), findsOneWidget);

      // The first step is below the quick-start strip on a phone, so the page
      // is scrolled to it rather than expected to fit on one screen: the
      // guide is longer than a phone now, on purpose.
      // Dragged on the list itself: the tab view is scrollable sideways too,
      // so "the first Scrollable" is not the one this page scrolls.
      await tester.dragUntilVisible(
        find.text('Getting in'),
        find.byType(ListView).last,
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      expect(find.text('Getting in'), findsOneWidget);
      expect(find.textContaining('verification link'), findsWidgets);

      // The banker tab describes the things this update added.
      await tester.tap(find.text('As the banker'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.text('Start a game'),
        find.byType(ListView).last,
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start a game'), findsOneWidget);
    });
  });

  group('App dialogs', () {
    testWidgets('a confirm returns true only when the action is tapped',
        (WidgetTester tester) async {
      bool? answer;

      Widget page(String label, bool tapConfirm) => _host(
            Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async {
                  answer = await showAppConfirm(
                    context,
                    title: 'Remove Ameen?',
                    message: 'The cash and cards go back to the bank.',
                    confirmLabel: 'Remove',
                    cancelLabel: 'Cancel',
                  );
                },
                child: Text(label),
              ),
            ),
          );

      await tester.pumpWidget(page('open', true));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Ameen?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await tester.pumpWidget(page('open again', false));
      await tester.tap(find.text('open again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    testWidgets('the summary rows show what the banker is about to start with',
        (WidgetTester tester) async {
      await _setSize(tester, const Size(320, 568));
      await tester.pumpWidget(_host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppDialogPoint(
                label: 'Cash per player',
                value: '1500.00',
                icon: Icons.person_outline),
            AppDialogPoint(
                label: 'Play with cards',
                value: 'Yes',
                icon: Icons.style_outlined),
          ],
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('Cash per player'), findsOneWidget);
      expect(find.text('1500.00'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
    });
  });
}
