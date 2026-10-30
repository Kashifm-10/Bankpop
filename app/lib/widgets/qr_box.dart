import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A QR code in a dialog, sized by the box it is given.
///
/// qr_flutter's [QrImageView] draws itself inside a `LayoutBuilder`, and
/// Flutter's `Dialog` measures its children with an `IntrinsicWidth` - which is
/// not allowed to ask a `LayoutBuilder` for a size. Every dialog that carried a
/// `QrImageView` therefore threw while laying out (the barrier was already up,
/// so the screen was dimmed with no code on it) - which is what made "Take rent"
/// look stuck.
///
/// This paints the same code with the size it is given instead of measuring it,
/// so the dialog can ask what it needs and the code still fills its box.
class QrBox extends StatelessWidget {
  const QrBox({
    super.key,
    required this.data,
    required this.size,
    this.padding = const EdgeInsets.all(10),
    this.semanticsLabel = 'qr code',
  });

  /// What the code stands for.
  final String data;

  /// The edge of the box the code is drawn in, including [padding].
  final double size;

  final EdgeInsets padding;

  final String semanticsLabel;

  /// Nothing recognisable at 16 px: below this the box would be drawn, but no
  /// camera could read it, so it is better to see a small square than to see a
  /// broken dialog.
  static const double _minEdge = 16;

  @override
  Widget build(BuildContext context) {
    final double edge = math.max(_minEdge, size - padding.horizontal);
    return Semantics(
      label: semanticsLabel,
      child: Padding(
        padding: padding,
        child: CustomPaint(
          size: Size.square(edge),
          painter: QrPainter(
            data: data,
            version: QrVersions.auto,
            // The gap between modules is what a scanner locks on to; a code
            // drawn without it reads as one block at small sizes.
            gapless: false,
          ),
        ),
      ),
    );
  }
}
