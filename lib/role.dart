import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mon/bank_details.dart';
import 'package:mon/main.dart';
import 'package:mon/player_details.dart';
import 'package:mon/player_screen.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SelectRoleScreen extends StatelessWidget {
  const SelectRoleScreen({super.key});

  void _goToBanker(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BankValueScreen()),
    );
  }

  void _goToPlayer(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? playerID = prefs.getString('playerID');

    // Step 1: Ask user to Scan or Enter Game ID
    // ignore: use_build_context_synchronously
    final bool? scanOption = await _showGameJoinDialog(context);
    if (scanOption == null) return; // User dismissed the dialog

    Map<String, dynamic>? result;

    if (scanOption == true) {
      // Step 2A: Push to QR scanner
      // ignore: use_build_context_synchronously
      final scannedResult = await _navigateToQRScanner(context);
      if (scannedResult == null) return; // If no valid result, exit
      result = scannedResult;
    } else {
      // Step 2B: Show input dialog to manually enter Game ID
      // ignore: use_build_context_synchronously
      String? enteredId = await _showGameIdInputDialog(context);
      if (enteredId != null && enteredId.trim().isNotEmpty) {
        final trimmedId = enteredId.trim();
        result =
            // ignore: use_build_context_synchronously
            await _checkGameIdAndShowNameDialog(context, trimmedId, playerID);
      }
    }

    // Step 3: Process result (after name entry and joining)
    if (result != null) {
      // ignore: use_build_context_synchronously
      _navigateToPlayersScreen(context, result);
    } else {
      // ignore: use_build_context_synchronously
      _showUnableToJoinDialog(context);
    }
  }

// Extracted method to show the initial dialog for scanning or entering the ID
  Future<bool?> _showGameJoinDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Game'),
        content: const Text(
            'Do you want to scan a QR code or enter the Game ID manually?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // Enter manually
            child: const Text('Enter'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), // Scan
            child: const Text('Scan'),
          ),
        ],
      ),
    );
  }

// Extracted method to navigate to QR scanner screen
  Future<Map<String, dynamic>?> _navigateToQRScanner(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PlayerQRScannerScreen(scan: true),
      ),
    );
  }

// Extracted method to show the dialog for entering Game ID
  Future<String?> _showGameIdInputDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        String input = '';
        return AlertDialog(
          title: const Text('Enter Game ID'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Game ID'),
            onChanged: (value) => input = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), // Cancel
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, input), // OK
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

// Extracted method to navigate to PlayersScreen
  void _navigateToPlayersScreen(
      BuildContext context, Map<String, dynamic> result) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayersScreen(
          bankValue: double.parse(result['wallet'].toString()),
          gameId: result['game_id'],
        ),
      ),
    );
  }

// Refactored _checkGameIdAndShowNameDialog to avoid BuildContext cross async
  Future<Map<String, dynamic>?> _checkGameIdAndShowNameDialog(
      BuildContext context, String gameId, String? playerID) async {
    final supabase = Supabase.instance.client;

    if (gameId.isEmpty || playerID == null) return null;

    // Check if the Game ID is valid by querying the 'players_test' table
    final gameResponse = await supabase
        .from('players_test')
        .select()
        .eq('game_id', gameId)
        .limit(1);

    final gameData = gameResponse;
    if (gameData.isEmpty) {
      // ignore: use_build_context_synchronously
      _showInvalidGameIdSnackBar(
          context); // Showing the error on invalid Game ID
      return null;
    }

    // Step 2: Show the Enter Name dialog
    final nameController = TextEditingController();
    // ignore: use_build_context_synchronously
    String? playerName = await _showEnterNameDialog(context, nameController);
    if (playerName == null || playerName.isEmpty) {
      return null; // If no name entered, return null
    }

    // Step 3: Check if player exists and try to join
    // ignore: use_build_context_synchronously
    final Map<String, dynamic>? playerData = await _checkPlayerAndJoin(
        context, gameId, playerID, nameController.text);
    return playerData;
  }

// Extracted method to show snack bar for invalid Game ID
  void _showInvalidGameIdSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invalid Game ID')),
    );
  }

