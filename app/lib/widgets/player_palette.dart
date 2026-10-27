import 'package:flutter/material.dart';

/// The colour a player is drawn in.
///
/// The roster, the player rows and the board's owner badges all read this, so a
/// player's circle on the board is the same colour as their name in the
/// leaderboard. It is derived from the name because that is what the roster has
/// always used; the name is unique within a game (the join already refuses a
/// duplicate), so two seats cannot share a colour.
abstract final class PlayerPalette {
  static Color forName(String name) =>
      Colors.primaries[name.hashCode % Colors.primaries.length];

  /// A darker shade of the same colour, for text drawn on the light background.
  static Color inkForName(String name) {
    final HSLColor hsl = HSLColor.fromColor(forName(name));
    return hsl.withLightness((hsl.lightness * 0.55).clamp(0.0, 1.0)).toColor();
  }
}
