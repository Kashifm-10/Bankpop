import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';

enum BoardSide { bottom, left, top, right, corner }

/// One card on the board.
///
/// The same tile is used by the game board, the boards screen and the printable
/// download, so a card cannot look like two different things in two places.
/// A bought card draws its colour block, its name under that block, its
/// artwork and its price in the same small type along the outer edge - the same
/// on every board, on screen and on paper. A utility has no name, and a special
/// square is only its artwork and its price.
class BankpopTile extends StatelessWidget {
  const BankpopTile({
    super.key,
    required this.space,
    required this.side,
    required this.width,
    required this.height,
    required this.onTap,
    this.houses = 0,
    this.hotels = 0,
    this.mortgaged = false,
    this.nameFontSize,
    this.currency = BoardCurrencies.fallback,
  });

  final BankpopSpace space;
  final BoardSide side;
  final double width;
  final double height;
  final VoidCallback onTap;

  final int houses;
  final int hotels;

  final bool mortgaged;

  /// The size of a card's name, set by the board so every card's name is the
  /// same size rather than each tile picking its own.
  final double? nameFontSize;

  /// The money symbol the card's price is written in: the board's own.
  final String currency;

  /// The paper the whole board is printed on.
  static const Color _paper = Color(0xFFF4E0BF);

  /// The line between two cards. Thin enough to read as a printed rule rather
  /// than a frame; every tile draws it on all four sides, so the screen board
  /// and the downloaded board both have a closed grid.
  static const double _line = 0.8;

