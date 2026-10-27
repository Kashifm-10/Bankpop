import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/building_rules.dart';

BankpopSpace _space(
  int index,
  String name, {
  String color = 'Brown',
  int houseCost = 50,
  int hotelCost = 50,
}) {
  return BankpopSpace(
    index: index,
    name: name,
    type: 'Property',
    price: 60,
    rent: const <int>[2, 10, 30, 90, 160, 250],
    color: color,
    houseCost: houseCost,
    hotelCost: hotelCost,
  );
}

void main() {
  final BankpopSpace first = _space(1, 'Beggar\u2019s Alley');
  final BankpopSpace second = _space(3, 'Rye Lane');
  final List<BankpopSpace> browns = <BankpopSpace>[first, second];

  test('the whole colour set is needed before a house', () {
    final BuildingDecision decision = BuildingRules.next(
      space: first,
      set: browns,
      ownedCards: <int>{first.index}, // only half the set
      houses: 0,
      hotels: 0,
      housesByCard: <int, int>{first.index: 0},
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('whole Brown set'));
    expect(decision.reason, contains('Rye Lane'));
  });

  test('with the set complete, the first house is offered at its price', () {
    final BuildingDecision decision = BuildingRules.next(
      space: first,
      set: browns,
      ownedCards: <int>{first.index, second.index},
      houses: 0,
      hotels: 0,
      housesByCard: <int, int>{first.index: 0, second.index: 0},
    );

    expect(decision.allowed, isTrue);
    expect(decision.kind, BuildingKind.house);
    expect(decision.price, 50);
  });

  test('a second house waits until the rest of the set has its first', () {
    final BuildingDecision decision = BuildingRules.next(
      space: first,
      set: browns,
      ownedCards: <int>{first.index, second.index},
      houses: 1,
      hotels: 0,
      housesByCard: <int, int>{first.index: 1, second.index: 0},
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('Build evenly'));
  });

  test('a card that is behind may catch up', () {
    final BuildingDecision decision = BuildingRules.next(
      space: second,
      set: browns,
      ownedCards: <int>{first.index, second.index},
      houses: 0,
      hotels: 0,
      housesByCard: <int, int>{first.index: 1, second.index: 0},
    );

    expect(decision.allowed, isTrue);
    expect(decision.kind, BuildingKind.house);
  });

  test('a hotel needs four houses on every card in the set', () {
    final BuildingDecision tooEarly = BuildingRules.next(
      space: first,
      set: browns,
      ownedCards: <int>{first.index, second.index},
      houses: 4,
      hotels: 0,
      housesByCard: <int, int>{first.index: 4, second.index: 3},
    );
    expect(tooEarly.allowed, isFalse);
    expect(tooEarly.reason, contains('before a hotel'));

    final BuildingDecision ready = BuildingRules.next(
      space: first,
      set: browns,
      ownedCards: <int>{first.index, second.index},
      houses: 4,
      hotels: 0,
      housesByCard: <int, int>{first.index: 4, second.index: 4},
    );
    expect(ready.allowed, isTrue);
    expect(ready.kind, BuildingKind.hotel);
    expect(ready.price, 50);
  });

  test('a card that already has a hotel takes no more buildings', () {
    final BuildingDecision decision = BuildingRules.next(
      space: first,
      set: browns,
      ownedCards: <int>{first.index, second.index},
      houses: 4,
      hotels: 1,
      housesByCard: <int, int>{first.index: 4, second.index: 4},
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('already has a hotel'));
  });

  test('Stations and Utilities take no buildings', () {
    final BankpopSpace station =
        _space(5, 'Station One', color: 'Station');
    final BuildingDecision decision = BuildingRules.next(
      space: station,
      set: <BankpopSpace>[station],
      ownedCards: <int>{station.index},
      houses: 0,
      hotels: 0,
      housesByCard: <int, int>{station.index: 0},
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('colour properties'));
  });
}
