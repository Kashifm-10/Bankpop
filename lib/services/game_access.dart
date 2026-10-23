import 'package:flutter/foundation.dart';
import 'package:mon/services/player_exit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which table a URL opens.
enum GameSeat {
  banker,
  player,
}

/// The answer to "may this device open this game, in this role?".
///
/// The four cases are kept apart because the screen explains them differently:
/// a stranger must not be told whether the game exists, a seated player who
/// typed the banker URL is told which table is theirs, and an offline device is
/// asked to retry rather than being refused for good.
enum GameAccess {
  allowed,
  notSeated,
  wrongRole,
  unavailable,
}

/// Decides whether the player id on this device has a seat in a game.
///
/// A game URL is a place, not a key: `players_test` holds one row per seat,
/// and only a row whose `player_id` is this device's player is a seat here.
/// Removed players keep their row (with a REMOVED badge on the banker's list),
/// so the check also has to ignore a row whose standing is gone.
///
/// The banker is the holder of the `role = 'banker'` row, which hand-over moves
/// to the new banker's id - so the same rule covers a game that changed hands.
class GameGate {
  const GameGate._();

  /// Asks the database about [gameId], then classifies the rows.
  ///
  /// [seat] null means "any seat at this table" - the history and scanner
  /// screens are for whoever is playing, banker or player.
  static Future<GameAccess> check({
    required String gameId,
    GameSeat? seat,
  }) async {
    final String id = gameId.trim();
    if (id.isEmpty) return GameAccess.notSeated;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String playerId = prefs.getString('playerID') ?? '';
    if (playerId.isEmpty) return GameAccess.notSeated;

    try {
      // `select()` without a column list: player_status.sql is optional, and a
      // project without its `status` column must still answer this question.
      final List<dynamic> rows = await Supabase.instance.client
          .from('players_test')
          .select()
          .eq('game_id', id)
          .eq('player_id', playerId);
      return classify(rows: rows, seat: seat, playerId: playerId);
    } catch (error) {
      // Fail closed. A network answer that could not be read is not permission.
      debugPrint('Could not check the seat in game $id: $error');
      return GameAccess.unavailable;
    }
  }

  /// The rule itself, without the database, so it can be tested directly.
  @visibleForTesting
  static GameAccess classify({
    required Iterable<dynamic> rows,
    required GameSeat? seat,
    required String playerId,
  }) {
    if (playerId.isEmpty) return GameAccess.notSeated;

    bool hasBankerSeat = false;
    bool hasPlayerSeat = false;

    for (final dynamic raw in rows) {
      if (raw is! Map) continue;
      final Map<String, dynamic> row = raw.cast<String, dynamic>();
      // The query already filters on this, and the rule repeats it: a row that
      // belongs to somebody else is never this seat, even if it slips through.
      if ((row['player_id']?.toString() ?? '') != playerId) continue;
      // A removed seat is still a row; it is not a way back into the game.
      if (PlayerStanding.fromRow(row).isGone) continue;
      final String role = row['role']?.toString() ?? '';
      if (role == 'banker') {
        hasBankerSeat = true;
      } else if (role == 'player') {
        hasPlayerSeat = true;
      }
    }

    if (!hasBankerSeat && !hasPlayerSeat) return GameAccess.notSeated;

    return switch (seat) {
      GameSeat.banker =>
        hasBankerSeat ? GameAccess.allowed : GameAccess.wrongRole,
      GameSeat.player =>
        hasPlayerSeat ? GameAccess.allowed : GameAccess.wrongRole,
      null => GameAccess.allowed,
    };
  }
}
