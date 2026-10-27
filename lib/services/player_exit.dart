import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a player stands in a game, as `players_test` records it.
///
/// There are only two states, because a seat is either theirs or gone: a player
/// at the table, and a player the banker removed. Quitting the screen is not a
/// standing - the row stays theirs and they come back to it - so there is no
/// "left" and no heartbeat to decide who is watching.
///
/// A project that has not run supabase/players_cleanup.sql has no `status`
/// column; every row then reads [active], which is exactly how the app behaved
/// before, and a kick falls back to writing `role = 'kicked'` instead.
enum PlayerStanding {
  active,
  kicked;

  static PlayerStanding fromRow(Map<String, dynamic> row) {
    if ((row['status'] ?? '').toString() == kicked.name) return kicked;
    // The fallback marker for a project without the status column.
    if (row['role']?.toString() == kicked.name) return kicked;
    return active;
  }

  /// True once the player is no longer at the table.
  bool get isGone => this != active;
}

/// What happened when the banker removed a player.
class KickOutcome {
  const KickOutcome.ok({
    required this.cash,
    required this.cards,
    required this.buildings,
    required this.legacy,
  }) : failure = null;

  const KickOutcome.rejected(this.failure)
      : cash = 0,
        cards = 0,
        buildings = 0,
        legacy = false;

  /// Money moved back to the bank.
  final double cash;

  /// Cards taken off the player and put back into the bank's unsold stock.
  final int cards;

  /// Houses and hotels that came off with those cards.
  final int buildings;

  /// True when the project has no `status` column and the row was marked with
  /// `role = 'kicked'` instead.
  final bool legacy;

  /// Why the kick did not happen, in words the banker can act on.
  final String? failure;

  bool get ok => failure == null;
}

/// What happened when the banker put a removed player back at the table.
class RestoreOutcome {
  const RestoreOutcome.ok({this.legacy = false}) : failure = null;

  const RestoreOutcome.rejected(this.failure) : legacy = false;

  /// True when the project has no `status` column and the row was put back with
  /// `role = 'player'` instead.
  final bool legacy;

  /// Why the player was not restored, in words the banker can act on.
  final String? failure;

  bool get ok => failure == null;
}

/// What a removal is about to take off the table, read before anything moves.
///
/// The banker's confirmation shows these numbers, so the sentence that their
/// buildings go back to the bank is followed by the actual counts rather than a
/// promise.
class KickPreview {
  const KickPreview({
    required this.cash,
    required this.cards,
    required this.houses,
    required this.hotels,
  });

  static const KickPreview empty =
      KickPreview(cash: 0, cards: 0, houses: 0, hotels: 0);

  final double cash;
  final int cards;
  final int houses;
  final int hotels;

  int get buildings => houses + hotels;

  bool get hasBuildings => buildings > 0;

  /// "2 houses and 1 hotel", for the confirmation dialog.
  String get buildingSummary {
    final List<String> parts = <String>[
      if (houses > 0) '$houses house${houses == 1 ? '' : 's'}',
      if (hotels > 0) '$hotels hotel${hotels == 1 ? '' : 's'}',
    ];
    if (parts.isEmpty) return 'none';
    if (parts.length == 1) return parts.first;
    return '${parts.first} and ${parts.last}';
  }
}

/// Removal and restoration for a running game.
///
/// A seat needs no heartbeat: leaving the screen changes nothing, so the only
/// write this file makes to a player's row is the one the banker asks for. A
/// banker who removes a player goes through [kick], which hands back everything
/// they held before the badge is written; [restore] gives them a fresh seat
/// afterwards, with an empty wallet and no cards.
class PlayerExit {
  const PlayerExit._();

  static const String _table = 'players_test';
  static const String _cardsTable = 'player_cards';

