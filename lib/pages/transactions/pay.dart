import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QRPayScanner extends StatefulWidget {
  final String gameId;

  /// Opened from "Buy Card": the scanner reads the same payloads, so this only
  /// changes what the screen says it is for.
  final bool isCardMode;

  const QRPayScanner({
    super.key,
    required this.gameId,
    this.isCardMode = false,
  });

  @override
  State<QRPayScanner> createState() => _QRPayScannerState();
}

class _QRPayScannerState extends State<QRPayScanner> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCardMode ? "Scan Card QR" : "Scan QR to Pay"),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          if (widget.isCardMode)
            Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Scan the bank's property card QR to buy it",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14.sp),
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

      // A property card for sale, rather than a plain payment.
      if (data['type'] == 'card') {
        await _handleCardPurchase(data);
        return;
      }

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

  /// Buys the property a card QR from the bank is offering.
  ///
  /// The card is claimed before the money moves. The card is the thing two
  /// players can collide over, and a claim that was just written can always be
  /// released if the payment fails - a refund cannot be guaranteed.
  Future<void> _handleCardPurchase(Map<String, dynamic> data) async {
    // Held rather than re-read from `context`: this screen pops itself midway
    // through, and a captured navigator stays valid after that.
    final NavigatorState navigator = Navigator.of(context);
    final int? cardIndex = data['cardIndex'] is num
        ? (data['cardIndex'] as num).toInt()
        : int.tryParse('${data['cardIndex']}');
    final String cardName = (data['name'] ?? 'Card').toString();
    final double price = double.tryParse('${data['price']}') ?? 0;
    final String bankerId = (data['playerID'] ?? '').toString();

    if (cardIndex == null || bankerId.isEmpty || price <= 0) {
      _showError('This card QR is not valid');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final String payerId = prefs.getString('playerID') ?? '';
    final String payerName = prefs.getString('display_name') ??
        prefs.getString('profile_name') ??
        'Player';
    if (payerId.isEmpty) {
      _showError('This device has no player id');
      return;
    }

    // Affordability first: there is no point reserving a card, or asking the
    // player to confirm, when the payment can only fail.
    final double? balance = await _walletBalance(payerId);
    if (!mounted) return;
    if (balance != null && balance < price) {
      navigator.pop();
      notify('failed', detail: 'Insufficient funds');
      return;
    }

    // Do not charge for a property the bank has already sold.
    final String? owner = await PlayerCards.ownerOf(widget.gameId, cardIndex);
    if (!mounted) return;
    if (owner != null) {
      _showError('$cardName is already owned by $owner');
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: const Text('Buy Card'),
        content: Text(
          'Buy $cardName for £$price?\nThe money goes to the bank.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      navigator.pop(); // Back to the wallet
      return;
    }

    final ClaimResult claim = await PlayerCards.claim(
      gameId: widget.gameId,
      cardIndex: cardIndex,
      fromName: 'Bank',
      toName: payerName,
      // The bank issued it, the scanning player received it.
      payerId: bankerId,
      receiverId: payerId,
    );
    if (!mounted) return;
    if (claim.alreadySold) {
      _showError('$cardName has just been sold to another player');
      return;
    }
    if (!claim.ok) {
      _showError('Could not reserve the card. Please try again.');
      return;
    }

    final TransferOutcome transfer = await WalletTransfer.pay(
      gameId: widget.gameId,
      fromId: payerId,
      fromRole: WalletTransfer.playerRole,
      toId: bankerId,
      toRole: WalletTransfer.bankerRole,
      amount: price,
    );
    if (!mounted) return;

    if (!transfer.ok) {
      // The player was never charged, so hand the card back to the bank.
      await PlayerCards.release(claim.rowId);
      if (!mounted) return;
      navigator.pop(); // Back to the wallet
      notify(
        'failed',
        detail: transfer.failure == TransferFailure.insufficientFunds
            ? 'Insufficient funds'
            : 'Please try again',
      );
      return;
    }

    // The card row is the card history; this keeps the money history too, the
    // way an ordinary ScanPay payment does.
    try {
      await Supabase.instance.client.from('transactions').insert({
        'game_id': widget.gameId,
        'value': price,
        'from': payerName,
        'to': 'Bank',
        'code': '${payerId}_$bankerId',
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': DateFormat('HH:mm:ss').format(DateTime.now()),
      });
    } catch (error) {
      debugPrint('Could not write the card purchase to transactions: $error');
    }
    if (!mounted) return;

    // The scanner is about to leave the tree; show the receipt through the
    // navigator that owns the route instead of the dying scanner context.
    navigator.pop();
    await showDialog<void>(
      context: navigator.context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: const Text('Card purchased'),
        content: Text('You now own $cardName.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// This player's wallet, or null when it cannot be read - in which case the
  /// atomic transfer still refuses a payment they cannot afford.
  Future<double?> _walletBalance(String playerId) async {
    try {
      final Map<String, dynamic>? row = await Supabase.instance.client
          .from('players_test')
          .select('wallet')
          .eq('game_id', widget.gameId)
          .eq('player_id', playerId)
          .eq('role', 'player')
          .maybeSingle();
      return (row?['wallet'] as num?)?.toDouble();
    } catch (error) {
      debugPrint('Could not read the wallet before a card purchase: $error');
      return null;
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
    if (!context.mounted) return;
    Navigator.pop(context); // Close the scanner
    if (!context.mounted) return;
    showMessage(context, message);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
