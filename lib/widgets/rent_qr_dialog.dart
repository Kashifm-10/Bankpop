import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:mon/widgets/qr_box.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shows one card's rent as a QR for the payer to scan.
///
/// The amount is worked out before this opens (see `services/rent.dart`), so
/// the payer scans the figure the card actually owes instead of typing one.
/// The dialog watches the owner's wallet and closes itself as soon as the money
/// lands; it returns true when that happens.
Future<bool> showRentQrDialog(
  BuildContext context, {
  required String gameId,
  required String playerId,
  required String playerName,
  required String cardName,
  required String currency,
  required int amount,
}) async {
  final bool? paid = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RentQrDialog(
      gameId: gameId,
      playerId: playerId,
      playerName: playerName,
      cardName: cardName,
      currency: currency,
      amount: amount,
    ),
  );
  return paid == true;
}

class _RentQrDialog extends StatefulWidget {
  const _RentQrDialog({
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.cardName,
    required this.currency,
    required this.amount,
  });

  final String gameId;
  final String playerId;
  final String playerName;
  final String cardName;
  final String currency;
  final int amount;

  @override
  State<_RentQrDialog> createState() => _RentQrDialogState();
}

class _RentQrDialogState extends State<_RentQrDialog> {
  Timer? _poll;

  /// The wallet when the QR opened. Rent is received when it has gone up by at
  /// least the amount, so a payment that was already on its way still counts.
  double? _openedAt;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _openedAt = await _wallet();
    if (!mounted) return;
    _poll = Timer.periodic(const Duration(seconds: 2), (Timer timer) async {
      final double? now = await _wallet();
      if (!mounted) {
        timer.cancel();
        return;
      }
      final double? start = _openedAt;
      if (now == null || start == null) return;
      if (now + 0.001 >= start + widget.amount) {
        timer.cancel();
        Navigator.of(context).pop(true);
      }
    });
  }

  Future<double?> _wallet() async {
    try {
      // The role is part of the row's identity: a device that banks and plays
      // in the same game has two rows under its id, and `maybeSingle` would
      // fail on both - leaving this window waiting for a payment it can never
      // see.
      final Map<String, dynamic>? row = await Supabase.instance.client
          .from('players_test')
          .select('wallet')
          .eq('game_id', widget.gameId)
          .eq('player_id', widget.playerId)
          .eq('role', 'player')
          .maybeSingle();
      return (row?['wallet'] as num?)?.toDouble();
    } catch (error) {
      debugPrint('Could not read the wallet while taking rent: $error');
      return null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String qrData = jsonEncode(<String, dynamic>{
      'playerID': widget.playerId,
      'name': widget.playerName,
      'value': '${widget.amount}',
      'role': 'player',
    });

    return AlertDialog(
      backgroundColor: const Color(0xFFFFF8E1),
      title: Text(
        'Rent for ${widget.cardName}',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            QrBox(
              data: qrData,
              size: 56.w,
              padding: const EdgeInsets.all(8),
            ),
            const SizedBox(height: 8),
            Text(
              BoardCurrencies.format(widget.currency, widget.amount),
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF33691E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.playerName}\'s ${widget.cardName}\n'
              'The payer scans this code. The window closes by itself when '
              'the rent arrives.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, color: Colors.black54),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