  /// What [kick] would move, read without touching anything.
  ///
  /// A project without the buildings columns reports no buildings, which is
  /// exactly what there is to sell on it.
  static Future<KickPreview> preview({
    required String gameId,
    required String playerId,
    required String playerName,
  }) async {
    if (gameId.isEmpty || playerId.isEmpty) return KickPreview.empty;
    try {
      final Map<String, dynamic>? row = await _playerRow(gameId, playerId);
      final List<Map<String, dynamic>> held =
          await _cardsOf(gameId, playerId, playerName);
      int houses = 0;
      int hotels = 0;
      for (final Map<String, dynamic> card in held) {
        houses += (card['houses'] as num?)?.toInt() ?? 0;
        hotels += (card['hotels'] as num?)?.toInt() ?? 0;
      }
      return KickPreview(
        cash: (row?['wallet'] as num?)?.toDouble() ?? 0,
        cards: held.length,
        houses: houses,
        hotels: hotels,
      );
    } catch (error) {
      // Only the summary is missing, never the removal itself.
      debugPrint('Could not read what the removal would move: $error');
      return KickPreview.empty;
    }
  }

  /// Removes [playerId] from the game.
  ///
  /// In order, so a failure leaves the game in a state the banker can retry:
  ///  1. the cash in their wallet goes to the bank,
  ///  2. their cards come off the board - houses and hotels cleared with them -
  ///     and go back into the bank's unsold stock, so the land can be sold
  ///     again,
  ///  3. their pending asks are withdrawn,
  ///  4. and only then is the row stamped `kicked`.
  ///
  /// A player who was already removed is reported as done rather than kicked
  /// twice, so a double tap cannot take the cash twice.
  static Future<KickOutcome> kick({
    required String gameId,
    required String playerId,
    required String playerName,
    required String bankerId,
  }) async {
    if (playerId.isEmpty) {
      return const KickOutcome.rejected('That player is not in this game');
    }

    final Map<String, dynamic>? row = await _playerRow(gameId, playerId);
    if (row == null) {
      return const KickOutcome.rejected('That player is not in this game');
    }
    if (PlayerStanding.fromRow(row) == PlayerStanding.kicked) {
      return const KickOutcome.ok(
          cash: 0, cards: 0, buildings: 0, legacy: false);
    }

    // 1. The cash. The bank takes whatever is left, including nothing.
    final double cash = (row['wallet'] as num?)?.toDouble() ?? 0;
    if (cash > 0 && bankerId.isNotEmpty) {
      final TransferOutcome moved = await WalletTransfer.pay(
        gameId: gameId,
        fromId: playerId,
        fromRole: WalletTransfer.playerRole,
        toId: bankerId,
        toRole: WalletTransfer.bankerRole,
        amount: cash,
      );
      if (!moved.ok) {
        return const KickOutcome.rejected(
          'The cash could not be moved to the bank, so nothing was changed',
        );
      }
      await _recordCash(
        gameId: gameId,
        playerId: playerId,
        playerName: playerName,
        bankerId: bankerId,
        amount: cash,
      );
    }

    // 2. Their property goes back on the market.
    //
    // A removed player must not leave a card behind that nobody can buy, sell
    // or build on - that is property out of the game for good. The houses and
    // hotels standing on it are sold back to the bank with it (the card comes
    // off the board bare), and the card row is removed so the bank can sell the
    // land again exactly as if it had never been bought.
    //
    // No refund is paid for the buildings: the seller has just been removed and
    // their cash is going to the bank in the step above, so a refund would only
    // be handed straight back to the same place. Keeping it out also keeps the
    // ledger honest - one movement, one row.
    int cards = 0;
    int buildings = 0;
    try {
      final List<Map<String, dynamic>> held =
          await _cardsOf(gameId, playerId, playerName);
      for (final Map<String, dynamic> card in held) {
        buildings += (card['houses'] as num?)?.toInt() ?? 0;
        buildings += (card['hotels'] as num?)?.toInt() ?? 0;
      }
      cards = held.length;
      if (held.isNotEmpty) {
        final List<int> indexes = <int>[
          for (final Map<String, dynamic> card in held)
            if ((card['card_index'] as num?) != null)
              (card['card_index'] as num).toInt(),
        ];
        await _releaseCards(gameId, indexes);
      }
    } catch (error) {
      debugPrint('Could not put the cards back on the market: $error');
      return const KickOutcome.rejected(
        'Their cards could not be returned to the board, so the player was not '
        'removed. Try again.',
      );
    }

    // 3. Anything they had asked for is withdrawn; the badge must not sit next
    //    to open requests the banker could still approve.
    await _withdrawAsks(gameId, playerId);

    // 4. The badge.
    final bool legacy = !await _markKicked(gameId, playerId);
    return KickOutcome.ok(
      cash: cash,
      cards: cards,
      buildings: buildings,
      legacy: legacy,
    );
  }

