import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mon/services/bank_handover.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:mon/widgets/qr_box.dart';

/// The code a banker shows to hand the bank to somebody who is not in the game.
///
/// The banker's own screen keeps watching `request_test`: the moment a player
/// scans the code and claims it, this dialog closes with that claim so the
/// banker can confirm or decline it. Closing the dialog by hand queues nothing.
class BankHandoverQrDialog extends StatefulWidget {
  const BankHandoverQrDialog({
    super.key,
    required this.gameId,
    required this.bankerId,
  });

  final String gameId;
  final String bankerId;

  @override
  State<BankHandoverQrDialog> createState() => _BankHandoverQrDialogState();
}

class _BankHandoverQrDialogState extends State<BankHandoverQrDialog> {
  Timer? _poll;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _check();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_closing) return;
    final List<HandoverRequest> claims =
        await BankHandover.pending(widget.gameId);
    if (!mounted || _closing || claims.isEmpty) return;
    _closing = true;
    _poll?.cancel();
    Navigator.of(context).pop(claims.first);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFFFF8E1),
      title: const Text('Hand over the bank'),
      content: SizedBox(
        width: 70.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Ask the player who is taking over to scan this code with '
              'Start -> Play -> Scan. They must not be in this game yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: const Color(0xFF33691E)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC5E1A5)),
              ),
              child: QrBox(
                data: BankHandover.payload(
                  gameId: widget.gameId,
                  bankerId: widget.bankerId,
                ),
                size: 52.w,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF689F38),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Waiting for a scan...',
                  style: TextStyle(fontSize: 13.sp, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
