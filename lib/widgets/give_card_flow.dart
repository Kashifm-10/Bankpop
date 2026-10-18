import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
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
/// The caller hasalready checked that the game is in cards mode; this only asks
/// *which* card and *how*.
Future<void> showGiveCardFlow({
  required BuildContext context,
  required String gameId,
  required String payOption,
  required String bankerId,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  // Say what the next tap means, because the board looks identical to the one on
  // the home screen where a tap opens the deed.
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Tap a property to sell it as a card'),
      duration: Duration(seconds: 2),
    ),
  );

  final BankpopSpace? space = await showDialog<BankpopSpace>(
    context: context,
    builder: (_) => const BankpopBoardPopup(isCardMode: true),
  );
  if (space == null || !context.mounted) return;

  final int? price = space.price;
  if (price == null || price <= 0) {
    messenger.showSnackBar(
      SnackBar(content: Text('${space.name} cannot be sold as a card')),
    );
    return;
  }

  // One property, one owner: never offer a card that has already gone.
  final String? owner = await PlayerCards.ownerOf(gameId, space.index);
  if (!context.mounted) return;
  if (owner != null) {
    messenger.showSnackBar(
      SnackBar(content: Text('${space.name} is already owned by $owner')),
    );
    return;
  }

  final bool scanPay = payOption == 'ScanPay';
  await showBankpopSpaceCard(
    context,
    space,
    actionWidget: Builder(
      builder: (BuildContext deedContext) {
        return ElevatedButton.icon(
          onPressed: () {
            // Close the deed first so the QR / player list is not stacked on
            // top of it.
            Navigator.of(deedContext).pop();
            if (scanPay) {
              _showSaleQr(context, space: space, bankerId: bankerId);
            } else {
              _assignToPlayer(context,
                  space: space, gameId: gameId, bankerId: bankerId);
            }
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
}

/// The QR the player scans to buy [space]. The payload is read in
/// `QRPayScanner._handleCardPurchase`, which charges the scanner and then claims
/// the card.
void _showSaleQr(
  BuildContext context, {
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

  showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      backgroundColor: Colors.yellow.shade50,
      title: Text(
        'Sell ${space.name}',
        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 70.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 55.w,
              gapless: false,
            ),
            SizedBox(height: 1.5.h),
            Text(
              '£${space.price}',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 0.5.h),
            Text(
              'The player who scans this pays the bank and receives the card.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: Colors.black54),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// InstantPay: hand [space] to one of the players already in the game.
Future<void> _assignToPlayer(
  BuildContext context, {
  required BankpopSpace space,
  required String gameId,
  required String bankerId,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final List<Map<String, dynamic>> roster;
  try {
    final List<dynamic> rows = await Supabase.instance.client
        .from('players_test')
        .select('name, player_id')
        .eq('game_id', gameId)
        .eq('role', 'player');
    roster = rows.cast<Map<String, dynamic>>();
  } catch (error) {
    debugPrint('Could not load players for a card: $error');
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not load the players')),
    );
    return;
  }
  if (!context.mounted) return;

  if (roster.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No players have joined yet')),
    );
    return;
  }

  final Map<String, dynamic>? chosen = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFFFFF8E1),
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
  if (chosen == null || !context.mounted) return;

  final String playerId = chosen['player_id']?.toString() ?? '';
  final String playerName = _displayName(chosen['name']?.toString());
  if (playerId.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That player has no id in this game')),
    );
    return;
  }

  final ClaimResult claim = await PlayerCards.claim(
    gameId: gameId,
    cardIndex: space.index,
    fromName: _bankName,
    toName: playerName,
    payerId: bankerId,
    receiverId: playerId,
  );
  if (!context.mounted) return;

  if (claim.alreadySold) {
    messenger.showSnackBar(
      SnackBar(content: Text('${space.name} has already been sold')),
    );
    return;
  }
  if (!claim.ok) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not give the card. Please try again.')),
    );
    return;
  }

  messenger.showSnackBar(
    SnackBar(content: Text('$playerName now owns ${space.name}')),
  );
}

/// "ameen" -> "Ameen"; tolerates the empty names a roster row can carry.
String _displayName(String? value) {
  if (value == null || value.isEmpty) return 'Player';
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
