import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/card_deck.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/bankpop_space_card.dart';
import 'package:mon/widgets/card_effect_flow.dart';
import 'package:mon/widgets/bankpop_tile.dart';
import 'package:mon/widgets/card_owner_badge.dart';
import 'package:mon/widgets/player_palette.dart';

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
          final Widget tile = BankpopTile(
            space: space,
            side: side,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            houses: owner?.houses ?? 0,
            hotels: owner?.hotels ?? 0,
            mortgaged: owner?.mortgaged ?? false,
            currency: board.currency,
            // One size for every name, so a short name is not drawn larger than
            // a long one.
            nameFontSize: (size * 0.016).clamp(6.5, 12.0).toDouble(),
            onTap: () => _onTap(context, space),
          );
          if (owner == null) return tile;

          // The holder's face sits on the card's inner edge, facing the middle
          // of the board, and hangs mostly outside the card - a fifth of it
          // over the card, four fifths of it clear of it - so the colour block
          // and the buildings standing on it are never covered: above a card on
          // the bottom row, below one on the top row, beside the left and right
          // columns. Nothing on the card is moved to make room for it, so the
          // deed, its block, its name and its price are untouched.
          final double badge = (min(constraints.maxWidth, constraints.maxHeight) *
                  0.42)
              .clamp(13.0, 26.0)
              .toDouble();
          // Only the fifth of the badge that sits over the card is inside it.
          final double hang = badge * 0.8;
          final Widget avatar = _ownerBadge(owner, badge);

          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              tile,
              switch (side) {
                BoardSide.bottom => Positioned(
                    top: -hang,
                    left: (constraints.maxWidth - badge) / 2,
                    child: avatar,
                  ),
                BoardSide.top => Positioned(
                    bottom: -hang,
                    left: (constraints.maxWidth - badge) / 2,
                    child: avatar,
                  ),
                BoardSide.left => Positioned(
                    right: -hang,
                    top: (constraints.maxHeight - badge) / 2,
                    child: avatar,
                  ),
                BoardSide.right => Positioned(
                    left: -hang,
                    top: (constraints.maxHeight - badge) / 2,
                    child: avatar,
                  ),
                BoardSide.corner => Positioned(
                    top: -hang,
                    left: (constraints.maxWidth - badge) / 2,
                    child: avatar,
                  ),
              },
            ],
          );
        },
      ),
    );
  }

  /// A player's face as the board marks a card they hold: round, with the ring
  /// in the colour the leaderboard gives them, so the same player is the same
  /// colour everywhere.
  Widget _ownerBadge(CardOwner owner, double size) {
    final String? raw = owner.avatar;
    final String path =
        (raw == null || raw.isEmpty) ? 'assets/avatars/boy1.jpg' : raw;
    final String initial =
        owner.name.trim().isEmpty ? '?' : owner.name.trim()[0].toUpperCase();

    return Semantics(
      label: owner.name,
      child: Tooltip(
        message: owner.name,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: PlayerPalette.forName(owner.name),
              width: max(1.5, size * 0.12),
            ),
          ),
          child: ClipOval(
            child: Image.asset(
              path,
              fit: BoxFit.cover,
              // The source avatars are 500-1200px; this is drawn at 26 at most.
              cacheWidth: 64,
              errorBuilder: (BuildContext context, Object error,
                      StackTrace? stackTrace) =>
                  ColoredBox(
                color: PlayerPalette.forName(owner.name),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: size * 0.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, BankpopSpace space) {
    if (!space.isProperty) {
      // A pack's square shows the pack: its card face, as a picture and nothing
      // else. Dealing still belongs to the banker, so this settles nothing and
      // closes on an outside tap like any other picture.
      final CardDeckKind? pack = _packOf(space.name);
      if (pack != null) {
        showCardFacePreview(context, pack);
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
        currency: board.currency,
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
    showBankpopSpaceCard(context, space, currency: board.currency);
  }

  /// The pack a special square belongs to, or null for GO, Jail and the taxes.
  ///
  /// The squares are named on the board itself (and a custom board keeps the
  /// names), so the name is what decides which of the two packs a square opens.
  static CardDeckKind? _packOf(String name) {
    if (name.contains('Community Chest')) return CardDeckKind.chest;
    if (name.contains('Chance')) return CardDeckKind.chance;
    return null;
  }

  Widget _interior() {
    return Container(
      // The frame around the middle: the lines that close the ring of cards.
      // A printed board draws them too - a paper board without a frame was
      // half a board, which is what made the screen and the download disagree.
      decoration: BoxDecoration(
        color: const Color(0xFFF4E0BF),
        border: Border.all(color: Colors.black, width: 0.8),
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
