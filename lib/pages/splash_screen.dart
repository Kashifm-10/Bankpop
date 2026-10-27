import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  /// The build the player is running, shown quietly under the animation. The
  /// home screen used to carry it; the splash is where a launch can be
  /// identified, and the profile repeats it for a report.
  String _version = '';

  /// The story belongs to a cold start. In the browser `/` is also somewhere
  /// the back button can land, and making the player watch three seconds of it
  /// again on the way back from a game is not a launch - so the wait only
  /// happens once per session.
  static bool _shown = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    final Duration wait = _shown ? Duration.zero : const Duration(seconds: 3);
    _shown = true;
    _timer = Timer(wait, () async {
      // A hot reload (or a very fast back gesture) can tear this screen down
      // before the timer fires; navigating from a disposed state throws.
      if (!mounted) return;
      // The story is only a first-run screen. Signing in is optional, so an
      // account is not what decides this: a device that has seen the story
      // (with or without an account) goes straight to its games, and a guest's
      // games are right there too.
      final bool signedIn = await Account.isSignedIn();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool onboarded = prefs.getBool(Account.onboardingDoneKey) ?? false;
      // A temporary password only buys a session: choose a real one first,
      // even if the app was closed in between.
      final bool mustChangePassword = await Account.passwordChangeRequired();
      if (!mounted) return;

      // `pushReplacement`, not `go`: the splash is not a place the back button
      // should be able to return to - a launch should leave the app, not show
      // the story again.
      if (mustChangePassword) {
        context.pushReplacement(AppRoutes.setPassword);
      } else {
        context.pushReplacement(
          signedIn || onboarded ? AppRoutes.home : AppRoutes.onboarding,
        );
      }
    });
  }

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.buildNumber.isEmpty
            ? 'Version ${info.version}'
            : 'Version ${info.version} (${info.buildNumber})';
      });
    } catch (error) {
      // A platform without package info simply shows no label.
      debugPrint('Could not read the version: $error');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.yellow.shade50,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'assets/lottie/splash.json',
              height: 50.h,
            ),
            if (_version.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _version,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w300,
                    color: const Color(0xFF558B2F),
                  ),
                ),
              ),
/*             const SizedBox(height: 20),
            const CircularProgressIndicator(color: Colors.white),
           */
          ],
        ),
      ),
    );
  }
}
