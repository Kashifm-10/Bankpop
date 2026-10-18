import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of `card_requests`: a player asking the banker to put a house or a
/// hotel on a card they own.
///
/// Nothing is charged when the request is made. The banker sees it, approves it,
/// and the money and the building move together at that point - a request is a
/// question, not a purchase.
class CardRequest {
  const CardRequest({
    required this.id,
    required this.gameId,
    required this.cardIndex,
    required this.playerId,
    required this.playerName,
    required this.kind,
    required this.amount,
    this.date = '',
    this.time = '',
  });

  final int id;
  final String gameId;
  final int cardIndex;
  final String playerId;
  final String playerName;

  /// `house` or `hotel`.
  final String kind;
  final double amount;

  /// When the request was written (`yyyy-MM-dd`).
  final String date;

  /// When the request was written (`HH:mm:ss`).
  final String time;

  bool get isHotel => kind == 'hotel';

  factory CardRequest.fromMap(Map<String, dynamic> map) {
    return CardRequest(
      id: (map['id'] as num?)?.toInt() ?? -1,
      gameId: map['game_id']?.toString() ?? '',
      cardIndex: (map['card_index'] as num?)?.toInt() ?? -1,
      playerId: map['player_id']?.toString() ?? '',
      playerName: map['player_name']?.toString() ?? 'Player',
      kind: map['kind']?.toString() ?? 'house',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      date: map['date']?.toString() ?? '',
      time: map['time']?.toString() ?? '',
    );
  }
}

/// What happened when a player asked for a building.
enum AskResult {
  /// The banker will see it on the next poll.
  sent,

  /// This card already has a request waiting to be approved.
  waiting,

  /// The write did not happen: no network, or the table is not deployed.
  failed,
}

/// The outcome of a ask, plus the row to watch: [requestId] is what the waiting
/// dialog polls until the banker settles it.
class AskOutcome {
  const AskOutcome(this.result, {this.requestId});

  final AskResult result;
  final int? requestId;

  bool get sent => result == AskResult.sent && requestId != null;
}

/// What happened when the banker acted on a request.
class BuildingOutcome {
  const BuildingOutcome.ok() : error = null;

  const BuildingOutcome.rejected(this.error);

  /// Why it did not happen, in words the banker can read. Null on success.
  final String? error;

  bool get ok => error == null;
}

/// Reads and settles `card_requests` (created by supabase/buildings.sql).
class CardRequests {
  const CardRequests._();

  static const String _table = 'card_requests';
  static const String _cardsTable = 'player_cards';

