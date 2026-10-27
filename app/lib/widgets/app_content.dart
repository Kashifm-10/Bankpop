import 'package:flutter/material.dart';

/// The three window shapes the layouts are built for.
///
/// A screen is not a phone stretched sideways: below [medium] everything is one
/// column, between [medium] and [wide] the columns get room, and at [wide] the
/// screen can put two groups of things side by side.
abstract final class AppLayout {
  static const double mediumWidth = 700;
  static const double wideWidth = 1000;

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  /// A phone, in either orientation.
  static bool isCompact(BuildContext context) =>
      widthOf(context) < mediumWidth;

  /// A tablet, or a small browser window.
  static bool isMedium(BuildContext context) =>
      widthOf(context) >= mediumWidth && widthOf(context) < wideWidth;

  /// A desktop browser window, or a tablet in landscape.
  static bool isWide(BuildContext context) => widthOf(context) >= wideWidth;

  /// The margin at the side of the content column.
  static double gutter(BuildContext context) {
    if (isCompact(context)) return 16;
    if (isMedium(context)) return 24;
    return 32;
  }
}

/// The readable column a screen's content is drawn in.
///
/// The window is filled by the Scaffold (and whatever background it paints),
/// while the content itself keeps a comfortable measure and stays centred. A
/// list, a form or a board inside this is as wide as [maxWidth] on a desktop
/// and edge-to-edge minus the gutter on a phone.
class AppContent extends StatelessWidget {
  const AppContent({
    super.key,
    required this.child,
    this.maxWidth = 1000,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;

  /// The widest the content gets. Forms read best around 640-720, game screens
  /// want 1000, and a board screen can take 1200.
  final double maxWidth;

  /// Extra padding inside the gutters, for a screen that needs its own top or
  /// bottom space.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final double gutter = AppLayout.gutter(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter).add(padding),
          child: child,
        ),
      ),
    );
  }
}
