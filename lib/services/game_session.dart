import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One game, as the backend sees it.
///
/// This is the single source of truth for the rules of a game - the payment
/// mode it was started with, whether it plays with cards, the per-player stake
/// and the round advance - and for its lifecycle. Players read it to learn how
/// the game works and whether it is paused; the banker writes it when they
/// start, suspend, resume or end a game.
///
/// The table is `game_sessions` (see supabase/game_sessions.sql). Games started
/// before that file was applied have no row; every read here returns null for
/// them and the screens fall back to the values they already had.
class GameSession {
  const GameSession({
    required this.gameId,
    required this.bankerId,
    required this.bankerName,
    required this.status,
    required this.paymentOption,
    required this.playWithCards,
    required this.playerValue,
    required this.advanceValue,
    this.startedAt,
    this.endedAt,
  });

  static const String active = 'active';
  static const String suspended = 'suspended';
  static const String ended = 'ended';

  final String gameId;
  final String bankerId;
  final String bankerName;
  final String status;
  final String paymentOption;
  final bool playWithCards;
  final double playerValue;
  final double advanceValue;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isActive => status == active;
  bool get isSuspended => status == suspended;
  bool get isEnded => status == ended;

  /// A game nobody has paused or ended.
  bool get isPlayable => isActive;

  /// True when the lifecycle forbids play: the banker paused the game, or it
  /// ended. Both are look-but-do-not-touch for the players - a pause is
  /// resumable, an end is not, but neither may move money.
  bool get blocksPlay => isSuspended || isEnded;

  /// Why play is blocked, in one sentence naming the banker. Null while the
  /// game is running.
  String? get blockedReason {
    if (isEnded) {
      return 'This game has ended. You can look at your holdings, but nothing '
          'can be paid, traded, built or advanced.';
    }
    if (isSuspended) {
      return 'The banker ($bankerName) paused this game. Only they can resume '
          'it, and everything continues exactly where it stopped.';
    }
    return null;
  }

  GameSession copyWith({String? status, DateTime? endedAt}) => GameSession(
        gameId: gameId,
        bankerId: bankerId,
        bankerName: bankerName,
        status: status ?? this.status,
        paymentOption: paymentOption,
        playWithCards: playWithCards,
        playerValue: playerValue,
        advanceValue: advanceValue,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
      );

  static GameSession? fromRow(Map<String, dynamic> row) {
    final String? gameId = row['game_id']?.toString();
    if (gameId == null || gameId.isEmpty) return null;
    return GameSession(
      gameId: gameId,
      bankerId: row['banker_id']?.toString() ?? '',
      bankerName: row['banker_name']?.toString() ?? 'Bank',
      status: row['status']?.toString() ?? active,
      paymentOption: row['payment_option']?.toString() ?? 'InstantPay',
      playWithCards: row['play_with_cards'] == true,
      playerValue: (row['player_value'] as num?)?.toDouble() ?? 0,
      advanceValue: (row['advance_value'] as num?)?.toDouble() ?? 0,
      startedAt: _parseDate(row['started_at']),
      endedAt: _parseDate(row['ended_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  /// Writes the row for a freshly started game.
  ///
  /// Returns null when the project has not run game_sessions.sql yet; the
  /// caller keeps going with its local values, exactly as before the table
  /// existed.
  static Future<GameSession?> create({
    required String gameId,
    required String bankerId,
    required String bankerName,
    required String paymentOption,
    required bool playWithCards,
    required double playerValue,
    required double advanceValue,
  }) async {
    final Map<String, dynamic> row = <String, dynamic>{
      'game_id': gameId,
      'banker_id': bankerId,
      'banker_name': bankerName,
      'status': active,
      'payment_option': paymentOption,
      'play_with_cards': playWithCards,
      'player_value': playerValue,
      'advance_value': advanceValue,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final dynamic saved = await Supabase.instance.client
          .from('game_sessions')
          .insert(row)
          .select()
          .maybeSingle();
      if (saved is Map<String, dynamic>) return fromRow(saved);
      return fromRow(row);
    } catch (error) {
      debugPrint('Could not create the game session: $error');
      return null;
    }
  }

  /// The session for [gameId], or null when there is none (old game, or a
  /// project without game_sessions.sql).
  static Future<GameSession?> fetch(String gameId) async {
    if (gameId.isEmpty) return null;
    try {
      final Map<String, dynamic>? row = await Supabase.instance.client
          .from('game_sessions')
          .select()
          .eq('game_id', gameId)
          .maybeSingle();
      if (row == null) return null;
      return fromRow(row);
    } catch (error) {
      debugPrint('Could not read the game session: $error');
      return null;
    }
  }

  /// Moves the game to [status]. Ending stamps `ended_at`; resuming clears it
  /// so a game that is picked up again reads as running, not finished.
  static Future<bool> setStatus(String gameId, String status) async {
    if (gameId.isEmpty) return false;
    final Map<String, dynamic> update = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'ended_at':
          status == ended ? DateTime.now().toUtc().toIso8601String() : null,
    };
    try {
      await Supabase.instance.client
          .from('game_sessions')
          .update(update)
          .eq('game_id', gameId);
      return true;
    } catch (error) {
      debugPrint('Could not update the game session: $error');
      return false;
    }
  }

  /// Hands the bank to another seat: the bank row keeps the bank's wallet and
  /// takes the new banker's id, and the session names them from then on.
  ///
  /// The bank is a row like any other (`role = 'banker'`), so moving it is one
  /// update rather than a new role for the device; whoever holds that id from
  /// now on is the banker, and the old device simply stops being one. Nothing
  /// about the money changes: the stake, the advances and the fines all stay in
  /// the same wallet.
  static Future<bool> handOverBank({
    required String gameId,
    required String newBankerId,
    required String newBankerName,
  }) async {
    if (gameId.isEmpty || newBankerId.isEmpty) return false;
    final SupabaseClient supabase = Supabase.instance.client;

    try {
      final List<dynamic> moved = await supabase
          .from('players_test')
          .update(<String, dynamic>{'player_id': newBankerId})
          .eq('game_id', gameId)
          .eq('role', 'banker')
          .select('id');
      if (moved.isEmpty) {
        debugPrint('No bank row to move in game $gameId');
        return false;
      }
    } catch (error) {
      debugPrint('Could not move the bank row: $error');
      return false;
    }

    // The session is where the banners learn who the banker is. A game started
    // before game_sessions.sql has no row to update, and the roster move above
    // is the part that decides who can actually bank.
    try {
      await supabase.from('game_sessions').update(<String, dynamic>{
        'banker_id': newBankerId,
        'banker_name': newBankerName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('game_id', gameId);
    } catch (error) {
      debugPrint('Could not name the new banker in the session: $error');
    }
    return true;
  }

  /// Live status changes. The screens keep their reconciliation poll as a
  /// safety net if the socket cannot connect.
  static Stream<GameSession> stream(String gameId) {
    return Supabase.instance.client
        .from('game_sessions')
        .stream(primaryKey: const <String>['id'])
        .eq('game_id', gameId)
        .map((List<Map<String, dynamic>> rows) {
          if (rows.isEmpty) return null;
          return fromRow(rows.first);
        })
        .where((GameSession? session) => session != null)
        .cast<GameSession>();
  }
}
