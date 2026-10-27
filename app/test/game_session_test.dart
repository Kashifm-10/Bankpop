import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/game_session.dart';

/// The session row is the only place a device learns the rules of a game and
/// whether it is paused. It is written by the banker's device and read by every
/// player, so the parser has to survive both a full row and a sparse one from a
/// project that has not filled every column yet.
void main() {
  Map<String, dynamic> row() => <String, dynamic>{
        'game_id': 'VGHTH',
        'banker_id': 'bank-1',
        'banker_name': 'Bank',
        'status': 'suspended',
        'payment_option': 'ScanPay',
        'play_with_cards': true,
        'player_value': 1500,
        'advance_value': 200,
        'started_at': '2026-10-20T09:30:00+00:00',
        'ended_at': null,
      };

  test('a full row keeps the rules and the lifecycle', () {
    final GameSession session = GameSession.fromRow(row())!;

    expect(session.gameId, 'VGHTH');
    expect(session.isSuspended, isTrue);
    expect(session.playWithCards, isTrue);
    expect(session.paymentOption, 'ScanPay');
    expect(session.playerValue, 1500);
    expect(session.advanceValue, 200);
    expect(session.startedAt, DateTime.parse('2026-10-20T09:30:00+00:00'));
    expect(session.endedAt, isNull);
  });

  test('a sparse row still yields a playable game', () {
    final GameSession session = GameSession.fromRow(<String, dynamic>{
      'game_id': 'ABCDE',
    })!;

    expect(session.status, GameSession.active);
    expect(session.isActive, isTrue);
    expect(session.playWithCards, isFalse);
    expect(session.playerValue, 0);
    expect(session.advanceValue, 0);
    expect(session.startedAt, isNull);
  });

  test('a row without a game id is not a session', () {
    expect(GameSession.fromRow(<String, dynamic>{}), isNull);
    expect(GameSession.fromRow(<String, dynamic>{'game_id': ''}), isNull);
  });

  test('ending a game marks it ended and keeps the rest', () {
    final GameSession session = GameSession.fromRow(row())!;
    final DateTime endedAt = DateTime.utc(2026, 10, 20, 12);
    final GameSession ended =
        session.copyWith(status: GameSession.ended, endedAt: endedAt);

    expect(ended.isEnded, isTrue);
    expect(ended.isSuspended, isFalse);
    expect(ended.endedAt, endedAt);
    expect(ended.playWithCards, isTrue);
    expect(ended.playerValue, 1500);
  });

  test('resuming clears the end date and reads as playable', () {
    final GameSession session = GameSession.fromRow(row())!;
    final GameSession resumed = session.copyWith(status: GameSession.active);

    expect(resumed.isPlayable, isTrue);
    expect(resumed.isSuspended, isFalse);
    expect(resumed.isEnded, isFalse);
  });
}
