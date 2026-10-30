// The two packs the banker deals from come as landscape art, so the tile has
// to take that ratio rather than squeeze the drawing into a square sticker.
// The art is cropped to its own bounds and has transparent corners, so the
// button must not paint a colour behind it: the tile is the picture and
// nothing else. These pin the shape, the artwork, the names and that a
// closed table deals no cards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/widgets/deck_button.dart';
import 'package:mon/widgets/game_controls.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('the deck tile is exactly the artwork',
      (WidgetTester tester) async {
    for (final double width in <double>[104, 128, 160]) {
      await tester.pumpWidget(_host(
        DeckButton(
          control: GameControls.chanceDeck,
          width: width,
          onPressed: () {},
        ),
      ));

      final Rect rect = tester.getRect(find.byType(DeckButton));
      expect(rect.width, moreOrLessEquals(width, epsilon: 0.5));
      expect(
        rect.height,
        moreOrLessEquals(width / DeckButton.artRatio, epsilon: 0.5),
        reason: 'the height follows the drawing, never the width',
      );
      expect(
        rect.width / rect.height,
        moreOrLessEquals(623 / 382, epsilon: 0.01),
      );

      // The picture's box is the tile's box: no frame colour, no margin left
      // inside the button.
      final Rect art = tester.getRect(find.image(
        const AssetImage('assets/Icons/chance_deck_l_trimmed.png'),
      ));
      expect(art.left, moreOrLessEquals(rect.left, epsilon: 0.5));
      expect(art.top, moreOrLessEquals(rect.top, epsilon: 0.5));
      expect(art.width, moreOrLessEquals(rect.width, epsilon: 0.5));
      expect(art.height, moreOrLessEquals(rect.height, epsilon: 0.5));

      // And nothing is painted underneath it: the art's own transparent
      // corners must show the paper through, not a band of colour.
      final Material material = tester.widget<Material>(
        find.descendant(
          of: find.byType(DeckButton),
          matching: find.byType(Material),
        ).first,
      );
      expect(material.color, Colors.transparent);

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('a pack on the board counts down and can be shuffled',
      (WidgetTester tester) async {
    int shuffles = 0;
    int draws = 0;

    await tester.pumpWidget(_host(
      DeckButton(
        control: GameControls.chanceDeck,
        width: 120,
        status: DeckStatus(
          left: 19,
          total: 22,
          onShuffle: () => shuffles++,
          onPressed: () => draws++,
        ),
      ),
    ));

    expect(find.text('19/22'), findsOneWidget);

    // The shuffle sits on the tile's own corner: a tap there shuffles, it does
    // not deal.
    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pump();
    expect(shuffles, 1);
    expect(draws, 0);

    await tester.tap(find.byType(DeckButton));
    await tester.pump();
    expect(draws, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shuffling pack shows the spinner in place of the button',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(
      DeckButton(
        control: GameControls.chestDeck,
        width: 120,
        status: DeckStatus(
          left: 4,
          total: 16,
          shuffling: true,
          onShuffle: () {},
          onPressed: () {},
        ),
      ),
    ));

    expect(find.byIcon(Icons.shuffle), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('4/16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both packs keep their name and their own artwork',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(_host(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DeckButton(
            control: GameControls.chanceDeck,
            width: 120,
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          DeckButton(
            control: GameControls.chestDeck,
            width: 120,
            onPressed: () {},
          ),
        ],
      ),
    ));

    expect(
      find.image(const AssetImage('assets/Icons/chance_deck_l_trimmed.png')),
      findsOneWidget,
    );
    expect(
      find.image(const AssetImage('assets/Icons/chest_deck_l_trimmed.png')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Chance deck'), findsOneWidget);
    expect(find.bySemanticsLabel('Community Chest deck'), findsOneWidget);
    expect(tester.takeException(), isNull);

    handle.dispose();
  });

  testWidgets('a suspended table\'s deck is drawn but does nothing',
      (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(_host(
      DeckButton(
        control: GameControls.chestDeck,
        width: 120,
        enabled: false,
        onPressed: () => taps++,
      ),
    ));

    await tester.tap(find.byType(DeckButton), warnIfMissed: false);
    await tester.pump();

    expect(taps, 0, reason: 'a closed table deals no cards');
    expect(tester.takeException(), isNull);
  });
}
