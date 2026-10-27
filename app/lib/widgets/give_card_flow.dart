import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/widgets/bankpop_space_card.dart';
import 'package:mon/widgets/qr_box.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the bank row is called in `player_cards.from`. The roster uses the same
/// word for the banker, so the card history reads "Bank -> Ameen".
const String _bankName = 'Bank';

/// The banker's side of a cards game: pick a property off the board, then sell
/// it.
///
/// ScanPay games sell by QR - the banker shows the code, the player scans it,
/// pays and the card lands in their hand. InstantPay games cannot scan, so the
/// banker assigns the card to a named player instead; the money for those
/// purchases already moved through the ordinary "Pay to Bank" flow.
///
/// The board is part of the banker's screen, so this is asked with the card the
/// banker already tapped. Each step is a layer on top of the last - deed, then
/// QR - so choosing a card never makes the board disappear, and only a completed
/// sale closes the deed.
Future<void> showGiveCardFor({
  required BuildContext context,
  required String gameId,
  required String payOption,
  required String bankerId,
  required BankpopSpace space,
}) async {
  final int? price = space.price;
  if (price == null || price <= 0) {
    showMessage(context, '${space.name} cannot be sold as a card');
    return;
  }
  final String currency = (await BoardCatalog.boardForGame(gameId)).currency;
  if (!context.mounted) return;

  // One property, one owner: never offer a card that has already gone.
  final String? owner = await PlayerCards.ownerOf(gameId, space.index);
  if (!context.mounted) return;
  if (owner != null) {
    showMessage(context, '${space.name} is already owned by $owner');
    return;
  }

  final bool scanPay = payOption == 'ScanPay';
  String? buyer;

  await showBankpopSpaceCard(
    context,
    space,
    currency: currency,
    actionWidget: Builder(
      builder: (BuildContext deedContext) {
        return ElevatedButton.icon(
          onPressed: () async {
            buyer = scanPay
                ? await _showSaleQr(
                    deedContext,
                    gameId: gameId,
                    space: space,
                    bankerId: bankerId,
                    currency: currency,
                  )
                : await _assignToPlayer(
                    context,
                    deedContext,
                    space: space,
                    gameId: gameId,
                    bankerId: bankerId,
                  );
            if (!deedContext.mounted || buyer == null) return;
            // The card has gone to a player: close the deed. The receipt is
            // shown on the screen itself.
            Navigator.of(deedContext).pop();
          },
          // One icon for both halves of the flow: the action is "give this
          // card", whatever the payment option makes it look like.
          icon: Image.asset(
            'assets/Icons/give_card.png',
            width: 22,
            height: 22,
            fit: BoxFit.contain,
          ),
          label: Text(scanPay ? 'Show QR' : 'Assign to player'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF689F38),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      },
    ),
  );

  if (!context.mounted) return;
  if (buyer == null) return;

  await showMessage(
    context,
    '$buyer bought ${space.name} for '
    '${BoardCurrencies.format(currency, price)}.',
    title: 'Card sold',
  );
}

/// The QR the player scans to buy [space]. The payload is read in
/// `QRPayScanner._handleCardPurchase`, which charges the scanner and then claims
/// the card.
///
/// The dialog watches the card while it is open: as soon as the row has an
/// owner it closes itself and hands the buyer's name back, so the banker sees
/// the sale instead of an unexplained dead QR.
Future<String?> _showSaleQr(
  BuildContext context, {
  required String gameId,
  required BankpopSpace space,
  required String bankerId,
  required String currency,
}) {
  final String qrData = jsonEncode(<String, dynamic>{
    'type': 'card',
    'cardIndex': space.index,
    'name': space.name,
    'price': '${space.price}',
    'currency': currency,
    // Who gets the money: this device's banker row, not the bank row's uuid.
    'playerID': bankerId,
    'role': 'banker',
  });

  return showDialog<String>(
    context: context,
    builder: (_) => _SaleQrDialog(
      gameId: gameId,
      cardIndex: space.index,
      space: space,
      currency: currency,
      qrData: qrData,
    ),
  );
}

/// The banker's "sell this card" QR, which closes when the card is bought.
class _SaleQrDialog extends StatefulWidget {
  const _SaleQrDialog({
    required this.gameId,
    required this.cardIndex,
    required this.space,
    required this.currency,
    required this.qrData,
  });

  final String gameId;
  final int cardIndex;
  final BankpopSpace space;
  final String currency;
  final String qrData;

  @override
  State<_SaleQrDialog> createState() => _SaleQrDialogState();
}

class _SaleQrDialogState extends State<_SaleQrDialog> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 2), (Timer timer) async {
      final String? owner = await PlayerCards.ownerOf(
        widget.gameId,
        widget.cardIndex,
      );
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (owner == null || owner == _bankName) return;
      timer.cancel();
      Navigator.of(context).pop(owner);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Sell ${widget.space.name}',
        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 70.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            QrBox(
              data: widget.qrData,
              size: 55.w,
              padding: const EdgeInsets.all(8),
            ),
            SizedBox(height: 1.5.h),
            Text(
              BoardCurrencies.format(widget.currency, widget.space.price ?? 0),
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 0.5.h),
            Text(
              'The player who scans this pays the bank and receives the card. '
              'This window closes on its own once it is bought.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: Colors.black54),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// InstantPay: hand [space] to one of the players already in the game.
///
/// Returns the player's name once the card has been given, or null if the
/// banker backed out or it failed (the reason is shown here).
Future<String?> _assignToPlayer(
  BuildContext pageContext,
  BuildContext deedContext, {
  required BankpopSpace space,
  required String gameId,
  required String bankerId,
}) async {
  final List<Map<String, dynamic>> roster;
  try {
    final List<dynamic> rows = await Supabase.instance.client
        .from('players_test')
        .select()
        .eq('game_id', gameId)
        .eq('role', 'player');
    // A player who was removed (or who quit) is not at the table, so the card
    // would go to a seat nobody is sitting in. The removed row stays in the
    // roster for its badge, which is why it is filtered here.
    roster = rows
        .cast<Map<String, dynamic>>()
        .where((Map<String, dynamic> row) =>
            PlayerStanding.fromRow(row) == PlayerStanding.active)
        .toList();
  } catch (error) {
    debugPrint('Could not load players for a card: $error');
    if (pageContext.mounted) {
      showMessage(pageContext, 'Could not load the players');
    }
    return null;
  }
  if (!deedContext.mounted) return null;

  if (roster.isEmpty) {
    showMessage(pageContext, 'No players have joined yet');
    return null;
  }

  final Map<String, dynamic>? chosen = await showDialog<Map<String, dynamic>>(
    context: deedContext,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(
        'Give ${space.name} to',
        style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 70.w,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: roster.length,
          itemBuilder: (BuildContext context, int index) {
            final Map<String, dynamic> row = roster[index];
            final String name = _displayName(row['name']?.toString());
            return ListTile(
              title: Text(name),
              onTap: () => Navigator.of(dialogContext).pop(row),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (chosen == null) return null;

  final String playerId = chosen['player_id']?.toString() ?? '';
  final String playerName = _displayName(chosen['name']?.toString());
  if (playerId.isEmpty) {
    if (pageContext.mounted) {
      showMessage(pageContext, 'That player has no id in this game');
    }
    return null;
  }

  final ClaimResult claim = await PlayerCards.claim(
    gameId: gameId,
    cardIndex: space.index,
    fromName: _bankName,
    toName: playerName,
    payerId: bankerId,
    receiverId: playerId,
  );
  if (!pageContext.mounted) return null;

  if (claim.alreadySold) {
    showMessage(pageContext, '${space.name} has already been sold');
    return null;
  }
  if (!claim.ok) {
    showMessage(pageContext, 'Could not give the card. Please try again.');
    return null;
  }

  return playerName;
}

/// "ameen" -> "Ameen"; tolerates the empty names a roster row can carry.
String _displayName(String? value) {
  if (value == null || value.isEmpty) return 'Player';
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
