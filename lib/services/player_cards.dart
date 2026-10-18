import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of `player_cards`: a property that changed hands in this game.
///
/// The table stores the board index rather than the name, so the name is looked
/// up from the bundled board (`PlayerCards.spaces()`), not from the row.
class PlayerCard {
  const PlayerCard({
    required this.id,
    required this.cardIndex,
    required this.from,
    required this.to,
    required this.date,
    required this.time,
  });

  final int? id;
  final int cardIndex;
  final String from;
  final String to;
  final String date;
  final String time;

  DateTime? get acquiredAt => DateTime.tryParse('$date $time'.trim());

  factory PlayerCard.fromMap(Map<String, dynamic> map) {
    return PlayerCard(
      id: (map['id'] as num?)?.toInt(),
      cardIndex: (map['card_index'] as num?)?.toInt() ?? -1,
      from: map['from']?.toString() ?? '',
      to: map['to']?.toString() ?? '',
      date: map['date']?.toString() ?? '',
      time: map['time']?.toString() ?? '',
    );
  }
}

/// What happened when a card was claimed for a player.
class ClaimResult {
  const ClaimResult.ok(this.rowId)
      : alreadySold = false,
        failed = false;

  const ClaimResult.alreadySold()
      : rowId = null,
        alreadySold = true,
        failed = false;

  const ClaimResult.failed()
      : rowId = null,
        alreadySold = false,
        failed = true;

  /// `player_cards.id` of the row just created, so a failed payment can undo it.
  final int? rowId;

  /// Another device recorded this board index first.
  final bool alreadySold;

  /// The insert did not happen for some other reason (network, permissions).
  final bool failed;

  bool get ok => !alreadySold && !failed;
}

/// Reads and writes `player_cards` (created by supabase/player_cards.sql).
///
/// A card is claimed *before* the money moves. The card, not the cash, is the
/// thing two devices can collide over, and a claim can always be released while
/// a refund cannot be guaranteed. See [claim] and [release].
class PlayerCards {
  const PlayerCards._();

  static const String _table = 'player_cards';

  /// Board index -> space, for turning a stored `card_index` back into a name
  /// and a colour. Loaded once per app run; an empty map if the asset is
  /// unreadable, in which case callers fall back to "Card #n".
  static Map<int, BankpopSpace>? _spaces;

  static Future<Map<int, BankpopSpace>> spaces() async {
    final Map<int, BankpopSpace>? cached = _spaces;
    if (cached != null) return cached;
    try {
      final BankpopBoard board =
          await BankpopBoard.loadFromAsset('assets/JSON/bankpop.json');
      final Map<int, BankpopSpace> map = <int, BankpopSpace>{
        for (final BankpopSpace space in board.spaces) space.index: space,
      };
      _spaces = map;
      return map;
    } catch (error) {
      debugPrint('Could not load the board for card names: $error');
      _spaces = const <int, BankpopSpace>{};
      return _spaces!;
    }
  }

  /// Name of whoever already holds this board index in this game, or null while
  /// it is still unsold.
  static Future<String?> ownerOf(String gameId, int cardIndex) async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_table)
          .select('to')
          .eq('game_id', gameId)
          .eq('card_index', cardIndex)
          .limit(1);
      if (rows.isEmpty) return null;
      return rows.first['to']?.toString();
    } catch (error) {
      // Treat an unreachable backend as "not known to be sold": the claim below
      // still has the last word, and the unique index (see the SQL file) is what
      // makes it decisive.
      debugPrint('Could not check card ownership: $error');
      return null;
    }
  }

  /// Records that a card went from [payerId] to [receiverId].
  ///
  /// `payer_id`/`receiver_id` are filled by the table's trigger from `code`, so
  /// only the pair itself is written here.
  static Future<ClaimResult> claim({
    required String gameId,
    required int cardIndex,
    required String fromName,
    required String toName,
    required String payerId,
    required String receiverId,
  }) async {
    final DateTime now = DateTime.now();
    try {
      final Map<String, dynamic> row =
          await Supabase.instance.client.from(_table).insert(<String, dynamic>{
        'game_id': gameId,
        'card_index': cardIndex,
        'from': fromName,
        'to': toName,
        'code': '${payerId}_$receiverId',
        'date': DateFormat('yyyy-MM-dd').format(now),
        'time': DateFormat('HH:mm:ss').format(now),
      }).select('id').single();
      return ClaimResult.ok((row['id'] as num?)?.toInt());
    } on PostgrestException catch (error) {
      // 23505 is the unique index on (game_id, card_index): the other device won
      // the race, and this one must not charge its player.
      if (error.code == '23505') return const ClaimResult.alreadySold();
      debugPrint('Could not record card: ${error.code} ${error.message}');
      return const ClaimResult.failed();
    } catch (error) {
      debugPrint('Could not record card: $error');
      return const ClaimResult.failed();
    }
  }

  /// Undoes a [claim] whose payment did not go through. Deleting a row we just
  /// created cannot fail for lack of funds, which is why the claim is taken
  /// first and the money moved second.
  static Future<void> release(int? rowId) async {
    if (rowId == null) return;
    try {
      await Supabase.instance.client.from(_table).delete().eq('id', rowId);
    } catch (error) {
      // Nothing else to try: report it so a stuck card can be found later.
      debugPrint('Could not release card row $rowId: $error');
    }
  }

  /// This player's cards in this game, newest first.
  ///
  /// The indexed filter matches the two id columns the trigger fills. Until the
  /// trigger is deployed those columns are null, so an undefined-column reply
  /// falls back to matching the ids inside `code` - the same arrangement the
  /// transaction history uses.
  static Future<List<PlayerCard>> forPlayer({
    required String gameId,
    required String playerId,
  }) async {
    if (playerId.isEmpty || playerId == '-') return const <PlayerCard>[];

    final SupabaseClient supabase = Supabase.instance.client;
    List<dynamic> rows;
    try {
      rows = await supabase
          .from(_table)
          .select()
          .eq('game_id', gameId)
          .or('receiver_id.eq.$playerId,payer_id.eq.$playerId')
          .order('date', ascending: false)
          .order('time', ascending: false)
          .limit(200);
    } on PostgrestException catch (error) {
      if (!_columnsMissing(error)) rethrow;
      debugPrint('player_cards.payer_id/receiver_id are empty - run '
          'supabase/player_cards.sql. Using the code filter until then.');
      rows = await supabase
          .from(_table)
          .select()
          .eq('game_id', gameId)
          .like('code', '%$playerId%')
          .order('date', ascending: false)
          .order('time', ascending: false)
          .limit(200);
    }

    return rows
        .map((dynamic row) =>
            PlayerCard.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  static bool _columnsMissing(PostgrestException error) {
    // 42703 is "undefined column"; PGRST204 is the same fact reported from a
    // stale PostgREST schema cache.
    if (error.code == '42703' || error.code == 'PGRST204') return true;
    return error.message.contains('payer_id') ||
        error.message.contains('receiver_id');
  }
}
