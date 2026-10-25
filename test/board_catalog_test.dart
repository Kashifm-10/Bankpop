import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_catalog.dart';

/// A small board with the shapes that matter: a street, a station, the two
/// fixed utilities, and a deck that mentions spaces by name.
BankpopBoard _board() {
  return const BankpopBoard(
    spaces: <BankpopSpace>[
      BankpopSpace(index: 0, name: 'GO', type: 'Special'),
      BankpopSpace(
        index: 1,
        name: 'Beggar\'s Alley',
        type: 'Property',
        price: 60,
        rent: <int>[2, 10, 30, 90, 160, 250],
        color: 'Brown',
        houseCost: 50,
        hotelCost: 50,
        houses: 4,
        hotels: 1,
      ),
      BankpopSpace(
        index: 5,
        name: 'North Star Station',
        type: 'Property',
        price: 200,
        rent: <int>[25, 50, 100, 200],
        color: 'Station',
      ),
      BankpopSpace(
        index: 12,
        name: 'Electric',
        type: 'Property',
        price: 150,
        rent: <int>[4, 10],
        color: 'Utility',
      ),
      BankpopSpace(
        index: 28,
        name: 'City Water',
        type: 'Property',
        price: 150,
        rent: <int>[4, 10],
        color: 'Utility',
      ),
    ],
    chanceOptions: <String>[
      'Advance to Beggar\'s Alley',
      'Take a trip to North Star Station',
      'Pay school fees of £150',
    ],
    communityChest: <String>[
      'Advance to Go (Collect £200)',
      'Bank error in your favor - Collect £200',
    ],
    boardId: 'usa',
    boardName: 'United States',
  );
}