  /// Every request still waiting in this game, oldest first.
  static Future<List<CardRequest>> pending(String gameId) async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('game_id', gameId)
          .eq('status', 'pending')
          .order('id');
      return rows
          .map((dynamic row) =>
              CardRequest.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      // The table is optional until supabase/buildings.sql is run.
      debugPrint('Could not read building requests: $error');
      return const <CardRequest>[];
    }
  }

  /// Asks for one more building on [cardIndex]. A card can only have one request
  /// waiting at a time, so a player cannot queue the same house twice.
  static Future<AskOutcome> ask({
    required String gameId,
    required int cardIndex,
    required String playerId,
    required String playerName,
    required String kind,
    required double amount,
  }) async {
    final SupabaseClient supabase = Supabase.instance.client;
    try {
      final List<dynamic> waiting = await supabase
          .from(_table)
          .select('id')
          .eq('game_id', gameId)
          .eq('card_index', cardIndex)
          .eq('status', 'pending')
          .limit(1);
      if (waiting.isNotEmpty) {
        return const AskOutcome(AskResult.waiting);
      }

      final DateTime now = DateTime.now();
      final Map<String, dynamic> row =
          await supabase.from(_table).insert(<String, dynamic>{
        'game_id': gameId,
        'card_index': cardIndex,
        'player_id': playerId,
        'player_name': playerName,
        'kind': kind,
        'amount': amount,
        'status': 'pending',
        'date': DateFormat('yyyy-MM-dd').format(now),
        'time': DateFormat('HH:mm:ss').format(now),
      }).select('id').single();
      return AskOutcome(
        AskResult.sent,
        requestId: (row['id'] as num?)?.toInt(),
      );
    } catch (error) {
      debugPrint('Could not ask for a building: $error');
      return const AskOutcome(AskResult.failed);
    }
  }

  /// `pending`, `approved` or `rejected`; null when it cannot be read.
  static Future<String?> statusOf(int requestId) async {
    try {
      final Map<String, dynamic> row = await Supabase.instance.client
          .from(_table)
          .select('status')
          .eq('id', requestId)
          .single();
      return row['status']?.toString();
    } catch (error) {
      debugPrint('Could not read request $requestId: $error');
      return null;
    }
  }

  /// Takes a request back before the banker has settled it. Nothing was charged,
  /// so the player has only to stop asking.
  static Future<void> cancel(int requestId) async {
    try {
      await Supabase.instance.client
          .from(_table)
          .update(<String, dynamic>{'status': 'cancelled'})
          .eq('id', requestId)
          .eq('status', 'pending');
    } catch (error) {
      debugPrint('Could not cancel request $requestId: $error');
    }
  }

  /// Turns the request down. Nothing was charged, so there is nothing to undo.
  static Future<void> decline(CardRequest request) async {
    try {
      await Supabase.instance.client
          .from(_table)
          .update(<String, dynamic>{'status': 'rejected'})
          .eq('id', request.id)
          .eq('status', 'pending');
    } catch (error) {
      debugPrint('Could not decline request ${request.id}: $error');
    }
  }

  /// Charges the player and puts the building up, in that order.
  ///
  /// The request is claimed first (pending -> approved) so two taps, or a
  /// duplicate dialog, cannot build twice. If the money cannot be taken the
  /// request is rejected instead, and if the card update fails afterwards the
  /// charge is handed straight back.
  static Future<BuildingOutcome> approve(
    CardRequest request, {
    required String bankerId,
  }) async {
    if (bankerId.isEmpty) {
      return const BuildingOutcome.rejected('this device has no bank id');
    }
    final SupabaseClient supabase = Supabase.instance.client;

    try {
      final List<dynamic> claimed = await supabase
          .from(_table)
          .update(<String, dynamic>{'status': 'approved'})
          .eq('id', request.id)
          .eq('status', 'pending')
          .select('id');
      if (claimed.isEmpty) {
        return const BuildingOutcome.rejected('that request was already handled');
      }

      // The card has to exist before any money moves.
      final List<dynamic> cards = await supabase
          .from(_cardsTable)
          .select('id, houses, hotels')
          .eq('game_id', request.gameId)
          .eq('card_index', request.cardIndex)
          .limit(1);
      if (cards.isEmpty) {
        await _close(supabase, request.id, 'rejected');
        return const BuildingOutcome.rejected('that card is not in this game');
      }

      final Map<String, dynamic> card = cards.first as Map<String, dynamic>;
      final int? cardId = (card['id'] as num?)?.toInt();
      final int houses = (card['houses'] as num?)?.toInt() ?? 0;
      final int hotels = (card['hotels'] as num?)?.toInt() ?? 0;

      if (cardId == null) {
        await _close(supabase, request.id, 'rejected');
        return const BuildingOutcome.rejected('that card has no id');
      }

      if (request.isHotel && hotels > 0) {
        await _close(supabase, request.id, 'rejected');
        return const BuildingOutcome.rejected('that card already has a hotel');
      }
      if (!request.isHotel && houses >= 4) {
        await _close(supabase, request.id, 'rejected');
        return const BuildingOutcome.rejected('that card already has four houses');
      }

      final TransferOutcome transfer = await WalletTransfer.pay(
        gameId: request.gameId,
        fromId: request.playerId,
        fromRole: WalletTransfer.playerRole,
        toId: bankerId,
        toRole: WalletTransfer.bankerRole,
        amount: request.amount,
      );
      if (!transfer.ok) {
        await _close(supabase, request.id, 'rejected');
        return BuildingOutcome.rejected(
          transfer.failure == TransferFailure.insufficientFunds
              ? '${request.playerName} does not have enough money'
              : 'the payment failed',
        );
      }

      try {
        await supabase.from(_cardsTable).update(<String, dynamic>{
          if (request.isHotel) 'hotels': 1 else 'houses': houses + 1,
        }).eq('id', cardId);
      } catch (error) {
        // Charged for a building that did not appear: give it back rather than
        // leave the player out of pocket.
        await WalletTransfer.pay(
          gameId: request.gameId,
          fromId: bankerId,
          fromRole: WalletTransfer.bankerRole,
          toId: request.playerId,
          toRole: WalletTransfer.playerRole,
          amount: request.amount,
        );
        await _close(supabase, request.id, 'rejected');
        debugPrint('Could not add the building, refunded: $error');
        return const BuildingOutcome.rejected(
            'the building failed, so the money was returned');
      }

      // The money moved, so the money history has to show it too, exactly as an
      // ordinary payment would. This is bookkeeping: a failure here does not
      // undo a house that is already up.
      try {
        await supabase.from('transactions').insert(<String, dynamic>{
          'game_id': request.gameId,
          'value': request.amount,
          'from': request.playerName,
          'to': 'Bank',
          'code': '${request.playerId}_$bankerId',
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'time': DateFormat('HH:mm:ss').format(DateTime.now()),
        });
      } catch (error) {
        debugPrint('Could not record the building payment: $error');
      }

      return const BuildingOutcome.ok();
    } catch (error) {
      debugPrint('Could not approve request ${request.id}: $error');
      return const BuildingOutcome.rejected('please try again');
    }
  }

  static Future<void> _close(
    SupabaseClient supabase,
    int id,
    String status,
  ) async {
    try {
      await supabase
          .from(_table)
          .update(<String, dynamic>{'status': status})
          .eq('id', id);
    } catch (error) {
      debugPrint('Could not close request $id: $error');
    }
  }
}
