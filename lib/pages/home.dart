import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/pages/player/player_screen.dart';
import 'package:mon/pages/profile_edit.dart';
import 'package:mon/pages/role.dart';
import 'package:mon/profile.dart';
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
  String _profilePath = '';
  String userName = "";
  File? _profileImage;

  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _profilePath = prefs.getString("profile_image") ?? '';
    userName = prefs.getString('profile_name') ?? "";
    if (_profilePath.isNotEmpty && userName.isNotEmpty) {
      await _loadPackageInfo();
      await _loadUser();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkForPlayerAndNavigate();
      });
    } else {
      bool? updated = await showDialog(
        context: context,
        barrierDismissible: false, // disables tap outside to dismiss
        builder: (context) => WillPopScope(
          onWillPop: () async => false, // disables back button
          child: const ProfileDialog(
            first: true,
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
      _profilePath = prefs.getString("profile_image") ?? '';
      _profileImage = File(_profilePath);
      userName = prefs.getString('profile_name') ?? "Your Name";
    });
  }

  Future<void> _checkForPlayerAndNavigate() async {
    showLoadingDialog(context, 'Loading...');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? playerID = prefs.getString('playerID');
    final String? gameID = prefs.getString('gameID');

    try {
      final response = await supabase
          .from('players_test')
          .select()
          .eq('game_id', gameID!)
          .eq('player_id', playerID!)
          .eq('role', 'banker')
          .limit(1);

      final response2 = await supabase
          .from('players_test')
          .select()
          .eq('game_id', gameID)
          .eq('player_id', playerID)
          .eq('role', 'player')
          .limit(1);

      if (response.isNotEmpty) {
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
      } else if (response2.isNotEmpty) {
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
        print('Error fetching player: $e');
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
                const CircularProgressIndicator(
                  color: Colors.black,
                ),
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

  void showHowToPlayDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        Widget bullet(String text) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "•  ",
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF827717),
                  ),
                ),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF827717),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget roleContent({
          required String role,
          required List<String> scanPayPoints,
          required List<String> instantPayPoints,
        }) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "ScanPay",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFFF57F17),
                  ),
                ),
                const SizedBox(height: 8),
                ...scanPayPoints.map(bullet),
                const SizedBox(height: 16),
                const Text(
                  "InstantPay",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFFF57F17),
                  ),
                ),
                const SizedBox(height: 8),
                ...instantPayPoints.map(bullet),
              ],
            ),
          );
        }

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: const Color(0xFFFFF9C4), // soft light green
          title: const Text(
            "How to Play",
            style: TextStyle(
              color: Color(0xFF33691E), // deep green for title
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: DefaultTabController(
              length: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TabBar(
                    labelColor: Color(0xFF33691E),
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Color(0xFF689F38),
                    tabs: [
                      Tab(text: "Player"),
                      Tab(text: "Banker"),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 280,
                    child: TabBarView(
                      children: [
                        // Player tab
                        roleContent(
                          role: "Player",
                          scanPayPoints: [
                            "Join a game hosted by the banker.",
                            "Manage your in-game balance digitally.",
                            "Tap to pay rent, buy property, or collect income.",
                            "Use the app instead of paper money or cards.",
                            "Keep an eye on your balance and transactions.",
                          ],
                          instantPayPoints: [
                            "Join a game instantly without scanning.",
                            "Manage your in-game balance digitally.",
                            "Tap to pay rent, buy property, or collect income.",
                            "Use the app instead of paper money or cards.",
                            "Monitor your balance at all times.",
                          ],
                        ),
                        // Banker tab
                        roleContent(
                          role: "Banker",
                          scanPayPoints: [
                            "Start a new game and assign starting balances.",
                            "Oversee all player transactions digitally.",
                            "Adjust balances manually if needed.",
                            "Ensure fair play and assist players.",
                            "End the game when a winner is declared.",
                          ],
                          instantPayPoints: [
                            "Quickly start a game without scanning.",
                            "Oversee all player transactions digitally.",
                            "Adjust balances manually if needed.",
                            "Ensure fair play and assist players.",
                            "End the game when a winner is declared.",
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          /*   actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              "Got it!",
              style: TextStyle(
                color: Color(0xFF689F38), // button green
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ], */
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
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Only an idiot would press this.')),
                            );
                          },
                          child: const Icon(
                            CupertinoIcons.info_circle_fill,
                            color: Color(0xFF33691E),
                          ),
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
                                    backgroundImage: _profileImage != null
                                        ? FileImage(_profileImage!)
                                        : const AssetImage(
                                                'assets/images/play_icon.jpg')
                                            as ImageProvider,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

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
                          onTap: () => showHowToPlayDialog(context),
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
                  'Version $version.$buildNumber',
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
    bool? confirmExit = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Exit the Game'),
          content: const Text('Are you sure you want to exit?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // Cancel
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // Confirm
              },
              child: const Text('Exit'),
            ),
          ],
        );
      },
    );

    if (confirmExit == true) {
      if (Platform.isAndroid) {
        SystemNavigator.pop(); // Closes the app
      } else if (Platform.isIOS) {
        exit(0); // Only way on iOS, but discouraged
      }
    }
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
    return GestureDetector(
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
    );
  }
}
