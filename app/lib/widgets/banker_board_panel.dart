import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/bankpop_board_view.dart';
import 'package:mon/widgets/give_card_flow.dart';

/// The game's board, always on the banker's screen.
///
/// It used to be behind a button in the app bar, so checking who owns what - and
/// giving a card - always began with a popup. The board is part of the screen
/// now: a tap opens that card's deed, and with cards mode on the same deed sells
/// it, exactly as the give-card popup did.
class BankerBoardPanel extends StatefulWidget {
  const BankerBoardPanel({
    super.key,
    required this.gameId,
    required this.payOption,
    required this.bankerId,
    this.canGiveCards = true,
    this.alignment = Alignment.center,
  });

  final String gameId;
  final String payOption;
  final String bankerId;

  /// Cards mode: a tap may sell the card. Without it the board is a reference,
  /// and a tap only opens the deed.
  final bool canGiveCards;

  /// Where the square sits in the room it is given.
  ///
  /// A board in a row with the players is put at the top of that row, so it
  /// starts where they start instead of leaving a band of empty paper above it;
  /// on a phone it is centred in a region cut to its own size.
  final Alignment alignment;

  @override
  State<BankerBoardPanel> createState() => _BankerBoardPanelState();
}

class _BankerBoardPanelState extends State<BankerBoardPanel> {
  BankpopBoard? _board;
  Map<int, CardOwner> _owners = const <int, CardOwner>{};
  Timer? _refresh;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Houses, mortgages and sales happen on other devices, so the board reads
    // the table again now and then rather than going stale on the banker.
    _refresh = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final BankpopBoard board = await BoardCatalog.boardForGame(widget.gameId);
      final Map<int, CardOwner> owners =
          widget.gameId.isEmpty
              ? const <int, CardOwner>{}
              : await PlayerCards.owners(widget.gameId);
      if (!mounted) return;
      setState(() {
        _board = board;
        _owners = owners;
        _failed = false;
      });
    } catch (error) {
      debugPrint('Could not read the board for the banker: $error');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _giveCard(BankpopSpace space) async {
    if (widget.bankerId.isEmpty) {
      showMessage(context, 'This device has no player id');
      return;
    }
    await showGiveCardFor(
      context: context,
      gameId: widget.gameId,
      payOption: widget.payOption,
      bankerId: widget.bankerId,
      space: space,
    );
    if (!mounted) return;
    // The card may have just changed hands.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final BankpopBoard? board = _board;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Widget content;
        if (board == null) {
          content = _failed
              ? const Text(
                  'The board could not be read.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                )
              : const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF689F38),
                  ),
                );
        } else {
          // A square board, the largest that fits the room it is given.
          final double size = box.maxWidth < box.maxHeight
              ? box.maxWidth
              : box.maxHeight;
          content = size < 60
              ? const SizedBox.shrink()
              : SizedBox(
                  width: size,
                  height: size,
                  child: BankpopBoardView(
                    board: board,
                    size: size,
                    isCardMode: widget.canGiveCards,
                    onSpaceSelected: widget.canGiveCards ? _giveCard : null,
                    owners: _owners,
                  ),
                );
        }

        // One place the content starts, whatever state it is in: where the
        // caller said - at the top when the board shares a row with the
        // players, so it begins where they begin.
        return Align(alignment: widget.alignment, child: content);
      },
    );
  }
}
