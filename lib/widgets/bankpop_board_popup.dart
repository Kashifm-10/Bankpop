import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/bankpop_deck_sheet.dart';
import 'package:mon/widgets/bankpop_space_card.dart';
import 'package:mon/widgets/bankpop_tile.dart';
import 'package:mon/widgets/card_owner_badge.dart';

class BankpopBoardPopup extends StatefulWidget {
  final bool isCardMode;
  final String gameId;

  /// In cards mode a tap normally closes the board with the chosen space. When
  /// this is set the board stays open and the callback runs instead, so the
  /// caller can open the deed *on top of* the board rather than replacing it.
  final void Function(BankpopSpace space)? onSpaceSelected;

  const BankpopBoardPopup({
    super.key,
    this.isCardMode = false,
    this.gameId = '',
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
    _future = BankpopBoard.loadFromAsset('assets/JSON/bankpop.json');
    _owners = PlayerCards.owners(widget.gameId);
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
              return Center(child: Text('Could not load board: ${snap.error}'));
            }
            return FutureBuilder<Map<int, CardOwner>>(
              future: _owners,
              builder: (context, ownersSnap) {
                if (ownersSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _Board(
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

class _Board extends StatelessWidget {
  final BankpopBoard board;
  final double size;
  final bool isCardMode;
  final Map<int, CardOwner> owners;
  final void Function(BankpopSpace space)? onSpaceSelected;

  const _Board({
    required this.board,
    required this.size,
    required this.isCardMode,
    required this.owners,
    this.onSpaceSelected,
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
  Widget build(BuildContext context) {
    final go = _spaceAt(0);
    final jail = _spaceAt(10);
    final freeParking = _spaceAt(20);
    final goToJail = _spaceAt(30);

    final bottomTiles = [for (var i = 9; i >= 1; i--) _spaceAt(i)];
    final leftTiles = [for (var i = 19; i >= 11; i--) _spaceAt(i)];
    final topTiles = [for (var i = 21; i <= 29; i++) _spaceAt(i)];
    final rightTiles = [for (var i = 31; i <= 39; i++) _spaceAt(i)];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF4E0BF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          children: [
            Expanded(
              flex: _cornerFlex,
              child: Row(
                children: [
                  _flexTile(context, freeParking,
                      side: BoardSide.corner, flex: _cornerFlex),
                  for (final s in topTiles)
                    _flexTile(context, s, side: BoardSide.top, flex: _tileFlex),
                  _flexTile(context, goToJail,
                      side: BoardSide.corner, flex: _cornerFlex),
                ],
              ),
            ),
            Expanded(
              flex: _middleFlex,
              child: Row(
                children: [
                  Expanded(
                    flex: _cornerFlex,
                    child: Column(
                      children: [
                        for (final s in leftTiles)
                          _flexTile(context, s,
                              side: BoardSide.left, flex: _tileFlex),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: _middleFlex,
                    child: _interior(),
                  ),
                  Expanded(
                    flex: _cornerFlex,
                    child: Column(
                      children: [
                        for (final s in rightTiles)
                          _flexTile(context, s,
                              side: BoardSide.right, flex: _tileFlex),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: _cornerFlex,
              child: Row(
                children: [
                  _flexTile(context, jail,
                      side: BoardSide.corner, flex: _cornerFlex),
                  for (final s in bottomTiles)
                    _flexTile(context, s,
                        side: BoardSide.bottom, flex: _tileFlex),
                  _flexTile(context, go,
                      side: BoardSide.corner, flex: _cornerFlex),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flexTile(BuildContext context, BankpopSpace? space,
      {required BoardSide side, required int flex}) {
    return Expanded(
      flex: flex,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (space == null) {
            return SizedBox(
                width: constraints.maxWidth, height: constraints.maxHeight);
          }
          return BankpopTile(
            space: space,
            side: side,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            ownerName: owners[space.index]?.name,
            houses: owners[space.index]?.houses ?? 0,
            hotels: owners[space.index]?.hotels ?? 0,
            mortgaged: owners[space.index]?.mortgaged ?? false,
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
    final CardOwner? owner = owners[space.index];
    if (owner != null) {
      showBankpopSpaceCard(
        context,
        space,
        actionWidget: CardOwnerBadge(owner: owner),
        houses: owner.houses,
        hotels: owner.hotels,
      );
      return;
    }
    if (isCardMode) {
      // The caller wants to keep the board visible under the deed it opens.
      final void Function(BankpopSpace space)? onSelected = onSpaceSelected;
      if (onSelected != null) {
        onSelected(space);
        return;
      }
      Navigator.of(context).pop(space);
      return;
    }
    showBankpopSpaceCard(context, space);
  }

  Widget _interior() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF4E0BF),
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
