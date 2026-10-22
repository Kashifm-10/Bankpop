import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

/// Keeps the app in a single, phone-shaped column and centres it on anything
/// wider than a phone.
///
/// The screens are built from percentages of the available size
/// (`40.w`, `12.h`, `18.sp` from responsive_sizer), which were tuned for a
/// portrait phone. Handing those percentages a 1280 px desktop window would
/// stretch every card and dialog across the whole window; handing them a
/// tablet's full width would do the same. Handing them a short landscape
/// window (400 px) collapses `12.h` to 48 px and clips buttons.
///
/// This frame therefore gives the sizing layer a *design* size rather than the
/// raw window: width is clamped to a phone/tablet column, and height to a
/// range where the layouts still read correctly. The widgets still lay out in
/// the real window; only the numbers behind `.w`/`.h`/`.sp` come from the
/// clamped design size. `MediaQuery.size` is overridden as well so anything
/// that reads it (dialogs, the board popup) agrees with the column.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child});

  final Widget child;

  /// A phone in portrait is 320-480 logical px wide. 560 leaves tablets a
  /// little extra room without turning a card into a billboard.
  static const double maxContentWidth = 560;

  /// Below this the platform itself is unusable, but it keeps the clamp from
  /// ever producing a negative or zero width.
  static const double minContentWidth = 240;

  /// Shortest design height. A 400 px landscape phone would otherwise scale
  /// every vertical percentage down by half and clip text inside its buttons;
  /// at 600 the layout is a compact phone that scrolls.
  static const double minDesignHeight = 600;

  /// Tallest design height, so a 1280 px tablet does not spread a phone layout
  /// over twice the vertical space it was drawn for.
  static const double maxDesignHeight = 940;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final ThemeData theme = Theme.of(context);

    // The window comes from MediaQuery, not a LayoutBuilder. A LayoutBuilder
    // callback runs *during layout*, and rebuilding the app's Navigator from
    // there while a route is animating trips the Navigator's
    // `!_debugLocked` assertion - which is exactly what happened when a dialog
    // opened on a narrow window. MediaQuery already delivers the same numbers,
    // as an ordinary build-time dependency.
    final double windowWidth = media.size.width;
    final double windowHeight = media.size.height;
    final double contentWidth =
        windowWidth.clamp(minContentWidth, maxContentWidth);
    final double designHeight = windowHeight.clamp(
      minDesignHeight,
      maxDesignHeight,
    );
    final bool centred = contentWidth < windowWidth - 0.5;

    _applyMetrics(
      context,
      width: contentWidth,
      height: designHeight,
    );

    final MediaQueryData framed = media.copyWith(
      // Dialogs size themselves from this, so they stay inside the column
      // instead of spanning a desktop window. Height is the real height: a
      // dialog taller than the window is unusable.
      size: Size(contentWidth, windowHeight),
    );

    final Widget app = MediaQuery(data: framed, child: child);

    if (!centred) return app;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // A quiet, branded backdrop so the centred app reads as a deliberate
          // panel rather than a phone floating in empty space.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[Color(0xFFF1F8E9), Color(0xFFDCEDC8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: Container(
              width: contentWidth,
              height: windowHeight,
              decoration: BoxDecoration(
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRect(child: app),
            ),
          ),
        ],
      ),
    );
  }

  /// Fills in the static metrics responsive_sizer's `.w`/`.h`/`.sp` read.
  ///
  /// Normally `ResponsiveSizer` computes these from its own constraints, but it
  /// has no way to cap them — and it is the cap this frame exists for. The
  /// fields are public, so setting them here is the same contract the package
  /// widget implements, with a design size instead of the raw window.
  static void _applyMetrics(
    BuildContext context, {
    required double width,
    required double height,
  }) {
    final MediaQueryData media = MediaQuery.of(context);

    Device.boxConstraints = BoxConstraints.tightFor(
      width: width,
      height: height,
    );
    Device.width = width;
    Device.height = height;
    Device.safeWidth = width;
    Device.safeHeight = height;
    Device.aspectRatio = height / width;
    Device.pixelRatio = media.devicePixelRatio;
    Device.orientation =
        width > height ? Orientation.landscape : Orientation.portrait;
    Device.screenType = ScreenType.mobile;
    Device.deviceType = switch (defaultTargetPlatform) {
      TargetPlatform.android => DeviceType.android,
      TargetPlatform.iOS => DeviceType.ios,
      TargetPlatform.macOS => DeviceType.mac,
      TargetPlatform.windows => DeviceType.windows,
      TargetPlatform.linux => DeviceType.linux,
      TargetPlatform.fuchsia => DeviceType.fuchsia,
    };
    if (kIsWeb) Device.deviceType = DeviceType.web;
  }
}
