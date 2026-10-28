import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/bankpop_board_view.dart';
import 'package:mon/widgets/bankpop_space_card.dart';
import 'package:mon/widgets/bankpop_tile.dart';
import 'package:mon/widgets/card_owner_badge.dart';

const BankpopSpace _beggarAlley = BankpopSpace(
  index: 1,
  name: "Beggar's Alley",
  type: 'Property',
  price: 60,
  rent: <int>[2, 10, 30, 90, 160, 250],
  color: 'Brown',
  houseCost: 50,
  hotelCost: 50,
);

/// One board tile at the size the board draws it, so a house or a hotel is laid
/// out the way it is in a game rather than in a roomy test box.
Widget _tile({int houses = 0, int hotels = 0}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: BankpopTile(
          space: _beggarAlley,
          side: BoardSide.bottom,
          width: 34,
          height: 46,
          houses: houses,
          hotels: hotels,
          onTap: () {},
        ),
      ),
    ),
  );
}

/// A house standing on a tile's colour block.
Finder get _houses => find.byWidgetPredicate(
      (Widget widget) =>
          widget is Icon &&
          widget.icon == Icons.home_rounded &&
          widget.color == const Color(0xFF1B5E20),
    );

/// A hotel standing on a tile's colour block.
Finder get _hotel => find.byWidgetPredicate(
      (Widget widget) =>
          widget is Icon &&
          widget.icon == Icons.apartment_rounded &&
          widget.color == const Color(0xFFC62828),
    );

/// The deed is opened from a dialog, so the tests need a screen with a button
/// that does what the banker screen does.
Widget _opener(Future<void> Function(BuildContext) onPressed, String label) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: TextButton(
            onPressed: () => onPressed(context),
            child: Text(label),
          ),
        ),
      ),
    ),
  );
}

/// The corners plus the brown card this file uses, laid out as the real board
/// is, so the owner badge is drawn where a game draws it.
BankpopBoard _board() => BankpopBoard(
      spaces: const <BankpopSpace>[
        BankpopSpace(index: 0, name: 'GO', type: 'Special'),
        _beggarAlley,
        BankpopSpace(index: 10, name: 'Jail', type: 'Special'),
        BankpopSpace(index: 20, name: 'Free Parking', type: 'Special'),
        BankpopSpace(index: 30, name: 'Go To Jail', type: 'Special'),
      ],
      chanceOptions: const <String>['Advance to GO'],
      communityChest: const <String>['Bank error in your favour'],
    );

