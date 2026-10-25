import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/widgets/bankpop_board_popup.dart';
import 'package:mon/widgets/bankpop_space_card.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
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
/// The caller has already checked that the game is in cards mode; this only asks
/// *which* card and *how*. Each step is a layer on top of the last - board, then
/// deed, then QR - so choosing a card never makes the board disappear.
Future<void> showGiveCardFlow({
  required BuildContext context,
  required String gameId,
  required String payOption,
  required String bankerId,
}) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext boardContext) => BankpopBoardPopup(
      isCardMode: true,
      gameId: gameId,
      onSpaceSelected: (BankpopSpace space) => _sellFromBoard(
        context,
        boardContext: boardContext,
        space: space,
        gameId: gameId,
        payOption: payOption,
        bankerId: bankerId,
      ),
    ),
  );
}

/// Opens the deed over the board, and the QR (or the player list) over the deed.
/// Only a completed sale closes the whole stack.
Future<void> _sellFromBoard(
  BuildContext pageContext, {
  required BuildContext boardContext,
  required BankpopSpace space,
  required String gameId,
  required String payOption,
  required String bankerId,
}) async {
  final int? price = space.price;
  if (price == null || price <= 0) {
    showMessage(boardContext, '${space.name} cannot be sold as a card');
    return;
  }

  // One property, one owner: never offer a card that has already gone.
  final String? owner = await PlayerCards.ownerOf(gameId, space.index);
  if (!boardContext.mounted) return;
  if (owner != null) {
    showMessage(boardContext, '${space.name} is already owned by $owner');
    return;
  }

  final bool scanPay = payOption == 'ScanPay';
  String? buyer;

  await showBankpopSpaceCard(
    boardContext,
    space,
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
                  )
                : await _assignToPlayer(
                    pageContext,
                    deedContext,
                    space: space,
                    gameId: gameId,
                    bankerId: bankerId,
                  );
            if (!deedContext.mounted || buyer == null) return;
            // The card has gone to a player: close the deed, then the board
            // underneath it. The receipt is shown on the screen itself.
            Navigator.of(deedContext).pop();
          },
          icon: Icon(scanPay ? Icons.qr_code_2 : Icons.person_add_alt_1,
              size: 18),
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

  if (!boardContext.mounted) return;
  if (buyer == null) return;

  Navigator.of(boardContext).pop(); // close the board
  if (!pageContext.mounted) return;
  await showMessage(
    pageContext,
    '$buyer bought ${space.name} for \u00a3$price.',
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
}) {
  final String qrData = jsonEncode(<String, dynamic>{
    'type': 'card',
    'cardIndex': space.index,
    'name': space.name,
    'price': '${space.price}',
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
    required this.qrData,
  });

  final String gameId;
  final int cardIndex;
  final BankpopSpace space;
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
            QrImageView(
              data: widget.qrData,
              version: QrVersions.auto,
              size: 55.w,
              gapless: false,
              padding: const EdgeInsets.all(8),
            ),
            SizedBox(height: 1.5.h),
            Text(
              '\u00a3${widget.space.price}',
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
