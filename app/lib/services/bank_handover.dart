import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mon/services/game_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The code a banker shows when they want somebody else to take the bank.
///
/// A hand-over is not the same thing as a join: the player who scans must not
/// already be at the table, and nothing happens until the banker confirms on
/// their own screen. The code therefore carries the game and who showed it, and
/// the claim is queued in `request_test` under its own role so the join-request
/// dialogs never mistake it for somebody asking for a seat.
///
/// Once the banker confirms, the bank row (which carries the bank's wallet)
/// moves to the scanner's id, exactly as a hand-over to a seated player used
/// to. The previous banker keeps a row of their own with the [exBankerRole], so
/// the game stays in Your Games and opens read-only for them.
class BankHandover {
  const BankHandover._();

  /// Marks the payload so a normal join code is never mistaken for one.
  static const String kind = 'bank_handover';

  /// The `request_test.role` of a queued hand-over claim.
  static const String requestRole = 'handover';

  /// What the previous banker's row is called once the bank has moved. It is
  /// deliberately not `player`: a viewer may look at the table, not move money.
  static const String exBankerRole = 'ex-banker';

  /// The code on the banker's screen. The banker's id is included so a code
  /// left open on an old screen cannot move a bank that has already changed
  /// hands - the confirmation reads the live session before it does anything.
  static String payload({required String gameId, required String bankerId}) {
    return jsonEncode(<String, String>{
      'kind': kind,
      'gameId': gameId,
      'bankerId': bankerId,
    });
  }

