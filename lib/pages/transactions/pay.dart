import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QRPayScanner extends StatefulWidget {
  final String gameId;
  const QRPayScanner({super.key, required this.gameId});

  @override
  State<QRPayScanner> createState() => _QRPayScannerState();
}

class _QRPayScannerState extends State<QRPayScanner> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan QR to Pay")),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // The scan frame the old scanner drew. MobileScanner has no overlay
          // API, so it is a plain red border over the same 250.w window.
          Center(
            child: IgnorePointer(
              child: Container(
                width: 250.w,
                height: 250.w,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 10),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final String? scannedCode = barcodes.first.rawValue;
    if (scannedCode == null || scannedCode.isEmpty) return;

    _scanned = true;
    // Stop the camera while the confirmation dialog is up.
    await _controller.stop();

    try {
      final Map<String, dynamic> data = jsonDecode(scannedCode);

      final playerID = data['playerID'];
      final value = data['value'];
      final name = data['name'];
      final receiverRole = data['role']?.toString() ?? 'player';

      if (playerID == null || value == null) {
        _showError('Invalid QR Code data');
        return;
      }

      final confirmed =
          await _showConfirmDialog(context, name, value.toString());

      if (!confirmed) {
        Navigator.pop(context);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final payerPlayerID = prefs.getString('playerID') ?? 'UnknownPlayer';

      // Step 1: Check payer's balance first
      final payerResponse = await Supabase.instance.client
          .from('players_test')
          .select('wallet, name')
          .eq('game_id', widget.gameId)
          .eq('role', 'player')
          .eq('player_id', payerPlayerID)
          .maybeSingle();

      double addedValue = double.tryParse(value.toString()) ?? 0;

      if (payerResponse == null || payerResponse['wallet'] == null) {
        _showError('Payer not found');
        return;
      }

      double payerWallet = (payerResponse['wallet'] as num).toDouble();

      if (payerWallet < addedValue) {
        if (context.mounted) {
          Navigator.pop(context); // Close scanner
          notify('failed');
          /*   ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Insufficient balance')),
            ); */
        }
        return;
      }

      // Step 2: read the payee, whose name goes into the history row.
      final receiverResponse = await Supabase.instance.client
          .from('players_test')
          .select('wallet, name')
          .eq('game_id', widget.gameId)
          .eq('player_id', playerID)
          .maybeSingle();

      // Step 3: move the money. One atomic call: the database locks both rows,
      // re-checks the funds and writes both wallets, so a payment that lands
      // while this one is in flight can no longer overwrite it. A payee that
      // does not exist now fails instead of quietly taking the payer's money.
      final TransferOutcome transfer = await WalletTransfer.pay(
        gameId: widget.gameId,
        fromId: payerPlayerID,
        fromRole: WalletTransfer.playerRole,
        toId: playerID.toString(),
        toRole: receiverRole,
        amount: addedValue,
      );

      if (!transfer.ok) {
        if (context.mounted) {
          Navigator.pop(context); // Close scanner
          notify(
            'failed',
            detail: transfer.failure == TransferFailure.insufficientFunds
                ? 'Insufficient balance'
                : transfer.failure == TransferFailure.notFound
                    ? 'Player not found in this game'
                    : 'Please try again',
          );
        }
        return;
      }

      if (context.mounted) {
        Navigator.pop(context);
        await Supabase.instance.client.from('transactions').insert({
          'game_id': widget.gameId,
          'value': double.parse(value),
          'from': payerResponse['name'],
          'to': receiverResponse!['name'],
          'code': "${payerPlayerID}_$playerID",
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'time': DateFormat('HH:mm:ss').format(DateTime.now()),
        });
        //   notify('paid'); // close scanner
        /*  ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment of $value completed.')),
          ); */
      }
    } catch (e) {
      _showError('Failed to process QR data');
    }
  }

  void notify(String message, {String? detail}) {
    final title = message == 'failed' ? 'Payment Failed' : 'Payment Successful';
    final body = detail ?? (message == 'failed' ? 'Please try again' : '');

    showDialog(
      barrierDismissible: false,
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Center(
            child: SizedBox(
              width: 60.w,
              height: 50.w,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Lottie.asset(
                    message == 'failed'
                        ? 'assets/lottie/failed.json'
                        : 'assets/lottie/paid.json',
                    repeat: false,
                  ),
                  Text(
                    body.isEmpty ? title : "$title\n$body",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showConfirmDialog(
      BuildContext context, String playerID, String value) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Color(0xFFFFF8E1),
            title: const Text('Confirm Payment'),
            content: Text('Pay $value to Player ID: $playerID?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('No')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Yes')),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String message) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
