// Where a card's name sits.
//
// Every board draws each name just under its colour block, so the block stays a
// solid band - the boards screen, the board in a game and the downloaded board
// are the same picture.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/widgets/bankpop_board_view.dart';
import 'package:mon/widgets/bankpop_tile.dart';

const BankpopSpace _brown = BankpopSpace(
  index: 1,
  name: 'Brown Card',
  type: 'Property',
  price: 60,
  rent: <int>[2, 10, 30, 90, 160, 250],
  color: 'Brown',
  houseCost: 50,
  hotelCost: 50,
);

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 140,
            height: 90,
            child: BankpopTile(
              space: _brown,
              side: BoardSide.bottom,
              width: 140,
              height: 90,
              nameFontSize: 9,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

/// The colour band: the only block painted in the group's own colour.
Finder get _block => find.byWidgetPredicate(
      (Widget widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).color ==
              const Color(0xFF8D5524),
    );

void main() {
  testWidgets('the name sits under the colour block',
      (WidgetTester tester) async {
    await _pump(tester);

    final Rect block = tester.getRect(_block);
    final Rect name = tester.getRect(find.text('BROWN'));

    expect(
      name.top,
      greaterThanOrEqualTo(block.bottom - 0.5),
      reason: 'the name would still be printed inside the block',
    );

    // And it is written in paper ink, not the white the block carried.
    final Text text = tester.widget<Text>(find.text('BROWN'));
    expect(text.style?.color, const Color(0xFF3E2723));
  });

  testWidgets('a two-word name is one word per line',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('BROWN'), findsOneWidget);
    expect(find.text('CARD'), findsOneWidget);
  });

  // GO pays the advance the banker set, so the square names the payment instead
  // of carrying a figure that could disagree with the game.
  testWidgets('the GO square says COLLECT ADVANCE', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: BankpopTile(
                space: const BankpopSpace(
                  index: 0,
                  name: 'GO',
                  type: 'Special',
                ),
                side: BoardSide.corner,
                width: 120,
                height: 120,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('COLLECT ADVANCE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The caption is set in the clear band Go.png leaves between the word GO
    // (which ends near 47% of the height) and the arrow (which starts near
    // 65%): it must not sit across the arrow at the bottom of the square.
    final Rect tile = tester.getRect(find.byType(BankpopTile));
    final Rect caption = tester.getRect(find.text('COLLECT ADVANCE'));
    final double centre = (caption.center.dy - tile.top) / tile.height;
    expect(centre, greaterThan(0.47));
    expect(centre, lessThan(0.63));
  });

  // The board screen draws this at whatever size the window leaves, so the
  // band, the name under it and the price still have to fit a phone-sized card.
  for (final double size in <double>[300, 560, 900]) {
    testWidgets('a board at ${size.toInt()}px lays its names out cleanly',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(Size(size + 40, size + 40));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size,
                height: size,
                child: BankpopBoardView(
                  board: _board(),
                  size: size,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull,
          reason: 'a card overflowed at ${size.toInt()}px');
      expect(find.text('CARD'), findsWidgets);
    });
  }
}

BankpopBoard _board() => BankpopBoard(
      spaces: <BankpopSpace>[
        for (int i = 0; i < 40; i++)
          BankpopSpace(
            index: i,
            name: i == 0
                ? 'GO'
                : i == 10
                    ? 'Jail'
                    : i == 20
                        ? 'Free Parking'
                        : i == 30
                            ? 'Go To Jail'
                            : 'Card $i',
            type: i % 10 == 0 ? 'Special' : 'Property',
            price: i % 10 == 0 ? null : 200,
            color: i % 10 == 0 ? null : 'Brown',
            rent: i % 10 == 0 ? null : const <int>[10, 40, 90, 160],
          ),
      ],
      chanceOptions: const <String>['Advance to GO'],
      communityChest: const <String>['Bank error in your favour'],
    );