// Refactored to avoid BuildContext across async operations
  Future<String?> _showEnterNameDialog(
      BuildContext context, TextEditingController nameController) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.yellow.shade50,
          title: const Text('Enter your name'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(nameController.text); // Close dialog and return name
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
  }

// Extracted method to check player and attempt to join game
  Future<Map<String, dynamic>?> _checkPlayerAndJoin(BuildContext context,
      String gameId, String? playerID, String name) async {
    final supabase = Supabase.instance.client;

    // Check if player already exists
    final existingPlayerResponse = await supabase
        .from('players_test')
        .select()
        .eq('game_id', gameId)
        .eq('player_id', playerID!)
        .limit(1);

    final existingPlayerData = existingPlayerResponse;
    if (existingPlayerData.isEmpty) {
      // If player doesn't exist, insert a new record
      try {
        await supabase.from('request_test').insert({
          'game_id': gameId,
          'name': name,
          'wallet': 0,
          'role': 'player',
          'player_id': playerID,
        });
      } catch (e) {
        debugPrint('Error inserting request: $e');
        return null;
      }
    }

    // Show waiting dialog while waiting for approval
    // ignore: use_build_context_synchronously
    _showWaitingDialog(context);

    final stopwatch = Stopwatch()..start();
    const pollInterval = Duration(seconds: 2);
    const maxWait = Duration(seconds: 10);

    Map<String, dynamic>? approvedPlayer;

    while (stopwatch.elapsed < maxWait) {
      final response = await supabase
          .from('players_test')
          .select()
          .eq('game_id', gameId)
          .eq('player_id', playerID)
          .eq('role', 'player')
          .limit(1);

      final data = response;
      if (data.isNotEmpty) {
        approvedPlayer = data.first;
        break;
      }

      await Future.delayed(pollInterval);
    }

    // ignore: use_build_context_synchronously
    Navigator.of(context).pop(); // Close waiting dialog

    return approvedPlayer;
  }

  void _showWaitingDialog(BuildContext context) {
    int secondsRemaining = 15;
    late StateSetter setState;

    Timer? timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (secondsRemaining > 0) {
        setState(() {
          secondsRemaining--;
        });
      } else {
        t.cancel();
        Navigator.of(context).pop(); // auto-close the dialog when timer ends
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter stateSetter) {
            setState = stateSetter;
            return AlertDialog(
              backgroundColor: Colors.yellow.shade50,
              title: const Text("Waiting for Approval"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text(
                      "Waiting for host to approve your join request..."),
                  const SizedBox(height: 16),
                  Text("Auto-canceling in $secondsRemaining seconds"),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      timer
          .cancel(); // Ensure timer is cancelled if dialog is dismissed manually
    });
  }

  void _showUnableToJoinDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.yellow.shade50,
        title: const Text("Unable to Join"),
        content: const Text("Approval not received within 1 minute."),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false), // Return to previous screen
            child: const Text("OK"),
          ),
        ],
      ),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 5.h),
                margin: EdgeInsets.symmetric(horizontal: 6.w),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Continue as',
                        style: TextStyle(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.black45,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 5.h),
                      _buildRoleButton(
                        context,
                        title: 'Banker',
                        icon: Icons.account_balance,
                        color: Colors.brown,
                        colors: [
                          const Color(0xFF5B86E5),
                          const Color(0xFF36D1DC)
                        ], // Blue gradient
                        onTap: () => _goToBanker(context),
                      ),
                      SizedBox(height: 3.h),
                      _buildRoleButton(
                        context,
                        title: 'Player',
                        icon: FontAwesomeIcons.dice,
                        color: Colors.blue.shade300,
                        colors: [
                          const Color(0xFF7F00FF),
                          const Color(0xFFE100FF)
                        ], // Purple gradient
                        onTap: () => _goToPlayer(context),
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

  Widget _buildRoleButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 70.w,
      height: 7.h,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            /*  gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ), */
            /*   boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.6),
                blurRadius: 5,
                offset: const Offset(3, 3),
              ),
            ], */
            border: Border.all(color: color.withOpacity(.6)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22.sp),
              const SizedBox(width: 20),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
