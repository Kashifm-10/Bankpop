import 'package:flutter/material.dart';
import 'package:mon/widgets/game_controls.dart';

/// What the pack on the board has to say for itself.
///
/// The tiles on the board carry two small marks: a shuffle button in their top
/// corner and how much is left of the pack in the other. This is the data
/// behind both, so a tile never has to know how a pack is counted or where it
/// is stored.
class DeckStatus {
  const DeckStatus({
    required this.left,
    required this.total,
    required this.onShuffle,
    this.onPressed,
    this.shuffling = false,
  });

  /// Cards still unseen in the pack.
  final int left;

  /// The pack's size, so the mark reads "19/22".
  final int total;

  /// Puts the pack in a new order.
  final VoidCallback onShuffle;

  /// Deals the next card. Null when the table is not dealing.
  final VoidCallback? onPressed;

  /// True while the shuffle is being written, so the button shows a spinner in
  /// place of itself until the pack comes back.
  final bool shuffling;
}

/// One of the two packs the banker deals from, as a tile that is exactly the
/// drawing.
///
/// The packs are landscape art, so a square sticker would leave the picture
/// floating in bare paper above and below it. The tile takes the art's own
/// ratio instead: give it a width and its height follows, and the drawing
/// covers every pixel of it. The art is cropped to its own bounds
/// (623 x 382) and its corners are transparent, so nothing is painted behind
/// it - a coloured surface would fill those corners with a band that is not in
/// the picture. The art itself is red for Chance and blue for Community Chest,
/// so the two packs read apart at a glance.
class DeckButton extends StatelessWidget {
  const DeckButton({
    super.key,
    required this.control,
    required this.width,
    this.onPressed,
    this.status,
    this.enabled = true,
  });

  /// 623 x 382: the ratio of `chance_deck_l_trimmed.png` and
  /// `chest_deck_l_trimmed.png` - the deck art cropped to its own bounds, with
  /// the drop shadow under it removed.
  static const double artRatio = 623 / 382;

  /// The tile's name and sentence, from the shared palette.
  final GameControl control;

  final VoidCallback? onPressed;

  /// The cards left and the shuffle, drawn on the tile. Null leaves the tile as
  /// just the drawing, which is what the doctor's legend and the tests use.
  final DeckStatus? status;

  /// The tile's width; its height is [artRatio] of it, so it never distorts
  /// the drawing.
  final double width;

  final bool enabled;

  double get height => width / artRatio;

  /// Dealing the next card: the caller's own handler, or the one the status was
  /// given when the tile sits on the board.
  VoidCallback? get _draw => status?.onPressed ?? onPressed;

  bool get _active => enabled && _draw != null;

  @override
  Widget build(BuildContext context) {
    final DeckStatus? status = this.status;
    // The marks sit inside the drawing's corners, clear of its rounded edge.
    // The count keeps a little more air from the edge than the shuffle does: it
    // is the smaller of the two and would otherwise read as if it were falling
    // off the card.
    final double pad = width * 0.07;
    final double countPad = width * 0.085;

    return Tooltip(
      message: control.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: _active,
        label: control.label,
        hint: control.detail,
        child: Material(
          // Nothing behind the art: its own corners are transparent, and a
          // coloured surface would show through them as a band that is not in
          // the picture.
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(width * 0.08),
          ),
          elevation: _active ? 2.5 : 0,
          shadowColor: Colors.brown.shade200,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _active ? _draw : null,
            // The tile is the drawing, edge to edge: the button's size is the
            // art's own ratio, so there is no band of colour left inside it to
            // look like a margin.
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Opacity(
                    opacity: _active ? 1 : 0.38,
                    child: Image.asset(
                      control.art!,
                      fit: BoxFit.fill,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  if (status != null) ...<Widget>[
                    Positioned(
                      left: pad,
                      top: pad,
                      child: _shuffleButton(status),
                    ),
                    Positioned(
                      right: countPad,
                      bottom: countPad,
                      child: _leftBadge(status),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The pack's own shuffle, in the tile's top corner. It turns into the
  /// spinner that says the shuffle is still being written.
  ///
  /// Nothing is painted behind it: the mark is the glyph, laid straight on the
  /// drawing, with a soft shadow to keep it off the art under it.
  Widget _shuffleButton(DeckStatus status) {
    final double side = (width * 0.11).clamp(12.0, 18.0).toDouble();
    return Semantics(
      button: true,
      label: 'Shuffle the ${control.label.toLowerCase()}',
      child: Tooltip(
        message: 'Shuffle this pack',
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: status.shuffling ? null : status.onShuffle,
          radius: side * 0.9,
          child: SizedBox(
            width: side,
            height: side,
            child: Center(
              child: status.shuffling
                  ? SizedBox(
                      width: side * 0.62,
                      height: side * 0.62,
                      child: const CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: Color(0xFFFFF3D6),
                      ),
                    )
                  : Icon(
                      Icons.shuffle,
                      size: side * 0.9,
                      color: const Color(0xFFFFF3D6),
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0x99000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// How much of the pack is left, in the tile's other corner: the numbers on
  /// their own, in the card's cream, with the same soft shadow.
  Widget _leftBadge(DeckStatus status) {
    final double font = (width * 0.058).clamp(6.5, 9.0).toDouble();
    return Semantics(
      label: '${status.left} of ${status.total} cards left in the '
          '${control.label.toLowerCase()}',
      child: ExcludeSemantics(
        child: Text(
          '${status.left}/${status.total}',
          style: TextStyle(
            fontSize: font,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: const Color(0xFFFFF3D6),
            shadows: const <Shadow>[
              Shadow(
                color: Color(0x99000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
