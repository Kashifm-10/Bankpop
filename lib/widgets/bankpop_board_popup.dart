import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/widgets/bankpop_deck_sheet.dart';
import 'package:mon/widgets/bankpop_space_card.dart';
import 'package:mon/widgets/bankpop_tile.dart';

class BankpopBoardPopup extends StatefulWidget {
  /// Cards game: tapping a property closes the board and hands that space back
  /// to the caller instead of opening its deed.
  ///
  /// Read it with `showDialog<BankpopSpace>(...)`: the board pops with the
  /// tapped space, so the caller decides what selling it means (a ScanPay QR, or
  /// an InstantPay assignment) without this widget knowing about games.
  final bool isCardMode;

  const BankpopBoardPopup({super.key, this.isCardMode = false});

  @override
  State<BankpopBoardPopup> createState() => _BankpopBoardPopupState();
}

class _BankpopBoardPopupState extends State<BankpopBoardPopup> {
  late Future<BankpopBoard> _future;

  @override
  void initState() {
    super.initState();
    _future = BankpopBoard.loadFromAsset('assets/JSON/bankpop.json');
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final size =
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
              return Center(
                  child: Text('Could not load board: ${snap.error}'));
            }
            return _Board(
              board: snap.data!,
              size: size,
              isCardMode: widget.isCardMode,
            );
          },
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  final BankpopBoard board;
  final double size;
  final bool isCardMode;

  const _Board({
    required this.board,
    required this.size,
    required this.isCardMode,
  });

  static const int _cornerFlex = 14;
  static const int _tileFlex = 10;
  static const int _middleFlex = 90; 

  BankpopSpace? _spaceAt(int index) {
    for (final s in board.spaces) {
      if (s.index == index) return s;
    }
    return null;
  }

  @override
  @override
  Widget build(BuildContext context) {
    final go = _spaceAt(0);
    final jail = _spaceAt(10);
    final freeParking = _spaceAt(20);
    final goToJail = _spaceAt(30);

    // Bottom goes right to left (9 down to 1)
    final bottomTiles = [for (var i = 9; i >= 1; i--) _spaceAt(i)];
    
    // LEFT SIDE FIX: Goes top to bottom (19 down to 11)
    final leftTiles = [for (var i = 19; i >= 11; i--) _spaceAt(i)];
    
    // Top goes left to right (21 up to 29)
    final topTiles = [for (var i = 21; i <= 29; i++) _spaceAt(i)];
    
    // Right goes top to bottom (31 up to 39)
    final rightTiles = [for (var i = 31; i <= 39; i++) _spaceAt(i)];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF4E0BF),
        // Removed the outer bottom and right borders
        borderRadius: BorderRadius.circular(6), // Added rounded corners
      ),
      // ClipRRect ensures the square tiles don't bleed out of the rounded board
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          children: [
            // ── TOP ROW ──
            Expanded(
              flex: _cornerFlex,
              child: Row(
                children: [
                  _flexTile(context, freeParking, side: BoardSide.corner, flex: _cornerFlex),
                  for (final s in topTiles)
                    _flexTile(context, s, side: BoardSide.top, flex: _tileFlex),
                  _flexTile(context, goToJail, side: BoardSide.corner, flex: _cornerFlex),
                ],
              ),
            ),
            // ── MIDDLE ──
            Expanded(
              flex: _middleFlex,
              child: Row(
                children: [
                  // LEFT COLUMN
                  Expanded(
                    flex: _cornerFlex,
                    child: Column(
                      children: [
                        for (final s in leftTiles)
                          _flexTile(context, s, side: BoardSide.left, flex: _tileFlex),
                      ],
                    ),
                  ),
                  // CENTER LOGO AREA
                  Expanded(
                    flex: _middleFlex,
                    child: _interior(),
                  ),
                  // RIGHT COLUMN
                  Expanded(
                    flex: _cornerFlex,
                    child: Column(
                      children: [
                        for (final s in rightTiles)
                          _flexTile(context, s, side: BoardSide.right, flex: _tileFlex),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── BOTTOM ROW ──
            Expanded(
              flex: _cornerFlex,
              child: Row(
                children: [
                  _flexTile(context, jail, side: BoardSide.corner, flex: _cornerFlex),
                  for (final s in bottomTiles)
                    _flexTile(context, s, side: BoardSide.bottom, flex: _tileFlex),
                  _flexTile(context, go, side: BoardSide.corner, flex: _cornerFlex),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flexTile(
    BuildContext context, 
    BankpopSpace? space, 
    {required BoardSide side, required int flex}
  ) {
    return Expanded(
      flex: flex,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (space == null) {
            return SizedBox(width: constraints.maxWidth, height: constraints.maxHeight);
          }
          return BankpopTile(
            space: space,
            side: side,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            onTap: () => _onTap(context, space),
          );
        },
      ),
    );
  }

  void _onTap(BuildContext context, BankpopSpace space) {
    if (!space.isProperty) {
      if (space.name.toLowerCase().contains('chance')) {
        showBankpopDeckSheet(context, 'Chance', board.chanceOptions);
        return;
      }
      if (space.name.toLowerCase().contains('community chest')) {
        showBankpopDeckSheet(context, 'Community Chest', board.communityChest);
        return;
      }
      showBankpopSpecialInfo(context, space.name);
      return;
    }
    if (isCardMode) {
      // Hand the space back to the caller; it knows whether this device sells
      // cards by QR or assigns them to a player.
      Navigator.of(context).pop(space);
      return;
    }
    showBankpopSpaceCard(context, space);
  }

  Widget _interior() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF4E0BF),
        // The center board area draws its own Top and Left border to fit the grid
        border: Border(
          top: BorderSide(color: Colors.black, width: 1.0),
          left: BorderSide(color: Colors.black, width: 1.0),
        ),
      ),
      child: Image.asset(
        'assets/images/play_icon.jpg',
        fit: BoxFit.cover, 
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      ),
    );
  }
}