import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomTheme {
  /// The one typeface the whole app is set in.
  ///
  /// Quicksand was already the light theme's family, while the dark theme asked
  /// for Montserrat Subrayada - an all-caps display face - so the type changed
  /// whenever the room got dark. One family now, in both, and in the dialog
  /// styles that used to spell their own out.
  static String get family => GoogleFonts.quicksand().fontFamily ?? 'Quicksand';

  /// Quicksand, weighted so the scale reads as one system: display and titles
  /// carry the emphasis, body copy stays legible rather than hairline, and
  /// labels sit a step under titles. Quicksand's strokes are thin at 400, which
  /// is why body text is 500 and small labels are not lighter than that.
  static TextTheme textThemeFor(Brightness brightness) {
    final TextTheme base = GoogleFonts.quicksandTextTheme(
      ThemeData(brightness: brightness).textTheme,
    );
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w800),
      displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w800),
      displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
      headlineMedium:
          base.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      bodyMedium: base.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      bodySmall: base.bodySmall?.copyWith(fontWeight: FontWeight.w500),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  static ThemeData lightThemeData() {
    return ThemeData(
      fontFamily: family,
      textTheme: textThemeFor(Brightness.light),
      colorScheme: MaterialTheme.lightScheme().toColorScheme(),
      scaffoldBackgroundColor: MaterialTheme.lightScheme().background,
      useMaterial3: true,
      // Every dialog in the app is drawn from this one definition: the cream
      // card, the round corner and the green title. Screens that used to set
      // their own grey / pale yellow background now inherit it, so a dialog
      // looks the same whichever screen opened it.
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFFFF8E1),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF33691E),
          fontFamily: family,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14.5,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF33691E),
          fontFamily: family,
        ),
      ),
      // Dialog actions (Cancel / Continue) used to come out in the scheme's
      // blue while the dialog around them was green. One green action colour
      // instead, with the weight of a button rather than a link.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF2E7D32),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static ThemeData darkThemeData() {
    return ThemeData(
      fontFamily: family,
      textTheme: textThemeFor(Brightness.dark),
      colorScheme: MaterialTheme.darkScheme().toColorScheme(),
      scaffoldBackgroundColor: MaterialTheme.darkScheme().background,
      useMaterial3: true,
      // Same shape and weight as the light theme, on a card that belongs in a
      // dark room rather than a white flash.
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF26291F),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFC5E1A5),
          fontFamily: family,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14.5,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: const Color(0xFFE0E0E0),
          fontFamily: family,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF9CCC65),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  /// Light color scheme
  static MaterialScheme lightScheme() {
    return const MaterialScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1565C0),
      surfaceTint: Color(0xFF1565C0),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD6E4FF),
      onPrimaryContainer: Color(0xFF001A40),
      secondary: Color(0xFF455A64),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFDCE4E8),
      onSecondaryContainer: Color(0xFF0F1C22),
      tertiary: Color(0xFF00897B),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFF64FFDA),
      onTertiaryContainer: Color(0xFF00201A),
      error: Color(0xFFB00020),
      onError: Colors.white,
      background: Color(0xFFFFF8E1),
      onBackground: Color(0xFF1B1B1B),
      surface: Color(0xFFF9F9F9),
      onSurface: Color(0xFF1B1B1B),
      surfaceVariant: Color(0xFFE0E0E0),
      onSurfaceVariant: Color(0xFF49454F),
      outline: Color(0xFF79747E),
      outlineVariant: Color(0xFFCAC4D0),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF2F3033),
      inverseOnSurface: Color(0xFFF1F0F4),
      inversePrimary: Color(0xFF90CAF9),
      surfaceDim: Color(0xFFEDEDED),
      surfaceBright: Color(0xFFFFFFFF),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF5F5F5),
      surfaceContainer: Color(0xFFF0F0F0),
      surfaceContainerHigh: Color(0xFFECECEC),
      surfaceContainerHighest: Color(0xFFE6E6E6),
    );
  }

  /// Dark color scheme
  static MaterialScheme darkScheme() {
    return const MaterialScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF90CAF9),
      surfaceTint: Color(0xFF90CAF9),
      onPrimary: Color(0xFF003063),
      primaryContainer: Color(0xFF003C8F),
      onPrimaryContainer: Color(0xFFD6E4FF),
      secondary: Color(0xFFB0BEC5),
      onSecondary: Color(0xFF1C313A),
      secondaryContainer: Color(0xFF37474F),
      onSecondaryContainer: Color(0xFFDCE4E8),
      tertiary: Color(0xFF4DB6AC),
      onTertiary: Color(0xFF00201A),
      tertiaryContainer: Color(0xFF00695C),
      onTertiaryContainer: Color(0xFF64FFDA),
      error: Color(0xFFCF6679),
      onError: Color(0xFF370617),
      background: Color(0xFF121212),
      onBackground: Color(0xFFE0E0E0),
      surface: Color(0xFF121212),
      onSurface: Color(0xFFE0E0E0),
      surfaceVariant: Color(0xFF49454F),
      onSurfaceVariant: Color(0xFFCAC4D0),
      outline: Color(0xFF938F99),
      outlineVariant: Color(0xFF49454F),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE6E6E6),
      inverseOnSurface: Color(0xFF2F3033),
      inversePrimary: Color(0xFF1565C0),
      surfaceDim: Color(0xFF1E1E1E),
      surfaceBright: Color(0xFF2C2C2C),
      surfaceContainerLowest: Color(0xFF0F0F0F),
      surfaceContainerLow: Color(0xFF1A1A1A),
      surfaceContainer: Color(0xFF242424),
      surfaceContainerHigh: Color(0xFF2F2F2F),
      surfaceContainerHighest: Color(0xFF3A3A3A),
    );
  }
}

/// Extension to convert [MaterialScheme] to Flutter's [ColorScheme]
extension SchemeToColorScheme on MaterialScheme {
  ColorScheme toColorScheme() {
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      error: error,
      onError: onError,
      // `background`/`onBackground` are deprecated aliases of surface/onSurface,
      // which are set from their own fields just below.
      surface: surface,
      onSurface: onSurface,
      // `surfaceVariant` was renamed; the colour is unchanged.
      surfaceContainerHighest: surfaceVariant,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      shadow: shadow,
      inverseSurface: inverseSurface,
      inversePrimary: inversePrimary,
      surfaceTint: surfaceTint,
      outlineVariant: outlineVariant,
      scrim: scrim,
    );
  }
}

/// A data class representing the full Material 3 color scheme
class MaterialScheme {
  final Brightness brightness;
  final Color primary;
  final Color surfaceTint;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color error;
  final Color onError;
  final Color background;
  final Color onBackground;
  final Color surface;
  final Color onSurface;
  final Color surfaceVariant;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color shadow;
  final Color scrim;
  final Color inverseSurface;
  final Color inverseOnSurface;
  final Color inversePrimary;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  const MaterialScheme({
    required this.brightness,
    required this.primary,
    required this.surfaceTint,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.background,
    required this.onBackground,
    required this.surface,
    required this.onSurface,
    required this.surfaceVariant,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.shadow,
    required this.scrim,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.inversePrimary,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
  });
}
