import 'dart:math' as math;

import 'package:responsive_sizer/responsive_sizer.dart';

/// The sizing layer every screen uses, on the real window.
///
/// Two things are deliberately not the raw window:
///
///  * `.w` is a percentage of at most [_designWidth]. The screens are full of
///    `80.w` dialogs and `50.w` buttons; on a 1920 px browser window those would
///    be 1536 and 960 px wide and overflow the centred content column. Capping
///    the percentage keeps them proportional to the column the app actually
///    draws in, so the same numbers work on a phone, a tablet and a desktop.
///  * `.sp` grows with the window's *short side*, capped, instead of the
///    package's quadratic width x height - which turned 12 px labels into 47 px
///    sentences on a desktop while a button only grew once.
///
/// Every screen imports this file with the package's `DeviceExt` hidden (see
/// `AppFrame`), so `.w`, `.h` and `.sp` everywhere mean these.
extension AppSizing on num {
  /// Percent of the design width - the window's width, up to a sensible column.
  double get w => this * math.min(Device.width, _designWidth) / 100;

  /// Percent of the window's height.
  double get h => this * Device.height / 100;

  /// Percent of the safe-area width, on the same design width.
  double get sw => this * math.min(Device.safeWidth, _designWidth) / 100;

  /// Percent of the safe-area height.
  double get sh => this * Device.safeHeight / 100;

  /// A text size in logical pixels, scaled gently with the screen.
  double get sp => this * textScale;

  /// Widest column a percentage is measured against. Wide enough for the
  /// largest dialog (`90.w`) and the game screens, narrow enough that a
  /// percentage cannot run away on an ultrawide monitor.
  static const double _designWidth = 1000;

  /// The phone the layouts were drawn on: 390 logical px on its short edge.
  static const double _designShortestSide = 390;

  /// Small phones are not shrunk past this, so text stays legible.
  static const double _minScale = 0.85;

  /// Past this, a bigger window gets more room rather than bigger text.
  static const double _maxScale = 1.2;

  /// How much larger text is than the design, from the window's short side.
  static double get textScale {
    final double shortest =
        math.min(Device.width, Device.height).clamp(240.0, 100000.0);
    return (shortest / _designShortestSide).clamp(_minScale, _maxScale);
  }
}
