import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mon/widgets/app_metrics.dart';

/// What a browser shows before it opens the camera.
///
/// Browsers only hand over the camera in response to a user action, and Safari
/// on iOS will not even prompt without one. A scanner that starts itself on
/// navigation works on Android but silently stays black there, so the web build
/// asks first - and offers the typed code as an equal option.
class ScannerStartView extends StatelessWidget {
  const ScannerStartView({
    super.key,
    required this.title,
    required this.body,
    required this.onStart,
    this.onManualEntry,
    this.manualLabel = 'Enter code instead',
  });

  final String title;
  final String body;
  final VoidCallback onStart;
  final VoidCallback? onManualEntry;
  final String manualLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1B1B1B),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.qr_code_scanner, color: Colors.white70, size: 56),
            SizedBox(height: 2.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 19.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 1.h),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14.sp,
                height: 1.35,
              ),
            ),
            SizedBox(height: 3.h),
            ElevatedButton.icon(
              onPressed: onStart,
              icon: Image.asset(
                'assets/Icons/camera.png',
                width: 20,
                height: 20,
                fit: BoxFit.contain,
              ),
              label: const Text('Turn on camera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF689F38),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (onManualEntry != null) ...<Widget>[
              SizedBox(height: 1.h),
              TextButton(
                onPressed: onManualEntry,
                child: Text(
                  manualLabel,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What a scanner shows when the camera cannot be used.
///
/// This is the same on every platform, with one difference that matters: in a
/// browser the usual cause is a blocked permission or an insecure page, not a
/// broken camera. Saying which one it is saves the player from staring at a
/// black rectangle.
class ScannerErrorView extends StatelessWidget {
  const ScannerErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.onManualEntry,
    this.manualLabel = 'Enter code instead',
  });

  final MobileScannerException error;
  final VoidCallback onRetry;

  /// When the screen has another way in (a join code), offer it here: a desktop
  /// browser without a webcam should still be able to join a game.
  final VoidCallback? onManualEntry;
  final String manualLabel;

  String get _message {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return kIsWeb
            ? 'Camera access was blocked. Allow the camera for this site in '
                'your browser, then try again.'
            : 'Camera access was blocked. Allow the camera for Bankpop in '
                'Settings, then try again.';
      case MobileScannerErrorCode.unsupported:
        return kIsWeb
            ? 'This browser has no usable camera. Enter the code instead.'
            : 'This device has no camera the app can use.';
      default:
        return kIsWeb
            ? 'The camera could not be started. Browsers only allow it on a '
                'secure page (https:// or localhost), and only after you allow '
                'it.'
            : 'The camera could not be started. Close any other app using it '
                'and try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1B1B1B),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.no_photography_outlined,
                color: Colors.white70, size: 52),
            SizedBox(height: 2.h),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15.sp,
                height: 1.35,
              ),
            ),
            SizedBox(height: 3.h),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: <Widget>[
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Try again'),
                ),
                if (onManualEntry != null)
                  ElevatedButton(
                    onPressed: onManualEntry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF689F38),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(manualLabel),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
