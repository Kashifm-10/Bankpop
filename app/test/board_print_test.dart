// What a card carries on the printed board, which is now the same picture the
// boards screen draws: the name in capitals under its colour block, broken
// between words onto two lines, with no line under it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/widgets/bankpop_tile.dart';

const BankpopSpace _brown = BankpopSpace(
  index: 1,
  name: "Beggar's Alley",
  type: 'Property',
  price: 60,
  rent: <int>[2, 10, 30, 90, 160, 250],
  color: 'Brown',
  houseCost: 50,
  hotelCost: 50,
);

Widget _tile(BoardSide side) => _tileWith(_brown, side);

const BankpopSpace _station = BankpopSpace(
  index: 5,
  name: 'Grand Central Station',
  type: 'Property',
  price: 200,
  rent: <int>[25, 50, 100],
  color: 'Station',
);

const BankpopSpace _go = BankpopSpace(
  index: 0,
  name: 'GO',
  type: 'Special',
);

/// The board's Income Tax square as boards.sql seeds it: a special that carries
/// the same 200 every other board's tax does.
const BankpopSpace _incomeTax = BankpopSpace(
  index: 4,
  name: 'Income Tax',
  type: 'Special',
  price: 200,
);

Widget _tileWith(
  BankpopSpace space,
  BoardSide side, {
  String currency = '£',
}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 90,
          child: BankpopTile(
            space: space,
            side: side,
            width: 200,
            height: 90,
            nameFontSize: 11,
            currency: currency,
            onTap: () {},
          ),
        ),
      ),
    );

