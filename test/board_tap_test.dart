// Tapping a card on the board has to open its deed.
//
// The board used to draw its tiles without a gesture listener, so every tap on
// a card did nothing: the deed never opened, and the cards game - which picks a
// property off this board before selling it - had no way in at all. These pin
// the tap on the tile itself.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/widgets/bankpop_board_view.dart';
import 'package:mon/widgets/bankpop_tile.dart';

BankpopBoard _board() {
  final List<BankpopSpace> spaces = <BankpopSpace>[
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
  ];
  return BankpopBoard(
    spaces: spaces,
    chanceOptions: const <String>['Advance to GO'],
    communityChest: const <String>['Bank error in your favour'],
  );
}

void main() {
  testWidgets('tapping a card opens its deed', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 420,
              child: BankpopBoardView(board: _board(), size: 420),
            ),
          ),
        ),
      ),
    );

    final Finder card = find.byWidgetPredicate(
      (Widget widget) => widget is BankpopTile && widget.space.index == 5,
    );
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pumpAndSettle();

    // The deed is the dialog that carries the card's name in its header.
    expect(find.text('Card 5'), findsWidgets);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('the tile itself is the tap target', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 180,
              child: BankpopTile(
                space: const BankpopSpace(
                  index: 5,
                  name: 'Card 5',
                  type: 'Property',
                  price: 200,
                  color: 'Brown',
                ),
                side: BoardSide.bottom,
                width: 120,
                height: 180,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(BankpopTile));
    expect(taps, 1);
  });
}
