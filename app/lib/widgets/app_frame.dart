import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

/// Fills the sizing layer (`20.w`, `12.h`, `18.sp` from responsive_sizer) with
/// the window the app was actually given.
///
/// It used to clamp every screen into a 560 px phone-shaped column and centre
/// it over a gradient, so a desktop browser showed a phone floating in a
/// backdrop. Every screen here is built from percentages of the window, so the
/// honest fix is to hand those percentages the real window: a wide window gets
/// a wide layout, a tall one a tall layout, and the app fills the screen.
///
/// The one thing kept from the old frame is the guard against a zero-sized
/// window (a hidden browser tab, the first frame of a resize), which would
/// divide by zero in every percentage.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child});

  final Widget child;

  /// Below this the platform itself is unusable, but it keeps the sizing layer
  /// from ever dividing by zero.
  static const double minSide = 200;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final Size window = media.size;
    final double width = window.width < minSide ? minSide : window.width;
    final double height = window.height < minSide ? minSide : window.height;

    _applyMetrics(
      context,
      width: width,
      height: height,
    );

    // The window is already what MediaQuery reports, so the app tree needs no
    // override: dialogs, sheets and the board all size against the same screen
    // the pages fill.
    return child;
  }

  /// Fills in the static metrics responsive_sizer's `.w`/`.h`/`.sp` read, from
  /// the real window.
  static void _applyMetrics(
    BuildContext context, {
    required double width,
    required double height,
  }) {
    final MediaQueryData media = MediaQuery.of(context);
    final double safeWidth = width - media.viewPadding.horizontal;
    final double safeHeight = height - media.viewPadding.vertical;

    Device.boxConstraints = BoxConstraints.loose(Size(width, height));
    Device.width = width;
    Device.height = height;
    Device.safeWidth = safeWidth > 0 ? safeWidth : width;
    Device.safeHeight = safeHeight > 0 ? safeHeight : height;
    Device.aspectRatio = height / width;
    Device.pixelRatio = media.devicePixelRatio;
    Device.orientation =
        width > height ? Orientation.landscape : Orientation.portrait;
    // The layouts are the phone's at every size - they scroll and grow rather
    // than switching to a different widget tree - so the breakpoint only
    // describes the window.
    Device.screenType = width >= 1000
        ? ScreenType.desktop
        : (width >= 600 ? ScreenType.tablet : ScreenType.mobile);
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
