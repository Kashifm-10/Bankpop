import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/pages/auth/auth_screen.dart';
import 'package:mon/pages/home.dart';
import 'package:mon/services/account.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

/// What a new install (or a browser with no account) sees first.
///
/// Three panels explain what the app is and what an account is for. The last
/// one offers both ways in: start playing as a guest straight away, or sign in
/// so the games follow the player to another device. An account is a bonus, not
/// a gate.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_Slide> _slides = <_Slide>[
    _Slide(
      lottie: 'assets/lottie/bank_role.json',
      title: 'Bankpop',
      body: 'The banker keeps the money, the players keep playing. No paper '
          'bills, no missing coins - just tap and play.',
    ),
    _Slide(
      lottie: 'assets/lottie/scan.json',
      title: 'Pay by scanning',
      body:
          'ScanPay games settle rent and purchases with a QR code. InstantPay '
          'games keep a running balance you can settle by hand.',
    ),
    _Slide(
      lottie: 'assets/lottie/player_role.json',
      title: 'Play now, sign in later',
      body: 'No account needed to play - start as a guest and your games are '
          'kept on this device. Sign in when you want them to follow you to a '
          'new phone, a reinstall or a browser.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The default way in: a guest. The name/avatar dialog on the home screen
  /// creates the local player, and no email is ever asked for.
  Future<void> _playAsGuest() async {
    await Account.markOnboarded();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const WelcomePage()),
    );
  }

  /// The optional way in: an account, so the games are not tied to this device.
  Future<void> _signIn() async {
    await Account.markOnboarded();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
    );
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  bool get _isLast => _page >= _slides.length - 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (int page) => setState(() => _page = page),
                itemBuilder: (BuildContext context, int index) {
                  final _Slide current = _slides[index];
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          height: 34.h,
                          child: Lottie.asset(
                            current.lottie,
                            fit: BoxFit.contain,
                            repeat: true,
                          ),
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          current.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF33691E),
                            letterSpacing: 1.1,
                          ),
                        ),
                        SizedBox(height: 1.5.h),
                        Text(
                          current.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16.sp,
                            height: 1.35,
                            color: const Color(0xFF558B2F),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_slides.length, (int index) {
                final bool selected = index == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: selected ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF689F38)
                        : const Color(0xFFC5E1A5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            SizedBox(height: 3.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLast ? _playAsGuest : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF689F38),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _isLast ? 'Start playing' : 'Next',
                    style:
                        TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            // An account is optional, so the guest path is the button and the
            // account is the alternative underneath it.
            TextButton(
              onPressed: _isLast ? _signIn : _playAsGuest,
              child: Text(
                _isLast ? 'Sign in or create an account' : 'Skip for now',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ),
            SizedBox(height: 2.h),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.lottie,
    required this.title,
    required this.body,
  });

  final String lottie;
  final String title;
  final String body;
}
