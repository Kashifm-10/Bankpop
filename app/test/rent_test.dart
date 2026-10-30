import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/rent.dart';

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

const BankpopSpace _station = BankpopSpace(
  index: 5,
  name: 'Grand Central Station',
  type: 'Property',
  price: 200,
  rent: <int>[25, 50, 100, 200],
  color: 'Station',
);

const BankpopSpace _stationTwo = BankpopSpace(
  index: 15,
  name: 'Union Depot Station',
  type: 'Property',
  price: 200,
  rent: <int>[25, 50, 100, 200],
  color: 'Station',
);

const BankpopSpace _electric = BankpopSpace(
  index: 12,
  name: 'Electric',
  type: 'Property',
  price: 150,
  rent: <int>[4, 10],
  color: 'Utility',
);

const BankpopSpace _water = BankpopSpace(
  index: 28,
  name: 'City Water',
  type: 'Property',
  price: 150,
  rent: <int>[4, 10],
  color: 'Utility',
);

const BankpopSpace _stationThree = BankpopSpace(
  index: 25,
  name: 'Pacific Terminal Station',
  type: 'Property',
  price: 200,
  rent: <int>[25, 50, 100, 200],
  color: 'Station',
);

const BankpopSpace _stationFour = BankpopSpace(
  index: 35,
  name: 'Atlantic Junction Station',
  type: 'Property',
  price: 200,
  rent: <int>[25, 50, 100, 200],
  color: 'Station',
);

const Map<int, BankpopSpace> _spaces = <int, BankpopSpace>{
  1: _brown,
  5: _station,
  12: _electric,
  15: _stationTwo,
  25: _stationThree,
  28: _water,
  35: _stationFour,
};

PlayerCard _card(
  int index, {
  int houses = 0,
  int hotels = 0,
  bool mortgaged = false,
}) {
  return PlayerCard(
    id: 1,
    cardIndex: index,
    from: 'Bank',
    to: 'Ameen',
    date: '2026-05-26',
    time: '21:49:36',
    houses: houses,
    hotels: hotels,
    mortgaged: mortgaged,
  );
}

RentDue _due(
  BankpopSpace space,
  PlayerCard card, {
  List<PlayerCard>? hand,
  int? dice,
}) {
  return Rent.forCard(
    space: space,
    card: card,
    ownerCards: hand ?? <PlayerCard>[card],
    spaces: _spaces,
    dice: dice,
  );
}

void main() {
  test('a bare colour card collects its base rent', () {
    expect(_due(_brown, _card(1)).amount, 2);
  });

  test('houses and a hotel move the rent to their own line', () {
    expect(_due(_brown, _card(1, houses: 1)).amount, 10);
    expect(_due(_brown, _card(1, houses: 3)).amount, 90);
    expect(_due(_brown, _card(1, houses: 4, hotels: 1)).amount, 250);
  });

  test('a mortgaged card collects nothing, whatever is built on it', () {
    final RentDue due =
        _due(_brown, _card(1, houses: 4, hotels: 1, mortgaged: true));
    expect(due.rentFree, isTrue);
    expect(due.amount, 0);
  });

  test('a station pays by how many stations its owner holds', () {
    final PlayerCard first = _card(5);

    expect(_due(_station, first).amount, 25);
    expect(
      _due(_station, first, hand: <PlayerCard>[first, _card(15)]).amount,
      50,
    );
    expect(
      _due(
        _station,
        first,
        hand: <PlayerCard>[
          first,
          _card(15),
          _card(25),
          _card(35),
        ],
      ).amount,
      200,
    );
  });

  test('a station counts only its own group, not the whole hand', () {
    final PlayerCard station = _card(5);
    final RentDue due = _due(
      _station,
      station,
      hand: <PlayerCard>[station, _card(1), _card(12)],
    );
    expect(due.amount, 25);
  });

  test('utility rent is a multiple of the throw', () {
    final PlayerCard electric = _card(12);

    final RentDue one = _due(_electric, electric, dice: 7);
    expect(one.needsDice, isTrue);
    expect(one.diceMultiplier, 4);
    expect(one.amount, 28);

    final RentDue both = _due(
      _electric,
      electric,
      hand: <PlayerCard>[electric, _card(28)],
      dice: 7,
    );
    expect(both.diceMultiplier, 10);
    expect(both.amount, 70);
  });

  test('a utility without a throw waits for the dice', () {
    final RentDue due = _due(_electric, _card(12));
    expect(due.needsDice, isTrue);
    expect(due.amount, 0);
  });

  test('a card with no rent table collects nothing', () {
    const BankpopSpace blank = BankpopSpace(
      index: 2,
      name: 'Community Chest',
      type: 'Special',
    );
    expect(_due(blank, _card(2)).amount, 0);
  });
}
