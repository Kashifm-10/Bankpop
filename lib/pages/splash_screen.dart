import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/pages/auth/onboarding_screen.dart';
import 'package:mon/pages/home.dart';
import 'package:mon/services/account.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), () async {
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
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => signedIn || onboarded
              ? const WelcomePage()
              : const OnboardingScreen(),
        ),
      );
    });
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
/*             const SizedBox(height: 20),
            const CircularProgressIndicator(color: Colors.white),
           */
          ],
        ),
      ),
    );
  }
}
