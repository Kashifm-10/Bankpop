import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_share.dart';

/// A board shaped like a row of `game_boards`: two streets, a station and a
/// fixed utility.
BankpopBoard _board({String street = 'Boardwalk', String station = 'Grand Central Station'}) {
  return BankpopBoard(
    boardId: 'custom_test',
    boardName: 'Test Land',
    spaces: <BankpopSpace>[
      const BankpopSpace(
        index: 1,
        name: 'Mediterranean Avenue',
        type: 'Property',
        price: 60,
        rent: <int>[2, 10, 30],
        color: 'Brown',
      ),
      BankpopSpace(
        index: 2,
        name: station,
        type: 'Property',
        price: 200,
        rent: <int>[25, 50, 100],
        color: 'Station',
      ),
      BankpopSpace(
        index: 3,
        name: street,
        type: 'Property',
        price: 400,
        rent: <int>[50, 200, 600],
        color: 'Dark Blue',
        houseCost: 200,
        hotelCost: 200,
      ),
    ],
    chanceOptions: <String>['Advance to $street', 'Pay bank'],
    communityChest: <String>['Receive from bank'],
  );
}

String _document(Map<String, dynamic> body) => jsonEncode(<String, dynamic>{
      'format': 'bankpop-board',
      'version': 1,
      'basedOn': 'usa',
      ...body,
    });

