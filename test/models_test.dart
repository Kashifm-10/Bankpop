// Regression tests for the models that drive the polling screens.
//
// These cover the two things the performance work depends on: Player value
// equality (without it `listEquals` can never be true, so every tick rebuilt the
// whole roster) and the tolerant parsing the history screen relies on.

import 'package:flutter_test/flutter_test.dart';
import 'package:mon/pages/player/player_screen.dart';
import 'package:mon/pages/transactions/transactions.dart';

void main() {
  Map<String, dynamic> playerRow() => <String, dynamic>{
        'player_id': 'p1r2o3b4e5',
        'name': 'Ameen',
        'wallet': 100,
        'avatar': 'assets/avatars/boy1.jpg',
      };

  test('an unchanged roster compares equal, so the screens skip the rebuild',
      () {
    final Player original = Player.fromMap(playerRow());
    final Player refetched = Player.fromMap(playerRow());

    expect(refetched, equals(original));
    expect(refetched.hashCode, equals(original.hashCode));
  });

  test('a moved wallet or a new avatar is a different player', () {
    final Player original = Player.fromMap(playerRow());

    expect(Player.fromMap(<String, dynamic>{
      ...playerRow(),
      'wallet': 101,
    }), isNot(equals(original)));
    expect(Player.fromMap(<String, dynamic>{
      ...playerRow(),
      'avatar': 'assets/avatars/girl2.jpg',
    }), isNot(equals(original)));
    expect(Player.fromMap(<String, dynamic>{
      ...playerRow(),
      'name': 'Someone else',
    }), isNot(equals(original)));
  });

  test('a sparse transaction row parses without throwing', () {
    // The history screen used to index from[0]/to[0] and DateTime.parse the
    // joined date+time, so a row with missing fields took the screen down.
    final Transaction transaction = Transaction.fromMap(<String, dynamic>{});

    expect(transaction.from, isEmpty);
    expect(transaction.to, isEmpty);
    expect(transaction.value, 0.0);
    expect(transaction.dateTime.trim(), isEmpty);
  });

  test('a full transaction row keeps its values', () {
    final Transaction transaction = Transaction.fromMap(<String, dynamic>{
      'from': 'banker',
      'to': 'ameen',
      'value': 15,
      'date': '2026-05-26',
      'time': '21:49:36',
      'code': 'payer_receiver',
    });

    expect(transaction.from, 'banker');
    expect(transaction.to, 'ameen');
    expect(transaction.value, 15.0);
    expect(DateTime.tryParse(transaction.dateTime.trim()), isNotNull);
  });
}
