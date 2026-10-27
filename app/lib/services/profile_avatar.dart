import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The avatar a player picked on their profile.
///
/// The choice is stored as the asset path of one of the bundled avatars rather
/// than as a copy in the app's documents directory. The web build has no file
/// system, so a file path saved on Android could not be read there — and
/// copying a bundled image to disk was only ever a round trip. Every screen
/// that used to draw a `FileImage` now draws the asset directly, which works
/// on Android, iOS and the web alike.
class ProfileAvatar {
  ProfileAvatar._();

  /// Drawn when the player has not picked one of the bundled avatars.
  static const String appIcon = 'assets/images/play_icon.jpg';

  /// The bundled avatars, in the order the profile dialog lays them out.
  static const List<String> choices = <String>[
    'assets/avatars/girl1.jpg',
    'assets/avatars/girl2.jpg',
    'assets/avatars/girl3.jpg',
    'assets/avatars/girl4.jpg',
    'assets/avatars/girl5.jpg',
    'assets/avatars/girl6.jpg',
    'assets/avatars/girl7.jpg',
    'assets/avatars/boy1.jpg',
    'assets/avatars/boy2.jpg',
    'assets/avatars/boy3.jpg',
    'assets/avatars/boy4.jpg',
    'assets/avatars/boy5.jpg',
    'assets/avatars/boy6.jpg',
    'assets/avatars/boy7.jpg',
  ];

  /// The avatar saved on this device, falling back to the app icon.
  static String saved(SharedPreferences prefs) {
    final String? path = prefs.getString('avatar_path');
    if (path == null || path.isEmpty) return appIcon;
    return path;
  }

  /// A memory-cheap image provider: the sources are 500-1200 px square and are
  /// drawn at 50-120 px, so [cacheWidth] keeps the decoded bitmap small.
  static ImageProvider provider(String asset, {int? cacheWidth}) {
    final AssetImage image = AssetImage(asset);
    if (cacheWidth == null) return image;
    return ResizeImage(image, width: cacheWidth);
  }

  /// Writes the picked avatar to prefs. [index] is kept so the profile dialog
  /// opens with the same avatar highlighted next time.
  static Future<void> save(
    SharedPreferences prefs, {
    required String asset,
    required int index,
  }) async {
    await prefs.setString('avatar_path', asset);
    await prefs.setInt('selected_avatar_index', index);
    // Older builds copied the avatar to a file and stored that path here. It
    // is no longer read anywhere, and leaving it behind would make an old
    // file path look like live state.
    await prefs.remove('profile_image');
  }
}
