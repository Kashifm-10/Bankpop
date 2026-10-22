// The trade builder used to list cards as plain checkboxes, which lost the one
// thing a player needs to make an offer: the colour group. These pin the picker
// that replaced it - grouped by colour, one tile per card, selectable, and never
// offering a card that still has buildings on it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/trade_builder_dialog.dart';

const BankpopSpace _brown1 = BankpopSpace(
  index: 1,
  name: "Beggar's Alley",
  type: 'Property',
  price: 60,
  rent: <int>[2, 10, 30, 90, 160, 250],
  color: 'Brown',
  houseCost: 50,
  hotelCost: 50,
);

const BankpopSpace _brown2 = BankpopSpace(
  index: 3,
  name: 'Mud Lane',
  type: 'Property',
  price: 60,
  rent: <int>[4, 20, 60, 180, 320, 450],
  color: 'Brown',
  houseCost: 50,
  hotelCost: 50,
);

const BankpopSpace _blue1 = BankpopSpace(
  index: 6,
  name: 'Harbour Road',
  type: 'Property',
  price: 100,
  rent: <int>[6, 30, 90, 270, 400, 550],
  color: 'Light Blue',
  houseCost: 50,
  hotelCost: 50,
);

const Map<int, BankpopSpace> _spaces = <int, BankpopSpace>{
  1: _brown1,
  3: _brown2,
  6: _blue1,
};

PlayerCard _card(int index, {int houses = 0}) => PlayerCard(
      id: index,
      cardIndex: index,
      from: 'Bank',
      to: 'Me',
      date: '2026-01-01',
      time: '10:00:00',
      houses: houses,
    );

Widget _dialog(List<PlayerCard> mine) => MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          AppFrame(child: child ?? const SizedBox.shrink()),
      home: Scaffold(
        body: TradeBuilderDialog(
          gameId: 'TEST',
          myId: 'me',
          myName: 'Me',
          myCards: mine,
          spaces: _spaces,
          players: const <Map<String, dynamic>>[],
        ),
      ),
    );

void main() {
  testWidgets('cards are grouped by colour and can be picked',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_dialog(<PlayerCard>[
      _card(1),
      _card(3),
      _card(6),
    ]));
    await tester.pumpAndSettle();

    // Group headers, in board order: Brown first, then Light Blue.
    expect(find.text('Brown'), findsOneWidget);
    expect(find.text('Light Blue'), findsOneWidget);

    // Every card is offered by name, not as an opaque "Card #1".
    expect(find.text("Beggar's Alley"), findsOneWidget);
    expect(find.text('Mud Lane'), findsOneWidget);
    expect(find.text('Harbour Road'), findsOneWidget);

    // A tap picks the card; the tick is the visible state, so a second tap
    // has to take it back off.
    final Finder mud = find.text('Mud Lane');
    await tester.tap(mud);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(mud);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('a card with buildings says why it cannot be traded',
      (WidgetTester tester) async {
    await tester.pumpWidget(_dialog(<PlayerCard>[_card(1, houses: 2)]));
    await tester.pumpAndSettle();

    expect(find.text('Sell buildings first'), findsOneWidget);

    await tester.tap(find.text("Beggar's Alley"));
    await tester.pump();
    expect(
      find.byIcon(Icons.check_circle),
      findsNothing,
      reason: 'a built-on card must not be selectable',
    );
  });

  testWidgets('an empty hand reads as empty rather than as an error',
      (WidgetTester tester) async {
    await tester.pumpWidget(_dialog(const <PlayerCard>[]));
    await tester.pumpAndSettle();

    expect(find.text('No cards here yet.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