/// The colour block the name is written in.
BoxDecoration _strip(WidgetTester tester) {
  final Iterable<Container> containers = tester.widgetList<Container>(
    find.byType(Container),
  );
  return containers
      .map((Container c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere(
          (BoxDecoration d) => d.color == const Color(0xFF8D5524));
}

void main() {
  testWidgets('a printed card name is upper case', (WidgetTester tester) async {
    await tester.pumpWidget(_tile(BoardSide.bottom));
    await tester.pump();

    // Two words, two lines, both in capitals.
    expect(find.text("BEGGAR'S"), findsOneWidget);
    expect(find.text('ALLEY'), findsOneWidget);
    expect(find.text("Beggar's Alley"), findsNothing);
  });

  testWidgets('the printed colour block has no line under the name',
      (WidgetTester tester) async {
    for (final BoardSide side in <BoardSide>[
      BoardSide.bottom,
      BoardSide.top,
      BoardSide.left,
      BoardSide.right,
    ]) {
      await tester.pumpWidget(_tile(side));
      await tester.pump();

      final Border border = _strip(tester).border! as Border;
      expect(border.top.width, 0, reason: 'line above the name on $side');
      expect(border.bottom.width, 0, reason: 'line under the name on $side');
      expect(border.left.width, 0, reason: 'line beside the name on $side');
      expect(border.right.width, 0, reason: 'line beside the name on $side');
    }
  });

  testWidgets('every card is closed by a thin line on all four sides',
      (WidgetTester tester) async {
    for (final BoardSide side in <BoardSide>[
      BoardSide.bottom,
      BoardSide.top,
      BoardSide.left,
      BoardSide.right,
    ]) {
      await tester.pumpWidget(_tile(side));
      await tester.pump();
      final Container printed = tester.widget<Container>(
        find.byWidgetPredicate(
            (Widget w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color ==
                    const Color(0xFFF4E0BF) &&
                (w.decoration as BoxDecoration).border != null),
      );
      final Border border =
          (printed.decoration! as BoxDecoration).border! as Border;

      expect(border.top.width, 0.8, reason: 'the top line of a $side card');
      expect(border.right.width, 0.8, reason: 'the right line of a $side card');
      expect(border.bottom.width, 0.8,
          reason: 'the bottom line of a $side card');
      expect(border.left.width, 0.8, reason: 'the left line of a $side card');
    }
  });

  testWidgets('a printed station carries its name where a colour card does',
      (WidgetTester tester) async {
    await tester.pumpWidget(_tileWith(_station, BoardSide.bottom));
    await tester.pump();

    expect(find.text('GRAND CENTRAL'), findsOneWidget);
    expect(find.text('STATION'), findsOneWidget);
  });

  testWidgets('a buyable card shows its price, an unbuyable one has none',
      (WidgetTester tester) async {
    await tester.pumpWidget(_tile(BoardSide.bottom));
    await tester.pump();
    expect(find.text('£60'), findsOneWidget);

    await tester.pumpWidget(_tileWith(_go, BoardSide.corner));
    await tester.pump();
    expect(find.textContaining('£'), findsNothing);
  });

  testWidgets('a printed price is written in the board currency',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        _tileWith(_brown, BoardSide.bottom, currency: '₹'));
    await tester.pump();

    expect(find.text('₹60'), findsOneWidget);
    expect(find.text('£60'), findsNothing);

    // A multi-character symbol is spaced away from the number.
    await tester.pumpWidget(
        _tileWith(_brown, BoardSide.bottom, currency: 'AED'));
    await tester.pump();
    expect(find.text('AED 60'), findsOneWidget);
  });

  testWidgets('a printed station has no colour block: its name sits on the art',
      (WidgetTester tester) async {
    await tester.pumpWidget(_tileWith(_station, BoardSide.bottom));
    await tester.pump();

    // The station's dark brown group colour is not used as a band over the
    // artwork - the picture is the card.
    final Iterable<Container> containers =
        tester.widgetList<Container>(find.byType(Container));
    final bool hasStationBand = containers.any((Container c) =>
        (c.decoration as BoxDecoration?)?.color == const Color(0xFF5D4037));
    expect(hasStationBand, isFalse);

    // The artwork is still drawn, and the name is over it.
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('GRAND CENTRAL'), findsOneWidget);
  });

  testWidgets('the Income Tax card shows its price like any other card',
      (WidgetTester tester) async {
    // A special square never had a price before; the tax card does, and it is
    // drawn by the same label as a property's: same size, same ink, same edge.
    await tester.pumpWidget(_tileWith(_incomeTax, BoardSide.bottom));
    await tester.pump();
    final Rect tax = tester.getRect(find.text('£200'));
    final Text taxText = tester.widget<Text>(find.text('£200'));

    await tester.pumpWidget(_tileWith(_brown, BoardSide.bottom));
    await tester.pump();
    final Rect property = tester.getRect(find.text('£60'));
    final Text propertyText = tester.widget<Text>(find.text('£60'));

    expect(taxText.style?.fontSize, propertyText.style?.fontSize);
    expect(taxText.style?.color, propertyText.style?.color);
    expect(taxText.style?.fontWeight, propertyText.style?.fontWeight);
    // Same distance from the card's outer edge (both tiles are 200x90).
    expect(tax.bottom, moreOrLessEquals(property.bottom, epsilon: 0.5));
  });

  testWidgets('the tax price follows the board currency',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        _tileWith(_incomeTax, BoardSide.bottom, currency: '₹'));
    await tester.pump();
    expect(find.text('₹200'), findsOneWidget);
  });

  testWidgets('a printed name is broken between words, not inside one',
      (WidgetTester tester) async {
    await tester.pumpWidget(_tile(BoardSide.bottom));
    await tester.pump();

    // The two halves of the name are separate lines, and each one is a whole
    // word: no line ends or begins part-way through a word.
    final Text first = tester.widget<Text>(find.text("BEGGAR'S"));
    final Text second = tester.widget<Text>(find.text('ALLEY'));
    expect(first.softWrap, isFalse);
    expect(second.softWrap, isFalse);
    expect(first.maxLines, 1);
    expect(second.maxLines, 1);
  });
}