  /// The hand-over invite in [raw], or null when it is some other code (a join
  /// code, a payment code, a plain game id).
  static HandoverInvite? parse(String raw) {
    final String trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final dynamic decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final Map<String, dynamic> data = decoded.cast<String, dynamic>();
      if (data['kind']?.toString() != kind) return null;
      final String gameId =
          (data['gameId'] ?? data['game_id'] ?? '').toString().trim();
      if (gameId.isEmpty) return null;
      return HandoverInvite(
        gameId: gameId,
        bankerId: (data['bankerId'] ?? data['banker_id'] ?? '').toString(),
      );
    } catch (error) {
      return null;
    }
  }

  /// True for the queued claim rows, so the banker screen's join-request
  /// handling can leave them alone.
  static bool isClaim(Map<String, dynamic> row) =>
      row['role']?.toString() == requestRole;

  /// Queues [invite] for this player, unless they are already at the table.
  ///
  /// Returns the outcome with the message the scanner should show. A claim is
  /// only a request: the banker still has to confirm it, and until they do the
  /// scanner's device keeps polling for the bank row to become theirs.
  static Future<HandoverClaim> claim({
    required HandoverInvite invite,
    required String playerId,
    required String playerName,
  }) async {
    if (playerId.isEmpty) {
      return const HandoverClaim.rejected(
        'This device has no player id. Please restart the app.',
      );
    }
    final SupabaseClient supabase = Supabase.instance.client;

    try {
      final GameSession? session = await GameSession.fetch(invite.gameId);
      if (session != null && session.isEnded) {
        return const HandoverClaim.rejected('That game has already ended.');
      }

      // A code can be stale or not ours at all: nothing queues for a table the
      // backend has never heard of, which would leave the player waiting out
      // the full two minutes for a confirmation nobody can give.
      final List<dynamic> table = await supabase
          .from('players_test')
          .select('id')
          .eq('game_id', invite.gameId)
          .limit(1);
      if (table.isEmpty) {
        return const HandoverClaim.rejected('No game found with that code.');
      }

      // "Somebody who is not already in the game": any seat at this table -
      // banker, player, removed player or an earlier ex-banker - disqualifies.
      final List<dynamic> seats = await supabase
          .from('players_test')
          .select('role')
          .eq('game_id', invite.gameId)
          .eq('player_id', playerId)
          .limit(1);
      if (seats.isNotEmpty) {
        return const HandoverClaim.rejected(
          'You are already at this table. Only a player who is not in the '
          'game can take over the bank.',
        );
      }

      // A rescan replaces the previous claim rather than queueing twice.
      await supabase
          .from('request_test')
          .delete()
          .eq('game_id', invite.gameId)
          .eq('player_id', playerId)
          .eq('role', requestRole);

      await supabase.from('request_test').insert(<String, dynamic>{
        'game_id': invite.gameId,
        'name': playerName,
        'wallet': 0,
        'role': requestRole,
        'player_id': playerId,
      });
      return HandoverClaim.queued(invite.gameId, playerName);
    } catch (error) {
      debugPrint('Could not queue the bank hand-over: $error');
      return const HandoverClaim.rejected(
        'Could not reach the table. Check the connection and scan again.',
      );
    }
  }

  /// The claims waiting for this game's banker to confirm, oldest first.
  static Future<List<HandoverRequest>> pending(String gameId) async {
    if (gameId.isEmpty) return const <HandoverRequest>[];
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('request_test')
          .select()
          .eq('game_id', gameId)
          .eq('role', requestRole);
      return <HandoverRequest>[
        for (final dynamic raw in rows)
          HandoverRequest.fromRow((raw as Map).cast<String, dynamic>()),
      ];
    } catch (error) {
      debugPrint('Could not read bank hand-over claims: $error');
      return const <HandoverRequest>[];
    }
  }

  /// Withdraws one claim (a cancelled wait, or a decline on the banker side).
  static Future<void> withdraw(HandoverRequest request) async {
    try {
      await Supabase.instance.client
          .from('request_test')
          .delete()
          .eq('id', request.id);
    } catch (error) {
      debugPrint('Could not withdraw the hand-over claim: $error');
    }
  }

  /// Does the work the banker confirmed: the bank moves to [newBankerId], the
  /// previous banker gets a view-only row, and every queued claim is cleared.
  ///
  /// The bank row carries the wallet, so it is moved rather than copied: the
  /// balance, the stake and every advance stay exactly where they were. The
  /// ex-banker row starts at zero because the bank's money is not theirs.
  static Future<bool> complete({
    required String gameId,
    required String oldBankerId,
    required String oldBankerName,
    required String newBankerId,
    required String newBankerName,
    String? oldBankerAvatar,
  }) async {
    if (gameId.isEmpty || newBankerId.isEmpty) return false;

    final bool moved = await GameSession.handOverBank(
      gameId: gameId,
      newBankerId: newBankerId,
      newBankerName: newBankerName,
    );
    if (!moved) return false;

    final SupabaseClient supabase = Supabase.instance.client;

    // The old banker must still be able to watch the table and find the game
    // in Your Games; a row of their own is what both of those read.
    if (oldBankerId.isNotEmpty && oldBankerId != newBankerId) {
      try {
        await supabase.from('players_test').insert(<String, dynamic>{
          'game_id': gameId,
          'name': oldBankerName.isEmpty ? 'Ex-banker' : oldBankerName,
          'wallet': 0,
          'role': exBankerRole,
          'player_id': oldBankerId,
          if (oldBankerAvatar != null && oldBankerAvatar.isNotEmpty)
            'avatar': oldBankerAvatar,
        });
      } catch (error) {
        // The bank has already moved, so this must not read as a failure of
        // the hand-over itself; the device can still watch through its old id.
        debugPrint('Could not seat the ex-banker for viewing: $error');
      }
    }

    // Anybody else who scanned this code while it was open is out of luck;
    // their claim must not take the bank a second time.
    try {
      await supabase
          .from('request_test')
          .delete()
          .eq('game_id', gameId)
          .eq('role', requestRole);
    } catch (error) {
      debugPrint('Could not clear the hand-over claims: $error');
    }
    return true;
  }

  /// The bank row of [gameId], when it belongs to [playerId]: the scanner uses
  /// this to learn that the banker confirmed without depending on
  /// `game_sessions`, which older games do not have.
  static Future<bool> holdsBank(String gameId, String playerId) async {
    if (gameId.isEmpty || playerId.isEmpty) return false;
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('players_test')
          .select('id')
          .eq('game_id', gameId)
          .eq('player_id', playerId)
          .eq('role', 'banker')
          .limit(1);
      return rows.isNotEmpty;
    } catch (error) {
      debugPrint('Could not check the bank seat: $error');
      return false;
    }
  }
}

/// What the banker's QR says.
class HandoverInvite {
  const HandoverInvite({required this.gameId, required this.bankerId});

  final String gameId;
  final String bankerId;
}

/// A claim waiting on the banker's answer, as `request_test` holds it.
class HandoverRequest {
  const HandoverRequest({
    required this.id,
    required this.playerId,
    required this.name,
  });

  /// The row's primary key, kept as the backend sent it so a delete can name
  /// exactly that row whatever the project's id type is.
  final Object id;
  final String playerId;
  final String name;

  static HandoverRequest fromRow(Map<String, dynamic> row) {
    return HandoverRequest(
      id: row['id'] ?? '',
      playerId: row['player_id']?.toString() ?? '',
      name: row['name']?.toString() ?? 'A player',
    );
  }
}

/// The scanner's answer: queued for the banker, or refused with a reason.
class HandoverClaim {
  const HandoverClaim.queued(this.gameId, this.name)
      : rejection = null;

  const HandoverClaim.rejected(this.rejection)
      : gameId = '',
        name = '';

  final String gameId;
  final String name;
  final String? rejection;

  bool get queued => rejection == null;
}
