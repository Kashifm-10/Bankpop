import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mon/models/bankpop_board.dart';
import 'package:mon/theme.dart';

/// BankPop's own coin: a gold disc with the money sign on it, turning slowly.
///
/// The screens used to borrow a coin animation from an icon pack, and every
/// coin in it was stamped with a dollar, a euro or a yen. Money in this app is
/// written in one sign (see [BoardCurrencies.mark]), so the coin is drawn here
/// instead - the same disc, the same turn, with BankPop's mark on it.
class BankpopCoin extends StatefulWidget {
  const BankpopCoin({super.key, this.size = 64, this.period = const Duration(milliseconds: 2800)});

  /// The diameter of the disc.
  final double size;

  /// How long one full turn takes.
  final Duration period;

  @override
  State<BankpopCoin> createState() => _BankpopCoinState();
}

class _BankpopCoinState extends State<BankpopCoin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _turn,
        builder: (BuildContext context, Widget? child) {
          final double angle = _turn.value * 2 * math.pi;
          // A coin seen edge-on for a moment: the perspective entry is what
          // makes the turn read as a spin rather than a squash.
          final Matrix4 matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateY(angle);
          return Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: child,
          );
        },
        // The face is drawn once; only the transform changes as it turns.
        child: CustomPaint(
          painter: _CoinPainter(),
          size: Size.square(widget.size),
        ),
      ),
    );
  }
}

class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;

    final Paint rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..color = const Color(0xFF22304A);
    final Paint face = Paint()..color = const Color(0xFFFFD34D);
    final Paint inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.06
      ..color = const Color(0xFFE0A800);

    canvas.drawCircle(centre, radius - radius * 0.06, face);
    canvas.drawCircle(centre, radius * 0.82, inner);
    canvas.drawCircle(centre, radius - radius * 0.06, rim);

    // The sign: the app's own font, so the coin carries exactly the character
    // every price in the app is written with.
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: BoardCurrencies.mark,
        style: TextStyle(
          fontFamily: CustomTheme.markFamily,
          fontSize: radius * 1.15,
          color: const Color(0xFF22304A),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      centre - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
