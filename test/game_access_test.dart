import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/game_access.dart';

/// A game URL may only open for a device that holds a seat in that game. These
/// tests pin the rule itself; the database call in front of it only supplies
/// the rows.
void main() {
  Map<String, dynamic> seat(String role, {String? status}) => <String, dynamic>{
        'role': role,
        'player_id': 'me',
        if (status != null) 'status': status,
      };

  group('GameGate', () {
    test('no row means no seat', () {
      expect(
        GameGate.classify(
            rows: <dynamic>[], seat: GameSeat.player, playerId: 'me'),
        GameAccess.notSeated,
      );
    });

    test('a player seat opens the player table', () {
      expect(
        GameGate.classify(
            rows: <dynamic>[seat('player')],
            seat: GameSeat.player,
            playerId: 'me'),
        GameAccess.allowed,
      );
    });

    test('a player seat does not open the bank', () {
      expect(
        GameGate.classify(
            rows: <dynamic>[seat('player')],
            seat: GameSeat.banker,
            playerId: 'me'),
        GameAccess.wrongRole,
      );
    });

    test('the bank seat opens the banker table', () {
      expect(
        GameGate.classify(
            rows: <dynamic>[seat('banker')],
            seat: GameSeat.banker,
            playerId: 'me'),
        GameAccess.allowed,
      );
    });

    test('the bank seat does not open a player table', () {
      expect(
        GameGate.classify(
            rows: <dynamic>[seat('banker')],
            seat: GameSeat.player,
            playerId: 'me'),
        GameAccess.wrongRole,
      );
    });

    test('history and the scanner accept either seat', () {
      expect(
        GameGate.classify(
            rows: <dynamic>[seat('banker')], seat: null, playerId: 'me'),
        GameAccess.allowed,
      );
      expect(
        GameGate.classify(
            rows: <dynamic>[seat('player')], seat: null, playerId: 'me'),
        GameAccess.allowed,
      );
      expect(
        GameGate.classify(rows: <dynamic>[], seat: null, playerId: 'me'),
        GameAccess.notSeated,
      );
    });

    test('a removed seat is no seat, even though its row remains', () {
      expect(
        GameGate.classify(
          rows: <dynamic>[seat('player', status: 'kicked')],
          seat: GameSeat.player,
          playerId: 'me',
        ),
        GameAccess.notSeated,
      );
      // Projects without player_status.sql mark a removal with the role.
      expect(
        GameGate.classify(
            rows: <dynamic>[seat('kicked')], seat: null, playerId: 'me'),
        GameAccess.notSeated,
      );
    });

    test('a device with both rows may open either table', () {
      final List<dynamic> rows = <dynamic>[seat('banker'), seat('player')];
      expect(
          GameGate.classify(rows: rows, seat: GameSeat.banker, playerId: 'me'),
          GameAccess.allowed);
      expect(
          GameGate.classify(rows: rows, seat: GameSeat.player, playerId: 'me'),
          GameAccess.allowed);
    });

    test('rows for another player are ignored', () {
      expect(
        GameGate.classify(
          rows: <dynamic>[
            <String, dynamic>{'role': 'player', 'player_id': 'someone-else'},
          ],
          seat: GameSeat.player,
          playerId: 'me',
        ),
        GameAccess.notSeated,
      );
    });

    test('an unexpected role is not a seat', () {
      expect(
        GameGate.classify(
            rows: <dynamic>[seat('spectator')], seat: null, playerId: 'me'),
        GameAccess.notSeated,
      );
    });
  });
}
