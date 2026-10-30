import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/app_metrics.dart';

/// The cover of the app: what a brand new install sees once the splash is over,
/// before the three-slide introduction.
///
/// The introduction used to be the first thing after the splash, which meant a
/// new player was reading panels before they had seen the name of the game.
/// This is a title page instead - the logo, the name, three lines about what
/// the app does - and the whole page is the button: a tap opens the story.
///
/// It is a first-run screen only. [Account.welcomeDoneKey] records that the
/// cover was tapped, so a player who reopens the app goes straight to their
/// games (or to the story, if they never finished that).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  /// Guards against a double tap opening the story twice: the tap marks the
  /// screen as seen before it navigates, and two `go`s in the same frame would
  /// push two copies of the onboarding flow.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The only way forward: record the cover as seen, then open the story.
  ///
  /// `go`, not `push`: the back button should walk back through the story, not
  /// return to this cover.
  Future<void> _begin() async {
    if (_leaving) return;
    _leaving = true;
    await Account.markWelcomeSeen();
    if (!mounted) return;
    context.go(AppRoutes.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        // `opaque` so the empty space around the copy is tappable too - the
        // hint says "anywhere", so anywhere has to work.
        behavior: HitTestBehavior.opaque,
        onTap: _begin,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[Color(0xFFFFFDF7), Color(0xFFFFF1CC)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: AppContent(
              maxWidth: 560,
              child: Column(
                children: <Widget>[
                  const Spacer(flex: 3),
                  _logo(),
                  SizedBox(height: 3.h),
                  Text(
                    'BankPop',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 44.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      height: 1.05,
                      color: const Color(0xFF33691E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The board game your phone pays for.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: const Color(0xFF7CB342),
                    ),
                  ),
                  SizedBox(height: 3.5.h),
                  _highlights(),
                  const Spacer(flex: 4),
                  _tapHint(),
                  SizedBox(height: 2.5.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The app's own rounded icon on a soft plate, so the cover matches the
  /// launcher icon instead of showing a different mark.
  Widget _logo() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Image.asset(
          'assets/images/app_icon_rounded_logo.png',
          width: 28.w > 150 ? 150 : 28.w,
          height: 28.w > 150 ? 150 : 28.w,
          fit: BoxFit.cover,
          // A build without the icon (a plain widget test, an odd platform)
          // still shows the cover, with the game's own money-green plate.
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stack) =>
                  Container(
            width: 28.w > 150 ? 150 : 28.w,
            height: 28.w > 150 ? 150 : 28.w,
            color: const Color(0xFF689F38),
            alignment: Alignment.center,
            child: const Icon(Icons.attach_money_rounded,
                size: 64, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// Three lines about the app, as chips rather than paragraphs: the story on
  /// the next screen explains them, this page only has to say what it is.
  Widget _highlights() {
    const List<(IconData, String)> items = <(IconData, String)>[
      (Icons.qr_code_scanner, 'Scan to pay'),
      (Icons.receipt_long_outlined, 'Every move recorded'),
      (Icons.people_alt_outlined, 'Play with friends'),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final (IconData icon, String label) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFE8DDBB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 15, color: const Color(0xFF689F38)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A5A3A),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The invitation. It breathes so the page does not look like a static poster,
  /// and the arrow points at the only action there is.
  Widget _tapHint() {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF689F38),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33689F38),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Flexible, not a bare Text: at a large accessibility text size
                // (or on a very narrow window) the label wraps under the arrow
                // instead of pushing the pill past the edge of the screen.
                Flexible(
                  child: Text(
                    'Tap anywhere to begin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    size: 20, color: Colors.white),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'A quick tour comes next - about twenty seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Color(0xFF8D9B7E)),
          ),
        ],
      ),
    );
  }
}
