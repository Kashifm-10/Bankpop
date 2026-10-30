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
    testWidgets('the chooser offers both halves of the guide',
        (WidgetTester tester) async {
      await _setSize(tester, const Size(320, 568));
      await tester.pumpWidget(_host(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showHowToUseGuide(context),
            child: const Text('opening'),
          ),
        ),
      ));

      await tester.tap(find.text('opening'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('How to use BankPop'), findsOneWidget);
      expect(find.text('As a player'), findsOneWidget);
      expect(find.text('As the banker'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('How to use BankPop'), findsNothing);
    });

    testWidgets('the player page is its own page, with no overflow on a phone',
        (WidgetTester tester) async {
      await _setSize(tester, const Size(320, 568));
      await tester.pumpWidget(_host(const HowToUsePlayerScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('As a player'), findsOneWidget);
      // The banker's half is a different page, so none of it is here.
      expect(find.text('As the banker'), findsNothing);

      // The first step is below the quick-start strip on a phone, so the page
      // is scrolled to it rather than expected to fit on one screen: the
      // guide is longer than a phone now, on purpose.
      await tester.dragUntilVisible(
        find.text('Getting in'),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      expect(find.text('Getting in'), findsOneWidget);
      expect(find.textContaining('verification link'), findsWidgets);
    });

    testWidgets('the banker page describes running the bank',
        (WidgetTester tester) async {
      await _setSize(tester, const Size(320, 568));
      await tester.pumpWidget(_host(const HowToUseBankerScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('As the banker'), findsOneWidget);
      expect(find.text('As a player'), findsNothing);

      await tester.dragUntilVisible(
        find.text('Start a game'),
        find.byType(ListView),
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
