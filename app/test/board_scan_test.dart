// A photograph of a board gives more than square names: prices, the corner
// words, the ring's numbers and whatever the camera caught around the board.
// These tests pin what survives that cleaning, and that the names land on the
// squares in board order with anything unread left as it was.

import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_scan.dart';

BankpopSpace _space(int index, String name, {String color = 'Brown'}) {
  return BankpopSpace(
    index: index,
    name: name,
    type: 'Property',
    color: color,
    price: 60,
  );
}

void main() {
  test('a name is tidied, and a price under it is not a name', () {
    expect(BoardScan.clean('  NORTH   STAR STATION  '), 'North Star Station');
    expect(BoardScan.clean('NORTH STAR STATION 200'), 'North Star Station');
    expect(BoardScan.clean('₹200'), '');
    expect(BoardScan.clean('200'), '');
    expect(BoardScan.clean('12'), '');
    expect(BoardScan.clean('A1'), '');
    expect(BoardScan.clean('...'), '');
  });

  test('the board keeps its own words for the squares it names itself', () {
    final List<String> names = BoardScan.names(<String>[
      'GO',
      'Community Chest',
      'CHANCE',
      'Free Parking',
      'Go To Jail',
      'Income Tax',
      'Super Tax',
      'Jail',
      'Electric',
      'Beggar\'s Alley',
    ]);
    expect(names, <String>['Beggar\'s Alley']);
  });

  test('a repeated line is used once', () {
    final List<String> names = BoardScan.names(<String>[
      'Peasant Lane',
      'PEASANT LANE',
      'peasant lane',
    ]);
    expect(names, <String>['Peasant Lane']);
  });

  test('names land on the squares in board order', () {
    final List<BankpopSpace> slots = <BankpopSpace>[
      _space(1, 'Beggar\'s Alley'),
      _space(3, 'Peasant Lane'),
      _space(5, 'North Star Station', color: 'Station'),
    ];
    final BoardRead read = BoardScan.apply(<String>[
      'HARBOUR ROAD',
      '200',
      'Harbour Road',
      'FISHERMAN\'S QUAY',
    ], slots);

    expect(read.names, <String>['Harbour Road', 'Fisherman\'s Quay', 'North Star Station']);
    expect(read.fromPhoto, <bool>[true, true, false]);
    expect(read.captured, 2);
  });

  test('a picture that reads nothing leaves the built-in names', () {
    final List<BankpopSpace> slots = <BankpopSpace>[
      _space(1, 'Beggar\'s Alley'),
      _space(3, 'Peasant Lane'),
    ];
    final BoardRead read = BoardScan.apply(<String>['12', '₹'], slots);

    expect(read.names, <String>['Beggar\'s Alley', 'Peasant Lane']);
    expect(read.captured, 0);
    expect(read.isEmpty, isTrue);
  });

  test('the utilities are not renamable, and the rest are in order', () {
    final BankpopBoard board = BankpopBoard.fromMap(<String, dynamic>{
      'board_id': 'test',
      'name': 'Test Land',
      'flag': '',
      'spaces': <Map<String, dynamic>>[
        <String, dynamic>{'index': 12, 'name': 'Electric', 'type': 'Property', 'color': 'Utility'},
        <String, dynamic>{'index': 3, 'name': 'Peasant Lane', 'type': 'Property', 'color': 'Brown'},
        <String, dynamic>{'index': 0, 'name': 'GO', 'type': 'Special'},
        <String, dynamic>{'index': 28, 'name': 'City Water', 'type': 'Property', 'color': 'Utility'},
        <String, dynamic>{'index': 5, 'name': 'North Star Station', 'type': 'Property', 'color': 'Station'},
      ],
      'cards': const <String, dynamic>{},
    });

    final List<BankpopSpace> slots = BoardScan.renamable(board);
    expect(slots.map((BankpopSpace s) => s.index), <int>[3, 5]);
    expect(slots.map((BankpopSpace s) => s.name),
        <String>['Peasant Lane', 'North Star Station']);
  });
}
