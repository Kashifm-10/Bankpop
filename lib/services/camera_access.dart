import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the camera has already been allowed on this device.
///
/// A browser remembers the decision for the site, but a page cannot reliably ask
/// it what that decision was, so the first successful start is remembered here.
/// The scanner's "turn the camera on" panel is then a first-run screen instead
/// of something every scan has to click through.
///
/// On Android and iOS the camera needs no tap at all, so it is always on.
class CameraAccess {
  CameraAccess._();

  static const String _key = 'camera_granted';

  static bool? _granted;

  static Future<bool> isGranted() async {
    if (!kIsWeb) return true;
    final bool? cached = _granted;
    if (cached != null) return cached;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool granted = prefs.getBool(_key) ?? false;
    _granted = granted;
    return granted;
  }

  /// Called when the player has just started the camera themselves, which means
  /// they answered the browser's prompt. Everything after that starts silently.
  static Future<void> remember() async {
    _granted = true;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  /// Called when a start failed - a revoked permission has to be asked for
  /// again, with the explanation panel in front of it.
  static Future<void> forget() async {
    _granted = false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
