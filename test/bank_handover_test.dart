// The hand-over code is a QR of its own: it asks a player who is not at the
// table to take the bank, and it must never be read as a join code. These pin
// the parsing and the viewing seat the previous banker keeps.

import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/bank_handover.dart';
import 'package:mon/services/game_access.dart';

void main() {
  group('BankHandover.parse', () {
    test('reads the invite a banker shows', () {
      final HandoverInvite? invite = BankHandover.parse(
        BankHandover.payload(gameId: 'ABC123', bankerId: 'bank-1'),
      );
      expect(invite, isNotNull);
      expect(invite!.gameId, 'ABC123');
      expect(invite.bankerId, 'bank-1');
    });

    test('a join code is not a hand-over', () {
      expect(BankHandover.parse('ABC123'), isNull);
      expect(BankHandover.parse('{"gameId":"ABC123"}'), isNull);
      expect(BankHandover.parse('not json'), isNull);
    });

    test('a payment code is not a hand-over', () {
      expect(
        BankHandover.parse(
          '{"playerID":"p1","name":"Ana","value":"20","role":"player"}',
        ),
        isNull,
      );
    });
  });

  group('hand-over rows', () {
    test('a claim is marked by its own role', () {
      expect(
        BankHandover.isClaim(<String, dynamic>{'role': BankHandover.requestRole}),
        isTrue,
      );
      expect(
        BankHandover.isClaim(<String, dynamic>{'role': 'player'}),
        isFalse,
      );
    });

    test('a claim keeps the backend id it has to delete', () {
      final HandoverRequest request = HandoverRequest.fromRow(
        <String, dynamic>{'id': 42, 'player_id': 'p1', 'name': 'Ana'},
      );
      expect(request.id, 42);
      expect(request.playerId, 'p1');
      expect(request.name, 'Ana');
    });
  });

  group('the ex-banker seat', () {
    Map<String, dynamic> seat(String role) =>
        <String, dynamic>{'role': role, 'player_id': 'me'};

    test('watches the player table but never the bank', () {
      expect(
        GameGate.classify(
          rows: <dynamic>[seat(BankHandover.exBankerRole)],
          seat: GameSeat.player,
          playerId: 'me',
        ),
        GameAccess.allowed,
      );
      expect(
        GameGate.classify(
          rows: <dynamic>[seat(BankHandover.exBankerRole)],
          seat: GameSeat.banker,
          playerId: 'me',
        ),
        GameAccess.wrongRole,
      );
      expect(
        GameGate.classify(
          rows: <dynamic>[seat(BankHandover.exBankerRole)],
          seat: null,
          playerId: 'me',
        ),
        GameAccess.allowed,
      );
    });

    test('a kicked ex-banker has no seat left', () {
      expect(
        GameGate.classify(
          rows: <dynamic>[
            <String, dynamic>{
              'role': BankHandover.exBankerRole,
              'player_id': 'me',
              'status': 'kicked',
            },
          ],
          seat: GameSeat.player,
          playerId: 'me',
        ),
        GameAccess.notSeated,
      );
    });
  });
}