  @override
  Widget build(BuildContext context) {
    final Widget body = side == BoardSide.corner
        ? _buildCornerContent()
        : space.isProperty
            ? _buildCardContent()
            : _buildSpecialContent();

    final Widget tile = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _paper,
        border: Border.all(color: Colors.black, width: _line),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          body,
          if (mortgaged) _mortgageTag(),
        ],
      ),
    );

    // The tile is what the board taps: without this wrapper every deed on the
    // board was silently untappable, which also left Give Card with no way in.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: tile,
    );
  }

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // A card on the board.
  // ---------------------------------------------------------------------------

  /// A special square - Chance, Tax, the corners' neighbours - is its own
  /// artwork, with a price along the outer edge when the board gives it one.
  Widget _buildSpecialContent() {
    final double minDim = min(width, height);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _rotatedArt(minDim * 0.55),
        if (space.price != null && space.price! > 0)
          _printedPrice(fontSize: _priceFontSize),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // A card that is bought.
  // ---------------------------------------------------------------------------

  bool get _isHorizontal =>
      side == BoardSide.top || side == BoardSide.bottom;

  /// A station is its own artwork: on paper its name is laid over the picture in
  /// the place a colour card carries its band, in dark type, so nothing is added
  /// to the card and the image is neither moved nor cropped.
  bool get _isStation => space.color == 'Station';

  /// A utility keeps its artwork too, with no name written over it.
  bool get _isUtility => space.color == 'Utility';

  /// One style for every price in the app, on every board: the small type a
  /// printed board uses, sized off the card so it scales with the window.
  double get _priceFontSize =>
      (min(width, height) * 0.06).clamp(5.0, 10.0).toDouble();

  /// A bought card: the colour band (with its name and any buildings), the
  /// artwork, and the price along the outer edge.
  Widget _buildCardContent() {
    final bool horizontal = _isHorizontal;
    final double minDim = min(width, height);
    final double thickness = (minDim * 0.30).clamp(18.0, 46.0).toDouble();
    final double longSide = horizontal ? width : height;
    final double priceFontSize = _priceFontSize;

    if (_isUtility) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _rotatedArt(minDim * 0.55),
          if (space.price != null && space.price! > 0)
            _printedPrice(fontSize: priceFontSize),
        ],
      );
    }

    if (_isStation) {
      // The name sits in the same band a colour card's name occupies, but over
      // the picture rather than in a block: the artwork is neither moved nor
      // cropped, and a station still reads in the same place as every other
      // card on the board.
      final Widget band = SizedBox(
        width: horizontal ? longSide : thickness,
        height: horizontal ? thickness : longSide,
        child: Center(child: _printedName()),
      );
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _rotatedArt(minDim * 0.55),
          Align(alignment: _innerAlignment, child: band),
          if (space.price != null && space.price! > 0)
            _printedPrice(fontSize: priceFontSize),
        ],
      );
    }

    // The name is set just outside the block, on the card itself, so the block
    // stays a solid band and the name is never squeezed into a strip. The band
    // is cut back to leave the name its own room, and the name may take a little
    // under half the card so a small tile never overflows.
    final double shortSide = min(width, height);
    final double nameSlot =
        (shortSide * 0.30).clamp(2.0, min(26.0, shortSide * 0.42)).toDouble();
    final double blockThickness =
        ((shortSide - nameSlot) * 0.42).clamp(4.0, 46.0).toDouble();

    // What stands on the card, drawn on the band: a green house for each house
    // and one red building for a hotel.
    final Widget? buildings = _buildBuildings(
      thickness: blockThickness,
      horizontal: horizontal,
    );

    final Widget strip = _strip(
      Color(BankpopBoard.colorForGroup(space.color)),
      horizontal: horizontal,
      thickness: blockThickness,
      // No line around the block that holds the name: the tile's own border
      // closes the card, and a second rule under the name read as an underline.
      border: const Border(),
      child: buildings,
    );

    final Widget nameBand = SizedBox(
      width: horizontal ? longSide : nameSlot,
      height: horizontal ? nameSlot : longSide,
      child: Center(child: _printedName()),
    );

    final Widget art = _rotatedArt(minDim * 0.42);

    final Widget body = horizontal
        ? Column(
            children: <Widget>[
              if (side == BoardSide.bottom) ...<Widget>[
                strip,
                nameBand,
              ],
              Expanded(child: art),
              if (side == BoardSide.top) ...<Widget>[
                nameBand,
                strip,
              ],
            ],
          )
        : Row(
            children: <Widget>[
              if (side == BoardSide.right) ...<Widget>[
                strip,
                nameBand,
              ],
              Expanded(child: art),
              if (side == BoardSide.left) ...<Widget>[
                nameBand,
                strip,
              ],
            ],
          );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        body,
        if (space.price != null && space.price! > 0)
          _printedPrice(fontSize: priceFontSize),
      ],
    );
  }

  /// Where a card's name sits: against the edge that faces the middle of the
  /// board, which is where the colour band is on a colour card.
  Alignment get _innerAlignment {
    switch (side) {
      case BoardSide.bottom:
        return Alignment.topCenter;
      case BoardSide.top:
        return Alignment.bottomCenter;
      case BoardSide.left:
        return Alignment.centerRight;
      case BoardSide.right:
        return Alignment.centerLeft;
      case BoardSide.corner:
        return Alignment.center;
    }
  }

  /// The card's name, set under its colour block or over a station's artwork.
  ///
  /// The name is broken between words - never inside one - into the two lines
  /// that come out most even, and the block of them is scaled down to the card.
  /// So a long name gets a second line, and a single long word shrinks instead
  /// of being cut in half. The type is the same on every card of a board, so a
  /// board reads as one set rather than each name picking a size of its own.
  Widget _printedName() {
    final double caption =
        nameFontSize ?? (min(width, height) * 0.16).clamp(5.0, 12.0).toDouble();
    final List<String> lines = _nameLines(space.name.toUpperCase());

    final Widget block = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final String line in lines)
          Text(
            line,
            textAlign: TextAlign.center,
            softWrap: false,
            maxLines: 1,
            style: TextStyle(
              fontSize: caption,
              height: 1.02,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF3E2723),
            ),
          ),
      ],
    );

    return RotatedBox(
      quarterTurns: _quarterTurns(side),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: block,
          ),
        ),
      ),
    );
  }

  /// A name broken between words into at most two as-even-as-possible lines.
  ///
  /// The split that makes the longer of the two lines shortest wins, so
  /// 'GRAND CENTRAL STATION' becomes 'GRAND CENTRAL' / 'STATION' rather than
  /// 'GRAND' / 'CENTRAL STATION'. One word stays one line, however long it is.
  static List<String> _nameLines(String name) {
    final List<String> words = name
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .toList();
    if (words.length < 2) return <String>[name];

    int bestSplit = 1;
    int bestLongest = 1 << 30;
    for (int split = 1; split < words.length; split++) {
      final int first = words.take(split).join(' ').length;
      final int second = words.skip(split).join(' ').length;
      final int longest = max(first, second);
      if (longest < bestLongest) {
        bestLongest = longest;
        bestSplit = split;
      }
    }

    return <String>[
      words.take(bestSplit).join(' '),
      words.skip(bestSplit).join(' '),
    ];
  }

  /// The price, in the small type a printed board uses, on the outer edge of
  /// the card - the bottom of the card as it is read - with a little room under
  /// it so it does not sit on the line.
  ///
  /// A colour card, a station, a utility and a special all use this one label:
  /// same size, same ink, same place, whatever the board.
  Widget _printedPrice({required double fontSize}) {
    final Widget label = RotatedBox(
      quarterTurns: _quarterTurns(side),
      child: Text(
        BoardCurrencies.format(currency, space.price!),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF3E2723),
        ),
      ),
    );

    // Three points of paper below the price: enough that it reads as set on the
    // card rather than underlined by its border.
    const double spacing = 3;
    switch (side) {
      case BoardSide.bottom:
      case BoardSide.corner:
        return Positioned(
          left: 2,
          right: 2,
          bottom: spacing,
          child: Center(child: label),
        );
      case BoardSide.top:
        return Positioned(
          left: 2,
          right: 2,
          top: spacing,
          child: Center(child: label),
        );
      case BoardSide.left:
        return Positioned(
          top: 2,
          bottom: 2,
          left: spacing,
          child: Center(child: label),
        );
      case BoardSide.right:
        return Positioned(
          top: 2,
          bottom: 2,
          right: spacing,
          child: Center(child: label),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Shared pieces.
  // ---------------------------------------------------------------------------

  Widget _strip(
    Color color, {
    required bool horizontal,
    required double thickness,
    required Border border,
    Widget? child,
  }) {
    return Container(
      width: horizontal ? double.infinity : thickness,
      height: horizontal ? thickness : double.infinity,
      decoration: BoxDecoration(color: color, border: border),
      child: child,
    );
  }

  /// What stands on a card, standing on its colour band: a green house for each
  /// house, and one red building once a hotel has been put up instead.
  Widget? _buildBuildings({
    required double thickness,
    required bool horizontal,
  }) {
    if (houses <= 0 && hotels <= 0) return null;

    // A mark stands on the colour band, so it is sized off the band and kept
    // small enough that four houses and the price beside them still read.
    final double size = (thickness * 0.6).clamp(5.0, 16.0).toDouble();
    final List<Widget> marks = hotels > 0
        ? <Widget>[
            Icon(
              Icons.apartment_rounded,
              size: size,
              color: const Color(0xFFC62828),
            ),
          ]
        : <Widget>[
            for (int i = 0; i < houses; i++)
              Icon(
                Icons.home_rounded,
                size: size,
                color: const Color(0xFF1B5E20),
              ),
          ];

    final Widget row = horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: marks)
        : Column(mainAxisSize: MainAxisSize.min, children: marks);
    return Center(
      child: FittedBox(fit: BoxFit.scaleDown, child: row),
    );
  }

  int _quarterTurns(BoardSide side) {
    switch (side) {
      case BoardSide.left:
        return 1;
      case BoardSide.top:
        return 2;
      case BoardSide.right:
        return 3;
      case BoardSide.bottom:
      case BoardSide.corner:
        return 0;
    }
  }

  Widget _rotatedArt(double size) {
    final int quarterTurns = _quarterTurns(side);

    Widget? content;
    bool isFullFill = false;
    String? imagePath;

    if (space.name.contains('Chance')) {
      imagePath = 'assets/images/Chance.png';
    } else if (space.name.contains('Community Chest')) {
      imagePath = 'assets/images/Community_Chest.png';
    } else if (space.name.contains('Station')) {
      imagePath = 'assets/images/Station.png';
    } else if (space.name.contains('Electric')) {
      imagePath = 'assets/images/Electric.png';
    } else if (space.name.contains('Water')) {
      imagePath = 'assets/images/Water.png';
    } else if (space.name.contains('Tax')) {
      imagePath = 'assets/images/Tax.png';
    }

    if (imagePath != null) {
      isFullFill = true;
      content = Image.asset(
        imagePath,
        fit: BoxFit.fill,
        errorBuilder: (context, error, stackTrace) {
          final fallbackIcon =
              _getIconForSpace(space.name) ?? Icons.broken_image;
          return Center(
              child: Icon(fallbackIcon, size: size, color: Colors.black87));
        },
      );
    } else {
      final IconData? icon = _getIconForSpace(space.name);
      if (icon != null) {
        content = Icon(icon, size: size, color: Colors.black87);
      }
    }

    if (content == null) return const SizedBox.shrink();

    return RotatedBox(
      quarterTurns: quarterTurns,
      child:
          isFullFill ? SizedBox.expand(child: content) : Center(child: content),
    );
  }

  IconData? _getIconForSpace(String name) {
    if (name.contains('Station')) return Icons.train;
    if (name.contains('Water')) return Icons.water_drop;
    if (name.contains('Electric')) return Icons.lightbulb;
    if (name.contains('Community Chest')) return Icons.card_giftcard;
    if (name.contains('Chance')) return Icons.question_mark;
    if (name.contains('Tax')) return Icons.money_off;
    return null;
  }

  Widget _buildCornerContent() {
    String? imagePath;

    switch (space.name) {
      case 'GO':
        imagePath = 'assets/images/Go.png';
        break;
      case 'Jail':
        imagePath = 'assets/images/Jail.png';
        break;
      case 'Free Parking':
        imagePath = 'assets/images/Free_Parking.png';
        break;
      case 'Go To Jail':
        imagePath = 'assets/images/Go_To_Jail.png';
        break;
    }

    if (imagePath == null) return const SizedBox.shrink();

    final Widget art = Image.asset(
      imagePath,
      width: width,
      height: height,
      fit: BoxFit.fill,
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.error_outline, color: Colors.red)),
    );

    // GO pays the advance the banker set for this game, so the square carries no
    // figure of its own: it names the payment, and whatever the banker set is
    // what a player collects.
    if (space.name == 'GO') {
      final double minDim = min(width, height);
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          art,
          // The artwork leaves a clear band between the word GO and the arrow:
          // in Go.png the word ends at about 46% of the height and the arrow
          // starts at about 65%, so the caption is set inside that band, between
          // the two, rather than across the arrow at the bottom.
          Positioned(
            left: 3,
            right: 3,
            top: minDim * 0.475,
            height: minDim * 0.145,
            // Scales down rather than clipping: the corner is small on a phone
            // and large on a printout, and the caption has to read on both.
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'COLLECT ADVANCE',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: (minDim * 0.10).clamp(6.0, 14.0).toDouble(),
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1B1B1B),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return art;
  }

  Widget _mortgageTag() {
    return Positioned(
      top: 2,
      right: 2,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration:
            const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
        child: const Text(
          'M',
          style: TextStyle(
              color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
