import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/bankpop_deck_sheet.dart';
import 'package:mon/widgets/bankpop_space_card.dart';
import 'package:mon/widgets/bankpop_tile.dart';
import 'package:mon/widgets/card_owner_badge.dart';

/// The square board itself, drawn from a [BankpopBoard].
///
/// The tiles are laid out in the usual ring - the four corners are fixed and
/// the sides run clockwise from GO - so a country board is the same shape with
/// that country's names on the tiles. It is a plain widget rather than a dialog
/// so the board can be shown inside one (the game screens) or inside a page
/// (the country preview).
class BankpopBoardView extends StatelessWidget {
  const BankpopBoardView({
    super.key,
    required this.board,
    required this.size,
    this.isCardMode = false,
    this.owners = const <int, CardOwner>{},
    this.onSpaceSelected,
    this.printNames = false,
  });

  final BankpopBoard board;
  final double size;

  /// In cards mode a tap normally closes the board with the chosen space. When
  /// [onSpaceSelected] is set the board stays open and the callback runs
  /// instead, so the caller can open the deed *on top of* the board.
  final bool isCardMode;

  /// Who holds each board index in this game. Empty on the preview board.
  final Map<int, CardOwner> owners;

  final void Function(BankpopSpace space)? onSpaceSelected;

  /// The printable board: same board, but each card's name is written inside
  /// its colour block so a printout can be played on without the app open.
  final bool printNames;

  static const int _cornerFlex = 14;
  static const int _tileFlex = 10;
  static const int _middleFlex = 90;

  BankpopSpace? _spaceAt(int index) {
    for (final BankpopSpace s in board.spaces) {
      if (s.index == index) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final BankpopSpace? go = _spaceAt(0);
    final BankpopSpace? jail = _spaceAt(10);
    final BankpopSpace? freeParking = _spaceAt(20);
    final BankpopSpace? goToJail = _spaceAt(30);

    final List<BankpopSpace?> bottomTiles = <BankpopSpace?>[
      for (var i = 9; i >= 1; i--) _spaceAt(i)
    ];
    final List<BankpopSpace?> leftTiles = <BankpopSpace?>[
      for (var i = 19; i >= 11; i--) _spaceAt(i)
    ];
    final List<BankpopSpace?> topTiles = <BankpopSpace?>[
      for (var i = 21; i <= 29; i++) _spaceAt(i)
    ];
    final List<BankpopSpace?> rightTiles = <BankpopSpace?>[
      for (var i = 31; i <= 39; i++) _spaceAt(i)
    ];

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
          children: <Widget>[
            Expanded(
              flex: _cornerFlex,
              child: Row(
                children: <Widget>[
                  _flexTile(context, freeParking,
                      side: BoardSide.corner, flex: _cornerFlex),
                  for (final BankpopSpace? s in topTiles)
                    _flexTile(context, s, side: BoardSide.top, flex: _tileFlex),
                  _flexTile(context, goToJail,
                      side: BoardSide.corner, flex: _cornerFlex),
                ],
              ),
            ),
            Expanded(
              flex: _middleFlex,
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: _cornerFlex,
                    child: Column(
                      children: <Widget>[
                        for (final BankpopSpace? s in leftTiles)
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
                      children: <Widget>[
                        for (final BankpopSpace? s in rightTiles)
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
                children: <Widget>[
                  _flexTile(context, jail,
                      side: BoardSide.corner, flex: _cornerFlex),
                  for (final BankpopSpace? s in bottomTiles)
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
          final CardOwner? owner = owners[space.index];
          return BankpopTile(
            space: space,
            side: side,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            ownerName: owner?.name,
            houses: owner?.houses ?? 0,
            hotels: owner?.hotels ?? 0,
            mortgaged: owner?.mortgaged ?? false,
            printNames: printNames,
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
