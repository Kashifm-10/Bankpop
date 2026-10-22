import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/pages/auth/auth_screen.dart';
import 'package:mon/pages/game_history_screen.dart';
import 'package:mon/pages/player/player_screen.dart';
import 'package:mon/services/account.dart';
import 'package:mon/pages/profile_edit.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/services/profile_avatar.dart';
import 'package:mon/pages/role.dart';
import 'package:mon/profile.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/how_to_play_dialog.dart';
import 'package:mon/widgets/bankpop_board_popup.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'banker/banker_screen.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final supabase = Supabase.instance.client;
  String appName = '';
  String packageName = '';
  String version = '';
  String buildNumber = '';

  /// The bundled avatar this device picked, or the app icon. It is an asset
  /// path rather than a file, so the same value renders on Android and web.
  String _avatarAsset = ProfileAvatar.appIcon;
  String userName = "";

  /// True when the game this device last joined is playing with cards. Read
  /// from prefs (banker) or the bank row (players), so the board icon is only
  /// offered in a game that actually uses cards.
  bool _playWithCards = false;

  /// An account is optional: a guest gets the whole app, and this only decides
  /// whether the greeting carries the "sign in to keep your games" banner.
  bool _signedIn = false;

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
    // Cards mode is a property of the game, kept on its session row. The local
    // copy is only a fallback while that row cannot be read (a project that
    // has not run game_sessions.sql yet).
    final String? gameId = prefs.getString('gameID');
    _playWithCards = prefs.getBool('playWithCards') ?? false;
    if (gameId != null && gameId.isNotEmpty) {
      final GameSession? session = await GameSession.fetch(gameId);
      if (session != null) {
        _playWithCards = session.playWithCards;
      } else {
        // A game started before game_sessions.sql keeps the switch on its bank
        // row; read it there so the board icon does not disappear.
        try {
          final Map<String, dynamic>? bankRow = await supabase
              .from('players_test')
              .select('play_with_cards')
              .eq('game_id', gameId)
              .eq('role', 'banker')
              .maybeSingle();
          if (bankRow?['play_with_cards'] is bool) {
            _playWithCards = bankRow!['play_with_cards'] == true;
          }
        } catch (error) {
          debugPrint('Could not read cards mode: $error');
        }
      }
    }
    if (userName.isNotEmpty) {
      await _loadPackageInfo();
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

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      appName = info.appName;
      packageName = info.packageName;
      version = info.version;
      buildNumber = info.buildNumber;
    });
  }

  Future<void> _loadUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _avatarAsset = ProfileAvatar.saved(prefs);
      userName = prefs.getString('profile_name') ?? "Your Name";
    });
  }

  Future<void> _checkForPlayerAndNavigate() async {
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

      if (isBanker) {
        // ignore: use_build_context_synchronously
        Navigator.pop(context);
        // Delay navigation slightly to avoid context issues
        Future.delayed(const Duration(milliseconds: 100), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => BankerGameScreen(
                bankValue: 0,
                gameId: gameID,
              ),
            ),
          );
        });
      } else if (isPlayer) {
        // ignore: use_build_context_synchronously
        Navigator.pop(context);
        // Delay navigation slightly to avoid context issues
        Future.delayed(const Duration(milliseconds: 100), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PlayersScreen(
                bankValue: 0,
                gameId: gameID,
              ),
            ),
          );
        });
      }
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
              Color(0xFFFFF8E1), // soft creamy yellow (like morning sun)
              Color(0xFFFFF8E1), // soft creamy yellow (like morning sun)
              // Color(0xFFB3E5FC), // light sky blue
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 0.h),
                margin: EdgeInsets.symmetric(horizontal: 2.w, vertical: 2.h),
                child: ListView(
                  // The version label is pinned over the bottom of this list; the
                  // padding stops the last card from sliding underneath it on a
                  // short screen.
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'BankPop!',
                          style: TextStyle(
                            fontSize: 24.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF33691E),
                            letterSpacing: 1.2,
                          ),
                        ),
                        Row(
                          children: [
                            if (_playWithCards)
                              GestureDetector(
                                onTap: () async {
                                  final SharedPreferences prefs =
                                      await SharedPreferences.getInstance();
                                  if (!context.mounted) return;
                                  showDialog(
                                    context: context,
                                    builder: (_) => BankpopBoardPopup(
                                      gameId: prefs.getString('gameID') ?? '',
                                    ),
                                  );
                                },
                                child: const Icon(Icons.grid_on),
                              ),
                            SizedBox(width: 15),
                            GestureDetector(
                              onTap: () {
                                showMessage(
                                    context, 'Only an idiot would press this.');
                              },
                              child: const Icon(
                                CupertinoIcons.info_circle_fill,
                                color: Color(0xFF33691E),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                    SizedBox(height: 2.h),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfilePage()),
                        );
                      },
                      child: Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        color: const Color(0xFFFFF9C4), // soft pastel yellow
                        elevation: 3,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                // <- Limits width so text can wrap
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
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
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const ProfilePage()),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: CircleAvatar(
                                    radius: 26.sp,
                                    backgroundColor: Colors.white,
                                    // Both sources are ~700-1200 px; the
                                    // avatar is drawn at 52.sp, so decode it
                                    // at 156px.
                                    backgroundImage: ProfileAvatar.provider(
                                        _avatarAsset,
                                        cacheWidth: 156),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (!_signedIn) ...<Widget>[
                      const SizedBox(height: 10),
                      _GuestBanner(onSignIn: _openAccount),
                    ],

                    SizedBox(height: 6.h),
                    Text(
                      'Bring Your Board Games to Life!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF33691E),
                      ),
                    ),
                    SizedBox(height: 1.h),
                    Text(
                      'No paper money, no mess — just tap, play, and enjoy a smarter game night!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF558B2F), // medium green
                      ),
                    ),
                    SizedBox(height: 4.h),

                    // Button cards
                    Column(
                      children: [
                        ButtonCard(
                          title: "Start Game",
                          gradientColors: const [
                            Color.fromARGB(255, 192, 235, 176),
                            Color.fromARGB(255, 182, 229, 165),
                            Color.fromARGB(
                                255, 138, 201, 115), // Calm Aqua Mint
                            Color.fromARGB(255, 80, 145, 55) // Calm Aqua Mint
                          ],
                          textColor: const Color(0xFF33691E),
                          lottieAssetPath: "assets/lottie/dice.json",
                          overlayImageUrl:
                              "https://i.pinimg.com/736x/b2/93/53/b293530e766938aeaad897363c9df0eb.jpg",
                          onTap: () => _startGame(context),
                        ),
                        const SizedBox(height: 20),
                        ButtonCard(
                          title: "Your Games",
                          gradientColors: const [
                            Color.fromARGB(255, 214, 234, 248),
                            Color.fromARGB(255, 197, 225, 245),
                            Color.fromARGB(255, 144, 202, 249),
                            Color.fromARGB(255, 100, 181, 246),
                          ],
                          textColor: const Color(0xFF0D47A1),
                          lottieAssetPath: "assets/lottie/bank_role.json",
                          overlayImageUrl:
                              "https://i.pinimg.com/736x/b2/93/53/b293530e766938aeaad897363c9df0eb.jpg",
                          onTap: () => _openGames(context),
                        ),
                        const SizedBox(height: 20),
                        ButtonCard(
                          title: "How to use",
                          gradientColors: const [
                            Color.fromARGB(255, 243, 233, 141),
                            Color.fromARGB(255, 243, 233, 141),
                            Color.fromARGB(255, 236, 220, 70), // Calm Aqua Mint
                            Color.fromARGB(255, 236, 215, 22) // Calm Aqua Mint
                          ],
                          textColor: const Color(0xFFFFF9C4),
                          lottieAssetPath: "assets/lottie/help.json",
                          overlayImageUrl:
                              "https://i.pinimg.com/736x/b2/93/53/b293530e766938aeaad897363c9df0eb.jpg",
                          onTap: () => HowToPlayGuide.show(context),
                        ),
                        const SizedBox(height: 20),
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
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Text(
                  buildNumber.isEmpty
                      ? 'Version $version'
                      : 'Version $version ($buildNumber)',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: const Color(0xFF558B2F), // medium green
                    fontWeight: FontWeight.w300,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Your Games belongs to the account: the list is read from the games this
  /// player id has rows in, which a guest does not have anywhere but this
  /// device. Asking for a sign-in is clearer than opening an empty list.
  Future<void> _openGames(BuildContext context) async {
    if (!await Account.isSignedIn()) {
      if (!context.mounted) return;
      final bool signIn = await showAppConfirm(
        context,
        title: 'Sign in to view your games',
        icon: Icons.lock_outline,
        confirmLabel: 'Sign in',
        cancelLabel: 'Not now',
        message:
            'Your games are saved to your account, so they follow you to a '
            'new phone or a reinstall. Sign in to see them - or keep playing '
            'as a guest without an account.',
      );
      if (signIn && context.mounted) await _openAccount();
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const GameHistoryScreen()),
    );
  }

  /// The banner's "Sign in": the same screen the first run offers, and back to
  /// the home screen afterwards so the name and avatar refresh.
  Future<void> _openAccount() async {
    final bool? signedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => const AuthScreen(returnOnSuccess: true),
      ),
    );
    if (signedIn != true || !mounted) return;
    await _loadUser();
    final bool nowSignedIn = await Account.isSignedIn();
    if (mounted) setState(() => _signedIn = nowSignedIn);
  }

  void _startGame(BuildContext context) {
    // Push to the next page (GamePage)
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              const SelectRoleScreen()), // Replace GamePage with your actual game page
    );
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
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomePage()),
        (Route<dynamic> route) => false,
      );
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

  const ButtonCard({
    super.key,
    required this.title,
    required this.gradientColors,
    required this.textColor,
    this.icon,
    this.overlayImageUrl,
    this.lottieAssetPath,
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
            width: 80.w,
            height: 11.h,
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
                      height: title != 'How to use' ? 11.h : 8.h,
                      width: title != 'How to use' ? 11.h : 8.h,
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23.sp,
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