void main() {
  group('renaming a board', () {
    final BankpopBoard custom = _board().renamed(
      name: 'Home Town',
      renames: const <String, String>{
        'Beggar\'s Alley': 'Chai Stall Lane',
        'North Star Station': 'Mumbai Terminus Station',
      },
    );

    test('changes only the names it was given', () {
      expect(
        custom.spaces.map((BankpopSpace s) => s.name),
        <String>[
          'GO',
          'Chai Stall Lane',
          'Mumbai Terminus Station',
          'Electric',
          'City Water',
        ],
      );
    });

    test('keeps every number the game charges from', () {
      final Map<int, BankpopSpace> before = <int, BankpopSpace>{
        for (final BankpopSpace s in _board().spaces) s.index: s,
      };
      for (final BankpopSpace space in custom.spaces) {
        final BankpopSpace original = before[space.index]!;
        expect(space.type, original.type);
        expect(space.price, original.price);
        expect(space.rent, original.rent);
        expect(space.color, original.color);
        expect(space.houseCost, original.houseCost);
        expect(space.hotelCost, original.hotelCost);
        expect(space.houses, original.houses);
        expect(space.hotels, original.hotels);
      }
    });

    test('points the cards at the new names', () {
      expect(custom.chanceOptions, <String>[
        'Advance to Chai Stall Lane',
        'Take a trip to Mumbai Terminus Station',
        'Pay school fees of £150',
      ]);
      // A card about GO is untouched: GO is not renameable.
      expect(custom.communityChest.first, 'Advance to Go (Collect £200)');
    });

    test('does not chain one rename into another', () {
      // Renaming A to B and B to C in one go must leave A as B, not as C.
      final BankpopBoard swapped = _board().renamed(
        name: 'Swap',
        renames: const <String, String>{
          'Beggar\'s Alley': 'North Star Station',
          'North Star Station': 'Beggar\'s Alley',
        },
      );
      expect(
        swapped.spaces.map((BankpopSpace s) => s.name).toList(),
        containsAll(<String>['North Star Station', 'Beggar\'s Alley']),
      );
    });

    test('reads a database row the way the table stores one', () {
      final BankpopBoard parsed = BankpopBoard.fromMap(<String, dynamic>{
        'board_id': 'custom_1',
        'name': 'Home Town',
        'flag': '',
        'spaces': <Map<String, dynamic>>[
          for (final BankpopSpace space in custom.spaces) space.toMap(),
        ],
        'cards': <String, dynamic>{
          'chanceOptions': custom.chanceOptions,
          'communityChest': custom.communityChest,
        },
      });
      expect(parsed.boardId, 'custom_1');
      expect(parsed.boardName, 'Home Town');
      expect(parsed.spaces.length, custom.spaces.length);
      expect(parsed.chanceOptions, custom.chanceOptions);
    });
  });

  group('the naming rules', () {
    test('a station always ends in Station', () {
      expect(BoardNames.finishStation('Mumbai Terminus'), 'Mumbai Terminus Station');
      expect(BoardNames.finishStation('Mumbai Terminus Station'),
          'Mumbai Terminus Station');
      expect(BoardNames.finishStation('  York station  '), 'York station');
      expect(BoardNames.finishStation('   '), '');
    });

    test('the utilities keep their names', () {
      expect(BoardNames.fixed, containsAll(<String>['Electric', 'City Water']));
    });
  });

  group('the seeded boards', () {
    final File seed = File('supabase/boards.sql');
    final String sql = seed.readAsStringSync();
    final List<String> payloads = RegExp(r'\$json\$(.*?)\$json\$::jsonb',
            dotAll: true)
        .allMatches(sql)
        .map((RegExpMatch match) => match.group(1)!)
        .toList();
    final Map<String, dynamic> template = jsonDecode(
      File('tool/data/board_template.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('every board has the same spaces and prices as the template', () {
      expect(payloads.length, 28, reason: '14 boards x (spaces, cards)');
      final List<dynamic> templateSpaces = template['spaces'] as List<dynamic>;

      for (var i = 0; i < payloads.length; i += 2) {
        final List<dynamic> spaces = jsonDecode(payloads[i]) as List<dynamic>;
        expect(spaces.length, templateSpaces.length);
        for (var s = 0; s < spaces.length; s++) {
          final Map<String, dynamic> seeded = spaces[s] as Map<String, dynamic>;
          final Map<String, dynamic> base =
              templateSpaces[s] as Map<String, dynamic>;
          expect(seeded['index'], base['index']);
          expect(seeded['type'], base['type']);
          expect(seeded['price'], base['price']);
          expect(seeded['rent'], base['rent']);
          expect(seeded['color'], base['color']);
          expect(seeded['houseCost'], base['houseCost']);
          expect(seeded['hotelCost'], base['hotelCost']);
        }
      }
    });

    test('has 14 boards, each with 40 spaces and 26 distinct properties', () {
      final Set<String> firstStreet = <String>{};
      for (var i = 0; i < payloads.length; i += 2) {
        final List<dynamic> spaces = jsonDecode(payloads[i]) as List<dynamic>;
        expect(spaces.length, 40);
        final List<String> properties = <String>[
          for (final dynamic raw in spaces)
            if ((raw as Map<String, dynamic>)['type'] == 'Property')
              raw['name'].toString(),
        ];
        // 22 streets, 4 stations and the 2 fixed utilities.
        expect(properties.length, 28);
        expect(properties.toSet().length, properties.length,
            reason: 'two properties share a name on board ${i ~/ 2}');
        firstStreet.add((spaces[1] as Map<String, dynamic>)['name'].toString());
      }
      // The cheap brown street is renamed on every board.
      expect(firstStreet.length, 14);
    });

    test('keeps Electric, City Water and the Station suffix on every board', () {
      for (var i = 0; i < payloads.length; i += 2) {
        final List<dynamic> spaces = jsonDecode(payloads[i]) as List<dynamic>;
        final List<Map<String, dynamic>> properties = <Map<String, dynamic>>[
          for (final dynamic raw in spaces)
            if ((raw as Map<String, dynamic>)['type'] == 'Property')
              raw,
        ];
        final Iterable<String> names =
            properties.map((Map<String, dynamic> s) => s['name'].toString());
        expect(names, contains('Electric'));
        expect(names, contains('City Water'));
        final Iterable<Map<String, dynamic>> stations =
            properties.where((Map<String, dynamic> s) => s['color'] == 'Station');
        expect(stations.length, 4);
        for (final Map<String, dynamic> station in stations) {
          expect(station['name'].toString(), endsWith('Station'));
        }
      }
    });

    test('the card decks are part of the same board', () {
      for (var i = 1; i < payloads.length; i += 2) {
        final Map<String, dynamic> cards =
            jsonDecode(payloads[i]) as Map<String, dynamic>;
        expect((cards['chanceOptions'] as List<dynamic>).length, 22);
        expect((cards['communityChest'] as List<dynamic>).length, 20);
      }
    });
  });
}
