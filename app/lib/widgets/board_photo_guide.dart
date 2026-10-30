import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mon/widgets/app_dialog.dart';

/// The instructions for photographing a board, shown before the camera opens.
///
/// A board photograph is only readable if it was taken the way the board is
/// printed: GO in the bottom-right corner and Free Parking in the top-left, so
/// the squares run in play order from the start. Held the other way round - the
/// common mistake, because the far corners are the ones in the picture - the
/// names come out reversed, and a player would have to retype all of them.
///
/// The dialog says that in one drawing rather than in words: a ring with the two
/// corners named and arrows for the way the squares are read. It also names the
/// squares BankPop does not take from the picture, because they are the game's
/// own (the corners, the two packs, the taxes, and the utilities that always
/// keep their names), so nobody photographs the board wondering why twenty-eight
/// names came back.
Future<void> showBoardPhotoGuide(BuildContext context) {
  return showAppDialog<void>(
    context,
    title: 'Point at the board',
    icon: Icons.photo_camera_outlined,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Center(
          child: SizedBox.square(dimension: 200, child: const _BoardRing()),
        ),
        const SizedBox(height: 14),
        const _Point(
          icon: Icons.crop_free,
          text: 'GO in the bottom-right corner, FREE PARKING in the top-left, '
              'and the whole board inside the frame. The squares are read from '
              'GO and clockwise - round the bottom, up the left side, along the '
              'top and down the right side - which is the way the board is '
              'printed.',
        ),
        const _Point(
          icon: Icons.wb_sunny_outlined,
          text: 'Flat board, even light, no glare: names read best straight on, '
              'and a steep angle cuts them short.',
        ),
        const _Point(
          icon: Icons.filter_alt_off_outlined,
          text: 'Prices are ignored. So are the squares that belong to the game '
              'itself - the four corners, Chance, Community Chest, Income Tax, '
              'Super Tax, Luxury Tax, Electric and Water - which keep their '
              'usual names.',
        ),
        const _Point(
          icon: Icons.fact_check_outlined,
          text: 'You check every name before anything is saved, so a misread '
              'square costs a correction rather than a board.',
        ),
      ],
    ),
    actions: <Widget>[
      AppDialogButton(
        label: 'Got it',
        primary: true,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

/// One line of the guide: a small icon and a sentence.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppDialogPalette palette = AppDialogPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: palette.accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: palette.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The board as a ring: the two corners that fix its orientation, and the way
/// the squares are read from GO.
class _BoardRing extends StatelessWidget {
  const _BoardRing();

  @override
  Widget build(BuildContext context) {
    final AppDialogPalette palette = AppDialogPalette.of(context);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _RingPainter(
              board: const Color(0xFFFFF8E1),
              edge: const Color(0xFFDCEDC8),
              arrow: palette.accent,
            ),
          ),
        ),
        // The two corners that decide which way round the picture is.
        Positioned(
          top: 0,
          left: 0,
          child: _Corner(text: 'FREE\nPARKING', palette: palette),
        ),
        Positioned(
          bottom: 5,
          right: 5,
          child: _Corner(text: 'GO', palette: palette, strong: true),
        ),
      ],
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({
    required this.text,
    required this.palette,
    this.strong = false,
  });

  final String text;
  final AppDialogPalette palette;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? palette.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: strong ? null : Border.all(color: palette.accent, width: 1),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: strong ? Colors.white : palette.accent,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.board,
    required this.edge,
    required this.arrow,
  });

  final Color board;
  final Color edge;
  final Color arrow;

  @override
  void paint(Canvas canvas, Size size) {
    // Room for the two corner labels, which sit outside the border.
    const double inset = 30;
    final Rect ring = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final RRect rrect =
        RRect.fromRectAndRadius(ring, const Radius.circular(9));

    canvas.drawRRect(rrect, Paint()..color = board);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = edge,
    );

    // The way the squares are read, drawn on the ring itself: from GO in the
    // bottom-right corner, clockwise - bottom row from the right to the left, up
    // the left side, along the top, and down the right side back to GO.
    final Paint line = Paint()
      ..color = arrow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    _arrow(canvas, Offset(ring.right - 18, ring.bottom),
        Offset(ring.left + 18, ring.bottom), line);
    _arrow(canvas, Offset(ring.left, ring.bottom - 18),
        Offset(ring.left, ring.top + 18), line);
    _arrow(canvas, Offset(ring.left + 18, ring.top),
        Offset(ring.right - 18, ring.top), line);
    _arrow(canvas, Offset(ring.right, ring.top + 18),
        Offset(ring.right, ring.bottom - 18), line);
  }

  void _arrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    canvas.drawLine(from, to, paint);
    final double angle = (to - from).direction;
    const double head = 6.5;
    final Path path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - head * math.cos(angle - 0.6),
        to.dy - head * math.sin(angle - 0.6),
      )
      ..lineTo(
        to.dx - head * math.cos(angle + 0.6),
        to.dy - head * math.sin(angle + 0.6),
      )
      ..close();
    canvas.drawPath(path, Paint()..color = paint.color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.board != board || old.edge != edge || old.arrow != arrow;
}
