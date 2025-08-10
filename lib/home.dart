import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mon/player_screen.dart';
import 'package:mon/role.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'banker_screen.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForPlayerAndNavigate();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image:
                AssetImage('assets/images/background.jpeg'), // Adjust the path
            fit: BoxFit.cover,
          ),
          gradient: LinearGradient(
            colors: [
              Color(0xFFF0F2F5),
              Color(0xFFE1E5EB),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 5.h),
                margin: EdgeInsets.symmetric(horizontal: 6.w),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: EdgeInsets.only(top: 18.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Welcome to Bankpop!',
                        style: TextStyle(
                          fontSize: 25.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.black45,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      _buildButton(
                        context,
                        title: 'Start Game',
                        icon: FontAwesomeIcons.dice,
                        color: Colors.green,
                        colors: [
                          const Color(0xFF00C6FF),
                          const Color(0xFF0072FF)
                        ], // Blue gradient
                        onTap: () => _startGame(context),
                      ),
                      SizedBox(height: 3.h),
                      _buildButton(
                        context,
                        title: 'Exit',
                        icon: FontAwesomeIcons.doorOpen,
                        color: Colors.red.shade300,
                        colors: [
                          const Color(0xFFf12711),
                          const Color.fromARGB(255, 245, 113, 25)
                        ], // Red gradient
                        onTap: () => _exitApp(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Color> colors,
    required Function onTap,
  }) {
    return InkWell(
      onTap: () => onTap(),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 2.h, horizontal: 4.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white),
            SizedBox(width: 4.w),
            Text(
              title,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
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
    // Show a confirmation dialog before exiting
    bool? confirmExit = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Exit the Game'),
          content: const Text('Are you sure you want to exit?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // User cancels
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // User confirms
              },
              child: const Text('Exit'),
            ),
          ],
        );
      },
    );

    // If the user confirmed, exit the app
    if (confirmExit == true) {
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(); // Close the current screen
    }
  }
}
