// A drawn card is shown on its own artwork, with the text on the middle band
// and the two buttons on the bottom corners. These tests pin that the picture
// is the one for the pack that was drawn, that the money button names the
// effect, and that the card still fits a small phone and a wide window.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/card_deck.dart';
import 'package:mon/widgets/card_effect_flow.dart';

/// The card is opened from the banker screen; this is the smallest stand-in
/// for it.
Widget _host() {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: ElevatedButton(
            onPressed: () => showCardEffectFlow(
              context,
              gameId: 'game-1',
              bankerId: 'banker-1',
              cardText: 'The bank pays you a dividend of \$50.',
              kind: CardDeckKind.chance,
              currency: '\$',
            ),
            child: const Text('Draw'),
          ),
        ),
      ),
    ),
  );
}

/// Opens the dialog and lets it lay itself out without settling: the artwork
/// is a picture, and pumpAndSettle would wait on its own frames.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Draw'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a Chance card is drawn on the Chance face', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await _open(tester);

    expect(
      find.image(const AssetImage('assets/Icons/chance_inside_trimmed.png')),
      findsOneWidget,
    );
    // The card was written with a dollar; the face shows the app's own sign.
    expect(
      find.text(BoardCurrencies.write('The bank pays you a dividend of \$50.')),
      findsOneWidget,
    );
    expect(find.text('Reward'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('a card with no money effect has only the way out',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => showCardEffectFlow(
                  context,
                  gameId: 'game-1',
                  bankerId: 'banker-1',
                  cardText: 'Advance to GO.',
                  kind: CardDeckKind.chest,
                  currency: '\$',
                ),
                child: const Text('Draw'),
              ),
            ),
          ),
        ),
      ),
    );
    await _open(tester);

    expect(
      find.image(const AssetImage('assets/Icons/chest_inside_trimmed.png')),
      findsOneWidget,
    );
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Reward'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card fits a small phone', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await _open(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Reward'), findsOneWidget);
  });

  testWidgets('the card fits a wide window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await _open(tester);

    expect(tester.takeException(), isNull);
    // The picture is the dialog's own size, not a stretched screen-wide slab.
    final Size card = tester.getSize(find.byType(Image).first);
    expect(card.width, lessThanOrEqualTo(560));
  });

  testWidgets('a drawn card is not thrown away by a tap beside it',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await _open(tester);

    // The card carries money the table has to settle, so the paper around it is
    // not a dismiss handle: only the card's own Close button closes it.
    await tester.tapAt(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Close'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/Icons/chance_inside_trimmed.png')),
      findsOneWidget,
    );
  });

  testWidgets('a pack\'s square shows the card face as a picture only',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    showCardFacePreview(context, CardDeckKind.chest),
                child: const Text('Look'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Look'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The picture, and nothing to read or press on it.
    expect(
      find.image(const AssetImage('assets/Icons/chest_inside_trimmed.png')),
      findsOneWidget,
    );
    expect(find.text('Close'), findsNothing);
    expect(find.text('Reward'), findsNothing);

    // Nothing is drawn by looking, so this one does close on an outside tap.
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Image), findsNothing);
  });
}