  /// Puts a removed player back at the table.
  ///
  /// This is a fresh seat, not an undo: the cash and the cards they held went
  /// into the game when they were removed - the bank has the money and the land
  /// is on the market, possibly owned by somebody else by now - so nothing is
  /// clawed back. They return with an empty wallet and no cards, and their own
  /// device can rejoin with the same Game ID.
  ///
  /// A player who was never removed is reported as already seated rather than
  /// changed.
  static Future<RestoreOutcome> restore({
    required String gameId,
    required String playerId,
  }) async {
    if (gameId.isEmpty || playerId.isEmpty) {
      return const RestoreOutcome.rejected('That player is not in this game');
    }

    final Map<String, dynamic>? row = await _playerRow(gameId, playerId);
    if (row == null) {
      return const RestoreOutcome.rejected('That player is not in this game');
    }
    if (PlayerStanding.fromRow(row) != PlayerStanding.kicked) {
      return const RestoreOutcome.ok();
    }

    final SupabaseClient supabase = Supabase.instance.client;
    try {
      await supabase
          .from(_table)
          .update(<String, dynamic>{
            'status': PlayerStanding.active.name,
            'wallet': 0,
          })
          .eq('game_id', gameId)
          .eq('player_id', playerId);
      return const RestoreOutcome.ok();
    } on PostgrestException catch (error) {
      if (!_missingColumn(error)) {
        debugPrint('Could not restore the player: ${error.code} '
            '${error.message}');
        return const RestoreOutcome.rejected(
            'Could not put that player back - try again');
      }
      debugPrint('players_test.status is missing - run '
          'supabase/players_cleanup.sql. Using the role marker for now.');
      try {
        await supabase
            .from(_table)
            .update(<String, dynamic>{
              'role': 'player',
              'wallet': 0,
            })
            .eq('game_id', gameId)
            .eq('player_id', playerId);
        return const RestoreOutcome.ok(legacy: true);
      } catch (legacyError) {
        debugPrint('Could not restore the player: $legacyError');
        return const RestoreOutcome.rejected(
            'Could not put that player back - try again');
      }
    } catch (error) {
      debugPrint('Could not restore the player: $error');
      return const RestoreOutcome.rejected(
          'Could not put that player back - try again');
    }
  }

