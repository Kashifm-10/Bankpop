import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One player's share of a "collect from every player" card.
///
/// The banker's draw writes a row per payer and the card's receiver; each payer
/// sees the charge waiting on their own screen and confirms it, which pays the
/// receiver directly. Keeping it in the database is what lets a card drawn on
/// the banker's phone settle on everybody else's.
class CardCharge {
  const CardCharge({
    required this.id,
    required this.description,
    required this.receiverId,
    required this.receiverName,
    required this.payerId,
    required this.payerName,
    required this.amount,
    required this.status,
  });

  final int id;
  final String description;
  final String receiverId;
  final String receiverName;
  final String payerId;
  final String payerName;
  final double amount;
  final String status;

  bool get isPaid => status == 'paid';

  static CardCharge? fromMap(Map<String, dynamic> row) {
    final int? id = (row['id'] as num?)?.toInt();
    if (id == null) return null;
    return CardCharge(
      id: id,
      description: row['description']?.toString() ?? 'Card',
      receiverId: row['receiver_id']?.toString() ?? '',
      receiverName: row['receiver_name']?.toString() ?? 'Player',
      payerId: row['payer_id']?.toString() ?? '',
      payerName: row['payer_name']?.toString() ?? 'Player',
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      status: row['status']?.toString() ?? 'pending',
    );
  }
}

/// The rows behind [CardCharge].
///
/// A project that has not run supabase/card_charges.sql cannot share the card
/// between devices; [create] says so and the banker is told to run the script
/// instead of the table quietly doing nothing.
abstract final class CardCharges {
  static const String _table = 'card_charges';

  /// Writes one pending charge for each payer in [payers] (player id -> name)
  /// and returns the ids of the rows it created.
  ///
  /// Null means the rows could not be written - the script has not been run, or
  /// the backend refused - and the banker is told so rather than being left
  /// waiting for money nothing is going to collect.
  static Future<List<int>?> create({
    required String gameId,
    required String description,
    required String receiverId,
    required String receiverName,
    required Map<String, String> payers,
    required double amount,
  }) async {
    if (gameId.isEmpty || payers.isEmpty) return const <int>[];
    final DateTime now = DateTime.now();
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_table)
          .insert(<Map<String, dynamic>>[
        for (final MapEntry<String, String> payer in payers.entries)
          <String, dynamic>{
            'game_id': gameId,
            'description': description,
            'receiver_id': receiverId,
            'receiver_name': receiverName,
            'payer_id': payer.key,
            'payer_name': payer.value,
            'amount': amount,
            'status': 'pending',
            'date': DateFormat('yyyy-MM-dd').format(now),
            'time': DateFormat('HH:mm:ss').format(now),
          },
        ])
          .select('id');
      return <int>[
        for (final dynamic raw in rows)
          if ((raw as Map<String, dynamic>)['id'] is num)
            (raw['id'] as num).toInt(),
      ];
    } catch (error) {
      debugPrint('Could not record the card charges: $error');
      return null;
    }
  }

  /// How many of [ids] have been settled, so a waiting dialog can count the
  /// shares of one card rather than every card the receiver ever collected.
  static Future<int> paidCount(List<int> ids) async {
    if (ids.isEmpty) return 0;
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_table)
          .select('id')
          .inFilter('id', ids)
          .eq('status', 'paid');
      return rows.length;
    } catch (error) {
      return 0;
    }
  }

  /// The shares of one card that one payer has to settle.
  static Future<List<CardCharge>> pendingForGame({
    required String gameId,
    required String payerId,
  }) async {
    if (gameId.isEmpty || payerId.isEmpty) return const <CardCharge>[];
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('game_id', gameId)
          .eq('payer_id', payerId)
          .eq('status', 'pending')
          .order('id');
      final List<CardCharge> pending = <CardCharge>[];
      for (final dynamic raw in rows) {
        final CardCharge? charge = CardCharge.fromMap(raw as Map<String, dynamic>);
        if (charge != null) pending.add(charge);
      }
      return pending;
    } catch (error) {
      return const <CardCharge>[];
    }
  }

  /// The charge this player still has to settle, oldest first, or null.
  static Future<CardCharge?> pendingFor({
    required String gameId,
    required String payerId,
  }) async {
    if (gameId.isEmpty || payerId.isEmpty) return null;
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('game_id', gameId)
          .eq('payer_id', payerId)
          .eq('status', 'pending')
          .order('id')
          .limit(1);
      if (rows.isEmpty) return null;
      return CardCharge.fromMap(rows.first as Map<String, dynamic>);
    } catch (error) {
      // The table has not been created yet: no card can be waiting.
      return null;
    }
  }

  /// Every charge of a card the [receiverId] collects, so the banker's waiting
  /// dialog can count who has paid.
  static Future<List<CardCharge>> forReceiver({
    required String gameId,
    required String receiverId,
  }) async {
    if (gameId.isEmpty || receiverId.isEmpty) return const <CardCharge>[];
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('game_id', gameId)
          .eq('receiver_id', receiverId)
          .order('id');
      final List<CardCharge> charges = <CardCharge>[];
      for (final dynamic raw in rows) {
        final CardCharge? charge =
            CardCharge.fromMap(raw as Map<String, dynamic>);
        if (charge != null) charges.add(charge);
      }
      return charges;
    } catch (error) {
      debugPrint('Could not read the card charges: $error');
      return const <CardCharge>[];
    }
  }

  /// Marks one charge as settled, after the money has moved.
  static Future<bool> markPaid(int id) async {
    try {
      await Supabase.instance.client
          .from(_table)
          .update(<String, dynamic>{'status': 'paid'})
          .eq('id', id);
      return true;
    } catch (error) {
      debugPrint('Could not settle the card charge: $error');
      return false;
    }
  }
}
