import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
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
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan QR to Pay")),
      body: QRView(
        key: qrKey,
        onQRViewCreated: _onQRViewCreated,
        overlay: QrScannerOverlayShape(
          borderColor: Colors.red,
          borderWidth: 10,
          borderLength: 30,
          borderRadius: 10,
          cutOutSize: 250.w,
        ),
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;

    controller.scannedDataStream.listen((scanData) async {
      if (_scanned) return;
      _scanned = true;

      controller.pauseCamera();

      try {
        final Map<String, dynamic> data = jsonDecode(scanData.code ?? '');

        final playerID = data['playerID'];
        final value = data['value'];
        final name = data['name'];

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

        // Step 2: Update receiver's wallet
        final receiverResponse = await Supabase.instance.client
            .from('players_test')
            .select('wallet, name')
            .eq('game_id', widget.gameId)
            .eq('player_id', playerID)
            .maybeSingle();

        if (receiverResponse != null && receiverResponse['wallet'] != null) {
          double receiverWallet =
              (receiverResponse['wallet'] as num).toDouble();
          double newReceiverWallet = receiverWallet + addedValue;

          await Supabase.instance.client
              .from('players_test')
              .update({'wallet': newReceiverWallet})
              .eq('game_id', widget.gameId)
              .eq('player_id', playerID);
        }

        // Step 3: Deduct from payer's wallet
        double newPayerWallet = payerWallet - addedValue;

        await Supabase.instance.client
            .from('players_test')
            .update({'wallet': newPayerWallet})
            .eq('game_id', widget.gameId)
            .eq('player_id', payerPlayerID);

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
    });
  }

  void notify(String message) {
    showDialog(
      barrierDismissible: false,
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        // Schedule dialog auto-close
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Center(
            child: SizedBox(
              width: 60.w, // Responsive width
              height: 50.w, // Responsive height
              child: Column(
                children: [
                  Lottie.asset(
                    message == 'paid'
                        ? 'assets/lottie/paid.json'
                        : message == 'failed'
                            ? 'assets/lottie/failed.json'
                            : message == 'received'
                                ? 'assets/lottie/received.json'
                                : 'assets/lottie/paid.json',
                    repeat: false,
                  ),
                  Text(
                    "Payment Failed\nInsufficient Balance",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
                    textAlign: TextAlign.center,
                  )
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
    controller?.dispose();
    super.dispose();
  }
}