  static Future<Map<String, dynamic>?> _playerRow(
    String gameId,
    String playerId,
  ) async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('game_id', gameId)
          .eq('player_id', playerId)
          .limit(10);
      for (final dynamic raw in rows) {
        final Map<String, dynamic> row = (raw as Map).cast<String, dynamic>();
        final String role = row['role']?.toString() ?? '';
        if (role == 'player' || role == PlayerStanding.kicked.name) return row;
      }
      return null;
    } catch (error) {
      debugPrint('Could not read the player row: $error');
      return null;
    }
  }

  /// The cards this player currently holds.
  ///
  /// One query for the game - a board is a few dozen rows - and the ownership
  /// is decided here, from the row's own id columns and then from `code`, which
  /// every claim writes. Reading `receiver_id` server-side would silently miss
  /// every card on a project where the trigger has not filled it, and a card
  /// that has since been traded away must stay with its new owner.
  static Future<List<Map<String, dynamic>>> _cardsOf(
    String gameId,
    String playerId,
    String playerName,
  ) async {
    final List<dynamic> rows = await Supabase.instance.client
        .from(_cardsTable)
        .select()
        .eq('game_id', gameId);

    return rows.cast<Map<String, dynamic>>().where((Map<String, dynamic> row) {
      final String? owner = _ownerIdOf(row);
      if (owner != null && owner.isNotEmpty) return owner == playerId;
      // No id columns and no code on this project: the deed's name is all
      // there is to go on.
      return row['to']?.toString() == playerName;
    }).toList();
  }

  static String? _ownerIdOf(Map<String, dynamic> row) {
    final String? explicit = row['receiver_id']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final String code = row['code']?.toString() ?? '';
    final List<String> parts = code.split('_');
    if (parts.length < 2 || parts[1].isEmpty) return null;
    return parts[1];
  }

  /// Takes the cards off the removed player and puts them back in the bank's
  /// unsold stock by deleting their rows.
  ///
  /// `player_cards` holds one row per board index and its unique index is what
  /// makes a claim decisive, so a row that still existed - even one whose `to`
  /// read "Bank" - would keep the land out of the game. Deleting it is the only
  /// state in which the card can be bought again, and it takes the houses and
  /// hotels with it.
  static Future<void> _releaseCards(String gameId, List<int> indexes) async {
    await Supabase.instance.client
        .from(_cardsTable)
        .delete()
        .eq('game_id', gameId)
        .inFilter('card_index', indexes);
  }

  /// Clears the asks this player still had open. Best-effort: an ask left
  /// behind cannot move money on its own, because approving it re-checks the
  /// payer's balance.
  static Future<void> _withdrawAsks(String gameId, String playerId) async {
    final SupabaseClient supabase = Supabase.instance.client;
    try {
      await supabase
          .from('request_test')
          .delete()
          .eq('game_id', gameId)
          .eq('player_id', playerId);
    } catch (error) {
      debugPrint('Could not clear the join request: $error');
    }
    try {
      await supabase
          .from('card_requests')
          .delete()
          .eq('game_id', gameId)
          .eq('player_id', playerId)
          .eq('status', 'pending');
    } catch (error) {
      debugPrint('Could not clear the building requests: $error');
    }
    // Deals this player offered, and deals somebody offered them: neither can
    // be settled by a seat that is no longer there.
    for (final String column in <String>['from_id', 'to_id']) {
      try {
        await supabase
            .from('deal_requests')
            .delete()
            .eq('game_id', gameId)
            .eq(column, playerId)
            .eq('status', 'pending');
      } catch (error) {
        debugPrint('Could not clear the open deals by $column: $error');
      }
    }
  }

  /// Stamps the row as removed. Returns false when the `status` column is not
  /// there and the `role` marker was used instead.
  static Future<bool> _markKicked(String gameId, String playerId) async {
    final SupabaseClient supabase = Supabase.instance.client;
    try {
      await supabase
          .from(_table)
          .update(<String, dynamic>{
            'status': PlayerStanding.kicked.name,
            'wallet': 0,
          })
          .eq('game_id', gameId)
          .eq('player_id', playerId);
      return true;
    } on PostgrestException catch (error) {
      if (!_missingColumn(error)) rethrow;
      debugPrint('players_test.status is missing - run '
          'supabase/player_status.sql. Using the role marker for now.');
      await supabase
          .from(_table)
          .update(<String, dynamic>{
            'role': PlayerStanding.kicked.name,
            'wallet': 0,
          })
          .eq('game_id', gameId)
          .eq('player_id', playerId);
      return false;
    }
  }

  /// The history row for the cash the bank took back: the money moved, so the
  /// player's ledger has to show where it went.
  static Future<void> _recordCash({
    required String gameId,
    required String playerId,
    required String playerName,
    required String bankerId,
    required double amount,
  }) async {
    try {
      await Supabase.instance.client
          .from('transactions')
          .insert(<String, dynamic>{
        'game_id': gameId,
        'value': amount,
        'from': playerName,
        'to': 'Bank',
        'code': '${playerId}_$bankerId',
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': DateFormat('HH:mm:ss').format(DateTime.now()),
      });
    } catch (error) {
      // Bookkeeping only: the money has already moved.
      debugPrint('Could not record the removal: $error');
    }
  }

  static bool _missingColumn(PostgrestException error) {
    // 42703 is "undefined column"; PGRST204 is the same fact reported from a
    // stale PostgREST schema cache.
    if (error.code == '42703' || error.code == 'PGRST204') return true;
    return error.message.contains('receiver_id') ||
        error.message.contains('status');
  }
}