void main() {
  group('a shared board', () {
    test('carries the name and every renamed space', () {
      final BoardDraft draft = BoardShare.decode(_document(<String, dynamic>{
        'name': 'My Home Town',
        'spaces': <String, String>{
          'Mediterranean Avenue': 'Gandhi Road',
          'Boardwalk': 'Marine Drive',
        },
      }));

      expect(draft.name, 'My Home Town');
      expect(draft.baseId, 'usa');
      expect(draft.renames['Mediterranean Avenue'], 'Gandhi Road');
      expect(draft.renames['Boardwalk'], 'Marine Drive');
      expect(draft.renames.length, 2);
    });

    test('carries the name and every renamed space by index', () {
      final BoardDraft draft = BoardShare.decode(_document(<String, dynamic>{
        'name': 'My Home Town',
        'spaces': <Map<String, dynamic>>[
          {'index': 1, 'name': 'Gandhi Road'},
          {'index': 3, 'name': 'Marine Drive'},
        ],
      }));

      expect(draft.name, 'My Home Town');
      expect(draft.baseId, 'usa');
      expect(draft.renamesByIndex[1], 'Gandhi Road');
      expect(draft.renamesByIndex[3], 'Marine Drive');
      expect(draft.renamesByIndex.length, 2);
    });

    test('does not carry anything but index and name', () {
      final BoardDraft draft = BoardShare.decode(_document(<String, dynamic>{
        'name': 'Cheap Land',
        'spaces': <Map<String, dynamic>>[
          {'index': 3, 'name': 'Free Street'},
          // A hand-written file cannot smuggle prices into an index entry:
          // only "index" and "name" are read from each card.
          {'index': 3, 'name': 'Free Street', 'price': 0},
        ],
      }));

      expect(draft.renamesByIndex.keys, <int>{3});
      expect(draft.renamesByIndex.values, <String>['Free Street']);
    });

    test('a board with no renames is still a board', () {
      final BoardDraft draft = BoardShare.decode(_document(<String, dynamic>{
        'name': 'Plain Country',
      }));

      expect(draft.renames, isEmpty);
      expect(draft.baseId, 'usa');
    });

    test('falls back to the default country when the base is not named', () {
      final BoardDraft draft = BoardShare.decode(jsonEncode(<String, dynamic>{
        'format': 'bankpop-board',
        'version': 1,
        'name': 'Nameless Base',
      }));

      expect(draft.baseId, 'usa');
    });

    test('the file name is safe for any board name', () {
      expect(BoardShare.fileName('My Home Town'), 'bankpop-my-home-town.json');
      expect(BoardShare.fileName('  Ünïcode & Co.  '), 'bankpop-n-code-co.json');
      expect(BoardShare.fileName('!!!'), 'bankpop-board.json');
    });
  });

  group('the index format', () {
    test('a shared board carries the index and the name of every card', () async {
      final String text =
          await BoardShare.encode(_board(street: 'Marine Drive'));
      final Map<String, dynamic> doc =
          jsonDecode(text) as Map<String, dynamic>;

      expect(doc['version'], BoardShare.version);
      final List<dynamic> spaces = doc['spaces'] as List<dynamic>;
      expect(spaces.first, <String, dynamic>{
        'index': 1,
        'name': 'Mediterranean Avenue',
      });
      // Nothing but the card number and the editable name travels.
      for (final dynamic entry in spaces) {
        expect((entry as Map<String, dynamic>).keys.toSet(),
            <String>{'index', 'name'});
      }
      expect(text.contains('"price"'), isFalse);
      expect(text.contains('"rent"'), isFalse);
      expect(text.contains('"color"'), isFalse);
    });

    test('the index ties a name to its card', () {
      final BoardDraft draft = BoardShare.decode(jsonEncode(<String, dynamic>{
        'format': 'bankpop-board',
        'version': 2,
        'name': 'Index Land',
        'basedOn': 'usa',
        'spaces': <Map<String, Object>>[
          <String, Object>{'index': 3, 'name': 'Marine Drive'},
        ],
      }));

      expect(draft.renamesByIndex[3], 'Marine Drive');
      expect(draft.renames, isEmpty);
    });

    test('a card with no usable index is refused', () {
      expect(
        () => BoardShare.decode(jsonEncode(<String, dynamic>{
          'format': 'bankpop-board',
          'version': 2,
          'name': 'No Index Land',
          'spaces': <Map<String, Object>>[
            <String, Object>{'name': 'Marine Drive'},
          ],
        })),
        throwsA(isA<BoardImportFailure>()),
      );
    });
  });

  group('a paste that is not a board', () {
    String message(String text) {
      try {
        BoardShare.decode(text);
      } on BoardImportFailure catch (failure) {
        return failure.message;
      }
      return '';
    }

    test('empty text asks for the text', () {
      expect(message('   '), contains('Paste'));
    });

    test('plain words are refused', () {
      expect(message('hello there'), contains('not a board file'));
    });

    test('valid JSON that is not a board is refused', () {
      expect(
        message(jsonEncode(<String, dynamic>{'name': 'Nope'})),
        contains('not a Bankpop board file'),
      );
    });

    test('a newer file is refused rather than half-read', () {
      expect(
        message(jsonEncode(<String, dynamic>{
          'format': 'bankpop-board',
          'version': 99,
          'name': 'From The Future',
        })),
        contains('newer version'),
      );
    });

    test('a board with no name is refused', () {
      expect(
        message(_document(<String, dynamic>{'spaces': <String, String>{}})),
        contains('no name'),
      );
    });

    test('a space cannot be renamed to a fixed one', () {
      expect(
        message(_document(<String, dynamic>{
          'name': 'Clever Land',
          'spaces': <String, String>{'Boardwalk': 'electric'},
        })),
        contains('fixed space'),
      );
    });

    test('a blank space name is refused', () {
      expect(
        message(_document(<String, dynamic>{
          'name': 'Half Land',
          'spaces': <String, String>{'Boardwalk': '   '},
        })),
        contains('no name'),
      );
    });
  });

  group('the copy a device keeps of a game board', () {
    test('survives a trip through storage and back', () {
      final BankpopBoard board = _board().renamed(
        renames: <String, String>{'Boardwalk': 'Marine Drive'},
        name: 'Test Land',
      );

      // What the cache stores is the row shape, so it goes through JSON the
      // same way it does in SharedPreferences.
      final Map<String, dynamic> row = jsonDecode(jsonEncode(board.toMap()))
          as Map<String, dynamic>;
      final BankpopBoard restored = BankpopBoard.fromMap(row);

      expect(restored.boardId, 'custom_test');
      expect(restored.boardName, 'Test Land');
      expect(restored.spaces.length, 3);
      expect(restored.spaces.last.name, 'Marine Drive');
      expect(restored.spaces.last.price, 400);
      expect(restored.spaces.last.rent, <int>[50, 200, 600]);
      expect(restored.spaces.last.color, 'Dark Blue');
      expect(restored.spaces.last.hotelCost, 200);
      expect(restored.chanceOptions, board.chanceOptions);
      expect(restored.communityChest, board.communityChest);
    });
  });
}
