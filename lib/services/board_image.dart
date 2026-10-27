import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_download.dart';
import 'package:mon/widgets/bankpop_board_view.dart';

/// The board as a picture a player can print.
///
/// It is the same [BankpopBoardView] the app draws, rendered off-screen at
/// print size and captured - so the printout and the screen cannot drift apart:
/// same tiles, same colours, same names, same artwork, same ring. On paper
/// there is no tap to open a deed, which is why the name and the price are on
/// the card itself.
///
/// A PNG is used rather than a PDF on purpose: capturing the board as drawn is
/// the only way to guarantee the printout matches the screen, and a square PNG
/// at 2x is already 2800x2800 - far more than a printer needs for an A4 sheet.
class BoardImage {
  const BoardImage._();

  /// Logical size the board is drawn at. The tiles are laid out in proportions
  /// of it, so this is what makes the names on the colour blocks big enough to
  /// read when the picture is printed.
  static const double boardSize = 1400;

  /// Pixels per logical pixel in the file, so the PNG is 2800x2800.
  static const double pixelRatio = 2;


  /// The conditions the board is drawn under for a download.
  ///
  /// The board is painted inside an overlay entry, which - unlike a screen -
  /// has no `Material` above it. Without one, `Text` inherits Flutter's
  /// fallback default style, and that style carries an underline in yellow:
  /// every printed card name came out of the PNG with a yellow line under it,
  /// while the same board on screen (inside a Scaffold) had none. Giving the
  /// board the screen's own `Material` and default text style is what makes the
  /// picture match what the player saw.
  static Widget frame(BuildContext context, Widget child) {
    final ThemeData theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: theme.textTheme.bodyMedium ?? const TextStyle(),
        child: child,
      ),
    );
  }

  /// Draws [board] off-screen and returns its PNG bytes.
  ///
  /// The board is built in the app's overlay, far off the left edge so nothing
  /// flashes on screen, and removed again once the pixels are taken. It is
  /// painted, not merely laid out - a board that is never painted has no
  /// pixels to capture.
  static Future<Uint8List> render(
    BuildContext context,
    BankpopBoard board,
  ) async {
    final GlobalKey boundaryKey = GlobalKey();
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      throw StateError('The board can only be drawn inside the app');
    }

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext _) => Positioned(
        left: 0,
        top: 0,
        child: Transform.translate(
          // Two boards to the left: laid out and painted, never seen.
          offset: const Offset(-2 * boardSize, 0),
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: boardSize,
              height: boardSize,
              child: frame(
                context,
                BankpopBoardView(
                  board: board,
                  size: boardSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    try {
      // One frame lays the board out, the next paints it.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final RenderObject? renderObject =
          boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('The board could not be drawn');
      }
      final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
      try {
        final ByteData? data =
            await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('The board could not be saved');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      entry.remove();
    }
  }

  /// Saves the picture where downloads go: the browser's downloads folder on
  /// the web, the platform's downloads (or documents) folder elsewhere.
  ///
  /// Returns the path written to, or null when the browser saved it itself.
  static Future<String?> save(Uint8List bytes, String boardName) =>
      BoardDownload.image(bytes, fileName(boardName));

  /// `bankpop-india-board.png`.
  static String fileName(String boardName) {
    final String slug = boardName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'bankpop-${slug.isEmpty ? 'board' : slug}-board.png';
  }
}
