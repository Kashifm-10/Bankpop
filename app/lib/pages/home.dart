import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:mon/pages/how_to_use_screen.dart';
import 'package:mon/pages/profile_edit.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/services/profile_avatar.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final supabase = Supabase.instance.client;

  /// The bundled avatar this device picked, or the app icon. It is an asset
  /// path rather than a file, so the same value renders on Android and web.
  String _avatarAsset = ProfileAvatar.appIcon;
  String userName = "";

  /// An account is optional: a guest gets the whole app, and this only decides
  /// whether the greeting carries the "sign in to keep your games" banner.
  bool _signedIn = false;

  /// Reopening the last game is what a launch does, not what every return to
  /// the home screen does. Without this, the browser's back button from a game
  /// would land on the splash, which lands here, which would push the player
  /// straight back into the game.
  static bool _autoResumeHandled = false;

  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool signedIn = await Account.isSignedIn();
    if (mounted && signedIn != _signedIn) {
      setState(() => _signedIn = signedIn);
    }
    _avatarAsset = ProfileAvatar.saved(prefs);
    userName = prefs.getString('profile_name') ?? "";
    // The board this device is part-way through, so anything that reads the
    // board before a game screen opens draws the right country.
    final String? gameId = prefs.getString('gameID');
    if (gameId != null && gameId.isNotEmpty) {
      final GameSession? session = await GameSession.fetch(gameId);
      BoardCatalog.use(session?.boardId);
    }
    if (userName.isNotEmpty) {
      await _loadUser();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkForPlayerAndNavigate();
      });
    } else {
      bool? updated = await showDialog(
        context: context,
        barrierDismissible: false, // disables tap outside to dismiss
        builder: (context) => PopScope(
          // Back button disabled: the profile has to be completed first.
          canPop: false,
          child: const ProfileDialog(
            first: true,
            prevIndex: 0,
          ),
        ),
      );

      if (updated == true) {
        await _loadUser();

        // Reload UI after changes
        setState(() {});
      }
    }
  }

  Future<void> _loadUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _avatarAsset = ProfileAvatar.saved(prefs);
      userName = prefs.getString('profile_name') ?? "Your Name";
    });
  }

  Future<void> _checkForPlayerAndNavigate() async {
    if (_autoResumeHandled) return;
    showLoadingDialog(context, 'Loading...');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? playerID = prefs.getString('playerID');
    final String? gameID = prefs.getString('gameID');

    // Nothing stored to continue: a fresh install mid-upgrade, or a pref that
    // was cleared elsewhere. Say nothing and leave the home screen as it is.
    if (playerID == null ||
        playerID.isEmpty ||
        gameID == null ||
        gameID.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      // A finished game must not pull the player back into it on launch. The
      // stored id is cleared so the home screen simply asks what to play next.
      final GameSession? session = await GameSession.fetch(gameID);
      BoardCatalog.use(session?.boardId);
      if (session != null && session.isEnded) {
        await prefs.remove('gameID');
        if (mounted) Navigator.pop(context);
        return;
      }
      // One round trip instead of two sequential ones: read this device's rows
      // once and pick the role locally, with banker taking precedence.
      final response = await supabase
          .from('players_test')
          .select()
          .eq('game_id', gameID)
          .eq('player_id', playerID)
          .limit(10);

      final rows = response as List<dynamic>;
      final isBanker = rows.any((row) => row['role'] == 'banker');
      final isPlayer = rows.any((row) => row['role'] == 'player');

      // A player the banker removed stays on the home screen: their seat is
      // gone, and the REMOVED badge on the banker's list is all that is left of
      // them in that game. The role check is deliberately not here: a project
      // without player_status.sql marks a removal with role = 'kicked', and
      // that row has to be recognised just the same.
      final bool removed = rows.any((dynamic raw) {
        final Map<String, dynamic> row = (raw as Map).cast<String, dynamic>();
        return PlayerStanding.fromRow(row) == PlayerStanding.kicked;
      });
      if (removed) {
        await prefs.remove('gameID');
        if (mounted) Navigator.pop(context);
        return;
      }
      // A row that is neither banker nor player is not a seat in this game.
      if (!isBanker && !isPlayer) {
        if (mounted) Navigator.pop(context);
        return;
      }

      // Close the loading box first; replacing the location while it is open
      // would leave it behind on the game screen.
      Navigator.pop(context);
      _autoResumeHandled = true;
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        // `go` rather than push: the lobby is not somewhere the back button
        // should return to once the game is open.
        context.go(
          isBanker ? AppRoutes.banker(gameID) : AppRoutes.player(gameID),
        );
      });
    } catch (e) {
      Navigator.pop(context);
      if (kDebugMode) {
        debugPrint('Error fetching player: $e');
      }
    }
  }

  void showLoadingDialog(BuildContext context, message) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.yellow.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF689F38)),
                const SizedBox(width: 20),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(fontSize: 16.0),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = AppLayout.isWide(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFFFF8E1), // soft creamy yellow (like morning sun)
              Color(0xFFFFF8E1), // soft creamy yellow (like morning sun)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          // The page background fills the window; the content keeps a readable
          // measure. On a desktop window the greeting and the hero copy sit in
          // a column on the left and the buttons in a column on the right,
          // instead of one set of cards stretched across the screen.
          child: AppContent(
            maxWidth: 1120,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                Text(
                  'BankPop!',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF33691E),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                _greetingCard(context),
                if (!_signedIn && !wide) ...<Widget>[
                  const SizedBox(height: 10),
                  _GuestBanner(onSignIn: _openAccount),
                ],
                SizedBox(height: wide ? 28 : 22),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _hero(),
                            if (!_signedIn) ...<Widget>[
                              const SizedBox(height: 18),
                              _GuestBanner(onSignIn: _openAccount),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 36),
                      Expanded(flex: 6, child: _buttons(context, wide: true)),
                    ],
                  )
                else ...<Widget>[
                  _hero(),
                  const SizedBox(height: 22),
                  _buttons(context, wide: false),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _greetingCard(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.profile),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: const Color(0xFFFFF9C4), // soft pastel yellow
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Hey, $userName',
                      style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF33691E),
                        letterSpacing: 1.2,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                    Text(
                      'Ready to play?',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF689F38),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => context.push(AppRoutes.profile),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: CircleAvatar(
                    radius: 26.sp,
                    backgroundColor: Colors.white,
                    // Both sources are ~700-1200 px; the avatar is drawn at
                    // 52.sp, so decode it at 156px.
                    backgroundImage:
                        ProfileAvatar.provider(_avatarAsset, cacheWidth: 156),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Bring Your Board Games to Life!',
          style: TextStyle(
            fontSize: 20.sp,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF33691E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'No paper money, no mess - just tap, play, and enjoy a smarter game '
          'night!',
          style: TextStyle(
            fontSize: 16.sp,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF558B2F), // medium green
          ),
        ),
      ],
    );
  }

  /// The four button rows, in the order the app is used: Start on its own, the
  /// two pairs that belong together, then Leave.
  Widget _buttons(BuildContext context, {required bool wide}) {
    final double gap = wide ? 14 : 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ButtonCard(
          title: "Start Game",
          gradientColors: const [
            Color.fromARGB(255, 192, 235, 176),
            Color.fromARGB(255, 182, 229, 165),
            Color.fromARGB(255, 138, 201, 115), // Calm Aqua Mint
            Color.fromARGB(255, 80, 145, 55) // Calm Aqua Mint
          ],
          textColor: const Color(0xFF33691E),
          lottieAssetPath: "assets/lottie/dice.json",
          overlayImageUrl:
              "https://i.pinimg.com/736x/b2/93/53/b293530e766938aeaad897363c9df0eb.jpg",
          onTap: () => _startGame(context),
        ),
        SizedBox(height: gap),
        Row(
          children: <Widget>[
            Expanded(
              child: ButtonCard(
                title: "Your Games",
                compact: true,
                gradientColors: const [
                  Color.fromARGB(255, 214, 234, 248),
                  Color.fromARGB(255, 197, 225, 245),
                  Color.fromARGB(255, 144, 202, 249),
                  Color.fromARGB(255, 100, 181, 246),
                ],
                textColor: const Color(0xFF0D47A1),
                lottieAssetPath: "assets/lottie/bank_role.json",
                onTap: () => _openGames(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ButtonCard(
                title: "Boards & cards",
                compact: true,
                gradientColors: const [
                  Color(0xFFE1BEE7),
                  Color(0xFFCE93D8),
                  Color(0xFFBA68C8),
                  Color(0xFFAB47BC),
                ],
                textColor: const Color(0xFF4A148C),
                lottieAssetPath: "assets/lottie/help.json",
                onTap: () => context.push(AppRoutes.boards),
              ),
            ),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: <Widget>[
            Expanded(
              child: ButtonCard(
                title: "How to use",
                compact: true,
                gradientColors: const [
                  Color.fromARGB(255, 243, 233, 141),
                  Color.fromARGB(255, 243, 233, 141),
                  Color.fromARGB(255, 236, 220, 70),
                  Color.fromARGB(255, 236, 215, 22)
                ],
                textColor: const Color(0xFFFFF9C4),
                lottieAssetPath: "assets/lottie/help.json",
                onTap: () => showHowToUseGuide(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ButtonCard(
                title: "Game rules",
                compact: true,
                gradientColors: const [
                  Color.fromARGB(255, 255, 224, 178),
                  Color.fromARGB(255, 255, 204, 128),
                  Color.fromARGB(255, 255, 183, 77),
                  Color.fromARGB(255, 245, 160, 40),
                ],
                textColor: const Color(0xFFE65100),
                lottieAssetPath: "assets/lottie/help.json",
                onTap: () => context.push(AppRoutes.gameRules),
              ),
            ),
          ],
        ),
        SizedBox(height: gap),
        ButtonCard(
          title: "Leave",
          gradientColors: const [
            Color.fromARGB(255, 243, 169, 169), // Soft Peach
            Color.fromARGB(255, 243, 128, 128), // Soft Peach
            Color.fromARGB(255, 250, 126, 126), // Soft Peach
            Color.fromARGB(255, 245, 67, 67), // Calm Coral
          ],
          textColor: const Color.fromARGB(255, 245, 72, 66),
          lottieAssetPath: "assets/lottie/close.json",
          overlayImageUrl:
              "https://i.pinimg.com/736x/03/52/7d/03527dc76d013498547fb1e61759dcd4.jpg",
          onTap: () => _exitApp(context),
        ),
      ],
    );
  }

  /// Your Games works for a guest too: the list is read from the player id
  /// this device has been playing under, account or not. A guest sees the same
  /// games with a reminder at the top that they are not linked to an account.
  Future<void> _openGames(BuildContext context) async {
    context.push(AppRoutes.games);
  }

  /// The banner's "Sign in": the same screen the first run offers, and back to
  /// the home screen afterwards so the name and avatar refresh.
  Future<void> _openAccount() async {
    final bool? signedIn = await context.push<bool>(AppRoutes.authReturning);
    if (signedIn != true || !mounted) return;
    await _loadUser();
    final bool nowSignedIn = await Account.isSignedIn();
    if (mounted) setState(() => _signedIn = nowSignedIn);
  }

  void _startGame(BuildContext context) {
    context.push(AppRoutes.start);
  }

  void _exitApp(BuildContext context) async {
    final bool confirmExit = await showAppConfirm(
      context,
      title: 'Exit the game?',
      icon: Icons.power_settings_new,
      destructive: true,
      confirmLabel: 'Exit',
      cancelLabel: 'Cancel',
      message: 'Are you sure you want to exit? Any game you are in can be '
          'reopened from Your Games.',
    );

    if (!confirmExit) return;

    if (kIsWeb) {
      // A page cannot close a tab it did not open. Clearing the game and
      // returning to the welcome screen is the closest equivalent, and it also
      // leaves the browser in the state "Leave" is meant to produce.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('gameID');
      if (!context.mounted) return;
      // Already the welcome screen; going there again clears the history so
      // the browser's back button does not walk into the game that was left.
      context.go(AppRoutes.home);
      return;
    }

    // Android: the system back-to-home gesture. iOS does not allow an app to
    // quit itself, so the same call is the platform's no-op there rather than
    // the `exit(0)` this used to run (which Apple discourages).
    await SystemNavigator.pop();
  }
}

/// A quiet reminder, under the greeting, that a guest's games are local.
class _GuestBanner extends StatelessWidget {
  const _GuestBanner({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFFE8F5E9),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.person_outline,
                color: Color(0xFF2E7D32), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Playing as a guest',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF33691E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your games stay on this device. Sign in to keep them '
                    'across devices and reinstalls.',
                    style: TextStyle(
                      fontSize: 11.sp,
                      height: 1.25,
                      color: const Color(0xFF558B2F),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onSignIn,
              child: Text(
                'Sign in',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ButtonCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Color> gradientColors;
  final Color textColor;
  final String? overlayImageUrl; // Static image in the background
  final String? lottieAssetPath; // 🆕 Foreground Lottie animation
  final VoidCallback onTap;

  /// Half a row rather than the whole width: the label and animation shrink so
  /// two cards still read cleanly side by side.
  final bool compact;

  const ButtonCard({
    super.key,
    required this.title,
    required this.gradientColors,
    required this.textColor,
    this.icon,
    this.overlayImageUrl,
    this.lottieAssetPath,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // The whole card is the tap target, so it is the whole card that screen
      // readers (and the web build's accessibility tree) should announce.
      button: true,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          color: Colors.transparent, // Keep transparent for gradient to show
          child: Container(
            width: double.infinity,
            // Clamped so a landscape phone still has a real tap target and a
            // tall desktop window does not turn a button into a banner.
            height: (compact ? 9.h : 11.h).clamp(64.0, 132.0).toDouble(),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                /*  if (overlayImageUrl != null)
                Opacity(
                  opacity: 0.5,
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(16), // Adjust the radius as needed
                    child: Image.network(
                      overlayImageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
         */
                // 🔥 Foreground Lottie animation
                if (lottieAssetPath != null)
                  Positioned(
                    left: title != 'How to use' ? 0 : 10,
                    bottom: 0,
                    top: 0,
                    child: SizedBox(
                      height: (compact
                              ? 7.h
                              : (title != 'How to use' ? 10.h : 8.h))
                          .clamp(46.0, 108.0)
                          .toDouble(),
                      width: (compact
                              ? 7.h
                              : (title != 'How to use' ? 10.h : 8.h))
                          .clamp(46.0, 108.0)
                          .toDouble(),
                      child: Lottie.asset(lottieAssetPath!,
                          fit: BoxFit.contain, repeat: true),
                    ),
                  ),

                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10.0, right: 10),
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 16.sp : 23.sp,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
