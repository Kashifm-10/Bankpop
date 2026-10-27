import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/bankpop_board_view.dart';

class BankpopBoardPopup extends StatefulWidget {
  final bool isCardMode;
  final String gameId;

  /// The board to draw. Null follows the board the current game plays on
  /// ([BoardCatalog.activeId]), which the game screens set from the session
  /// row; the preview passes the board it is showing.
  final String? boardId;

  /// In cards mode a tap normally closes the board with the chosen space. When
  /// this is set the board stays open and the callback runs instead, so the
  /// caller can open the deed *on top of* the board rather than replacing it.
  final void Function(BankpopSpace space)? onSpaceSelected;

  const BankpopBoardPopup({
    super.key,
    this.isCardMode = false,
    this.gameId = '',
    this.boardId,
    this.onSpaceSelected,
  });

  @override
  State<BankpopBoardPopup> createState() => _BankpopBoardPopupState();
}

class _BankpopBoardPopupState extends State<BankpopBoardPopup> {
  late Future<BankpopBoard> _future;
  late Future<Map<int, CardOwner>> _owners;

  @override
  void initState() {
    super.initState();
    // In a game the board is the game's, and this device already holds a copy
    // of it; before a game exists the caller names the board it is previewing.
    _future = widget.gameId.isEmpty
        ? BoardCatalog.board(widget.boardId)
        : BoardCatalog.boardForGame(widget.gameId);
    _owners = PlayerCards.owners(widget.gameId);
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final double size =
        (screen.width < screen.height ? screen.width : screen.height) * 0.92;

    return Dialog(
      insetPadding: const EdgeInsets.all(6),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<BankpopBoard>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || !snap.hasData) {
              return Center(child: Text('Could not load board: ${snap.error}'));
            }
            return FutureBuilder<Map<int, CardOwner>>(
              future: _owners,
              builder: (context, ownersSnap) {
                if (ownersSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return BankpopBoardView(
                  board: snap.data!,
                  size: size,
                  isCardMode: widget.isCardMode,
                  onSpaceSelected: widget.onSpaceSelected,
                  owners: ownersSnap.data ?? const <int, CardOwner>{},
                );
              },
            );
          },
        ),
      ),
    );
  }
}