void main() {
  testWidgets('the deed runs the card action the caller passes in',
      (WidgetTester tester) async {
    bool sold = false;

    await tester.pumpWidget(_opener((BuildContext context) {
      return showBankpopSpaceCard(
        context,
        _beggarAlley,
        actionWidget: Builder(
          builder: (BuildContext deedContext) => TextButton(
            onPressed: () {
              sold = true;
              // The action closes the deed itself, so its own follow-up opens
              // over the screen instead of on top of the deed.
              Navigator.of(deedContext).pop();
            },
            child: const Text('Pay QR'),
          ),
        ),
      );
    }, 'open'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The deed itself is unchanged, with the price still on it.
    expect(find.text('£60'), findsOneWidget);
    expect(find.text('Pay QR'), findsOneWidget);

    await tester.tap(find.text('Pay QR'));
    await tester.pumpAndSettle();

    expect(sold, isTrue);
    expect(find.text('Pay QR'), findsNothing);
  });

  testWidgets('a deed without an action shows only Close',
      (WidgetTester tester) async {
    await tester.pumpWidget(_opener((BuildContext context) {
      return showBankpopSpaceCard(context, _beggarAlley);
    }, 'open'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Pay QR'), findsNothing);
    expect(find.text('Pay QR'), findsNothing);
  });

  testWidgets('an owned deed shows the owner instead of a sell action',
      (WidgetTester tester) async {
    await tester.pumpWidget(_opener((BuildContext context) {
      // What the board passes for a card that already has an owner: the same
      // deed, with the owner where Give Card puts its QR button.
      return showBankpopSpaceCard(
        context,
        _beggarAlley,
        actionWidget: const CardOwnerBadge(owner: CardOwner(name: 'Ameen')),
      );
    }, 'open'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The deed itself is unchanged, price and all.
    expect(find.text('£60'), findsOneWidget);
    expect(find.text('Ameen'), findsOneWidget);
    expect(find.text('owns this card'), findsOneWidget);
    expect(find.text('Show QR'), findsNothing);
  });

  testWidgets('a sold card carries its holder above the card',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 420,
              child: BankpopBoardView(
                board: _board(),
                size: 420,
                owners: const <int, CardOwner>{
                  1: CardOwner(name: 'Ameen'),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The holder is the avatar badge; its name is what the badge announces and
    // shows on hover, so somebody at the table still knows whose card it is.
    final Finder avatar = find.byTooltip('Ameen');
    expect(avatar, findsOneWidget);

    // It hangs above the card, centred on it, and half outside it - over the
    // middle of the board, never over the card's own face.
    final Finder card = find.byWidgetPredicate(
      (Widget widget) => widget is BankpopTile && widget.space.index == 1,
    );
    final Rect face = tester.getRect(avatar);
    final Rect tile = tester.getRect(card);
    expect(face.center.dy, lessThan(tile.top + tile.height * 0.1));
    expect(face.center.dx, moreOrLessEquals(tile.center.dx, epsilon: 1));
  });

  testWidgets('an unsold card stays empty', (WidgetTester tester) async {
    await tester.pumpWidget(_tile());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Ameen'), findsNothing);
  });

  testWidgets('a deed ticks the houses it has and offers the next level',
      (WidgetTester tester) async {
    int? asked;
    await tester.pumpWidget(_opener((BuildContext context) {
      return showBankpopSpaceCard(
        context,
        _beggarAlley,
        houses: 1,
        hotels: 0,
        onBuild: (int step) async {
          asked = step;
          return true; // the banker approved
        },
      );
    }, 'open'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // One house built: its row carries the tick, the second row the plus.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.add_circle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();

    expect(asked, 2);
    // Approved, so the second row is ticked too and the plus moved on.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.byIcon(Icons.add_circle), findsOneWidget);
  });

  testWidgets('a hotel deed ticks every level and offers nothing',
      (WidgetTester tester) async {
    await tester.pumpWidget(_opener((BuildContext context) {
      return showBankpopSpaceCard(
        context,
        _beggarAlley,
        houses: 4,
        hotels: 1,
      );
    }, 'open'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Four houses plus the hotel: five ticks, nothing left to buy.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(5));
    expect(find.byIcon(Icons.add_circle), findsNothing);
  });

  testWidgets('rent values stay right-aligned with the mark beside them',
      (WidgetTester tester) async {
    await tester.pumpWidget(_opener((BuildContext context) {
      return showBankpopSpaceCard(
        context,
        _beggarAlley,
        houses: 1,
        onBuild: (int step) async => false, // the plus only exists with this
      );
    }, 'open'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Rents are 2, 10, 30... and one house is built: its row carries the tick,
    // the next row the plus. Every value has to end at the same right edge.
    final double bare = tester.getTopRight(find.text('\u00a32')).dx;
    final double ticked = tester.getTopRight(find.text('\u00a310')).dx;
    final double offered = tester.getTopRight(find.text('\u00a330')).dx;
    expect(ticked, moreOrLessEquals(bare, epsilon: 0.5));
    expect(offered, moreOrLessEquals(bare, epsilon: 0.5));

    // And the mark is on the left of its value, not trailing the row.
    expect(
      tester.getTopRight(find.byIcon(Icons.check_circle)).dx,
      lessThanOrEqualTo(ticked),
    );
    expect(
      tester.getTopRight(find.byIcon(Icons.add_circle)).dx,
      lessThanOrEqualTo(offered),
    );
  });

  testWidgets('a tile shows one green house per house',
      (WidgetTester tester) async {
    await tester.pumpWidget(_tile(houses: 2));
    await tester.pumpAndSettle();

    expect(_houses, findsNWidgets(2));
    expect(_hotel, findsNothing);
  });

  testWidgets('a hotel replaces the houses with one red building',
      (WidgetTester tester) async {
    await tester.pumpWidget(_tile(houses: 4, hotels: 1));
    await tester.pumpAndSettle();

    expect(_hotel, findsOneWidget);
    expect(_houses, findsNothing);
  });
}
