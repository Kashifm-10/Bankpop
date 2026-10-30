import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/app_metrics.dart';

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

  /// The only way on: the account screen, where the player signs in, creates
  /// an account, or chooses the guest path deliberately.
  ///
  /// The story used to drop a guest straight onto the home screen, which left
  /// the account screen reachable only from a banner - so a player who wanted
  /// an account had to find it after the fact. Both the last slide and the skip
  /// link land here instead.
  Future<void> _continue() async {
    await Account.markOnboarded();
    if (!mounted) return;
    // `go`, not `push`: the story is finished, and the back button should walk
    // back through the account screen, not into the slides again.
    context.go(AppRoutes.auth);
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
        // The slides are a phone-shaped story: on a desktop window the copy
        // keeps a readable measure instead of running across the screen.
        child: AppContent(
          maxWidth: 600,
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
                  onPressed: _isLast ? _continue : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF689F38),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _isLast ? 'Get started' : 'Next',
                    style:
                        TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            // The skip link is for the slides, not for the account screen: a
            // player who skips lands on the same choice everyone else gets.
            if (!_isLast)
              TextButton(
                onPressed: _continue,
                child: Text(
                  'Skip for now',
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
