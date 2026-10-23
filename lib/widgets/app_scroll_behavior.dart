import 'package:flutter/material.dart';

/// Keeps scrollbars off every scrollable in the app.
///
/// Flutter draws a scrollbar by itself on desktop and in the browser, and on
/// the narrow app column the frame puts the app in, those bars sat on top of
/// cards and cut a dark strip down the right edge of the game. A phone build
/// has no scrollbar at all; this makes the web build match it.
///
/// Scrolling itself is unchanged - wheel, trackpad, drag and keyboard all still
/// work, and the touch overscroll glow is kept.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
