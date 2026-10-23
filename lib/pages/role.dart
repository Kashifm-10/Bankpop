import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SelectRoleScreen extends StatelessWidget {
  const SelectRoleScreen({super.key});

  /// Set when the join was refused for a reason that was already explained in
  /// its own dialog (a player the banker removed). The generic "approval not
  /// received" box must not then appear on top of that explanation.
  static bool _explainedRefusal = false;

  void _goToBanker(BuildContext context) {
    context.push(AppRoutes.newGame);
  }

  void _goToPlayer(BuildContext context) async {
    _explainedRefusal = false;
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
    } else if (!_explainedRefusal) {
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
    // The scanner pops its result, and a routed push returns that result just
    // as a MaterialPageRoute did.
    return context.push<Map<String, dynamic>>(AppRoutes.joinScan);
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
    final String gameId = result['game_id']?.toString() ?? '';
    final double wallet = double.tryParse('${result['wallet']}') ?? 0;
    context.push(AppRoutes.player(gameId, bankValue: wallet));
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

    // A finished game must not take new players. A suspended one can still be
    // joined: the player is told it is paused and can come back when the
    // banker resumes it.
    final GameSession? session = await GameSession.fetch(gameId);
    if (session != null && session.isEnded) {
      if (context.mounted) showMessage(context, 'That game has already ended.');
      return null;
    }

    // The name now comes from the profile saved on this device.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? playerName =
        prefs.getString('profile_name') ?? 'player${playerID.substring(0, 3)}';

    // Step 3: Check if player exists and try to join
    // ignore: use_build_context_synchronously
    final Map<String, dynamic>? playerData =
        await _checkPlayerAndJoin(context, gameId, playerID, playerName);
    return playerData;
  }

// Extracted method to show snack bar for invalid Game ID
  void _showInvalidGameIdSnackBar(BuildContext context) {
    showMessage(context, 'Invalid Game ID');
  }

// Refactored to avoid BuildContext across async operations
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

    // A removed player has no seat left to rejoin - their cash and cards are
    // the bank's now.
    for (final dynamic raw in existingPlayerData) {
      final Map<String, dynamic> row = (raw as Map).cast<String, dynamic>();
      if (PlayerStanding.fromRow(row) != PlayerStanding.kicked) continue;
      _explainedRefusal = true;
      if (context.mounted) {
        await showAppDialog<void>(
          context,
          title: 'You were removed',
          icon: Icons.person_remove_alt_1,
          accent: const Color(0xFFC62828),
          message: 'The banker removed you from this game, so there is no seat '
              'to rejoin. Ask them to put you back - they can do that from the '
              'table, and you will start again with an empty wallet and no '
              'cards - or to start a new game.',
          actions: <Widget>[
            AppDialogButton(
              label: 'OK',
              primary: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      }
      return null;
    }

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

    final stopwatch = Stopwatch()..start();
    const pollInterval = Duration(seconds: 2);
    const maxWait = Duration(seconds: 10);

    // Show waiting dialog while waiting for approval. It counts down the same
    // window the poll waits for, so it never outlives the poll (which used to
    // leave a stray `pop` closing the screen behind it).
    // ignore: use_build_context_synchronously
    _showWaitingDialog(context, maxWait);

    Map<String, dynamic>? approvedPlayer;

    // Realtime first: approval inserts this player's row, so the waiting dialog
    // can close the moment it lands. The loop below still asks the backend
    // directly, which is what keeps joining working if the socket is down.
    final Completer<Map<String, dynamic>> approved =
        Completer<Map<String, dynamic>>();
    StreamSubscription<List<Map<String, dynamic>>>? approvalUpdates;
    try {
      approvalUpdates = supabase
          .from('players_test')
          .stream(primaryKey: const ['id'])
          .eq('game_id', gameId)
          .listen(
            (List<Map<String, dynamic>> rows) {
              if (approved.isCompleted) return;
              for (final Map<String, dynamic> row in rows) {
                if (row['role'] == 'player' && row['player_id'] == playerID) {
                  approved.complete(row);
                  return;
                }
              }
            },
            onError: (Object error) =>
                debugPrint('Approval stream error, still polling: $error'),
          );
    } catch (e) {
      debugPrint('Could not subscribe to approval updates: $e');
    }

    try {
      while (stopwatch.elapsed < maxWait && !approved.isCompleted) {
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

        // Wake up as soon as the socket delivers the approval instead of always
        // waiting out the full poll interval.
        await Future.any<void>(<Future<void>>[
          Future<void>.delayed(pollInterval),
          approved.future,
        ]);
      }

      if (approvedPlayer == null && approved.isCompleted) {
        approvedPlayer = await approved.future;
      }
    } finally {
      await approvalUpdates?.cancel();
    }

    // Nothing came back inside the window: the request is withdrawn so the
    // banker's queue does not hold a seat nobody is waiting for any more.
    if (approvedPlayer == null) {
      try {
        await supabase
            .from('request_test')
            .delete()
            .eq('game_id', gameId)
            .eq('player_id', playerID);
      } catch (error) {
        debugPrint('Could not withdraw the join request: $error');
      }
    }

    // ignore: use_build_context_synchronously
    Navigator.of(context).pop(); // Close waiting dialog

    if (approvedPlayer == null) {
      // Already said, so the caller's own "unable to join" dialog does not
      // stack a second copy on top of it.
      _explainedRefusal = true;
      if (context.mounted) {
        showMessage(
          context,
          'The banker did not approve in time, so the request was withdrawn. '
          'Ask them to watch for it, then join again.',
          title: 'Not approved yet',
        );
      }
    }

    return approvedPlayer;
  }

  void _showWaitingDialog(BuildContext context, Duration window) {
    int secondsRemaining = window.inSeconds;
    late StateSetter setState;
    bool open = true;

    final Timer timer = Timer.periodic(const Duration(seconds: 1), (t) {
      // The poll closes this dialog; the countdown only keeps the player
      // informed and stops once there is nothing left to count.
      if (!open || secondsRemaining <= 0) {
        t.cancel();
        return;
      }
      setState(() {
        secondsRemaining--;
      });
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter stateSetter) {
            setState = stateSetter;
            return AlertDialog(
              title: const Text("Waiting for Approval"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF689F38)),
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
      // The dialog is gone (the poll closed it); stop repainting it.
      open = false;
      timer.cancel();
    });
  }

  void _showUnableToJoinDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Unable to Join"),
        content:
            const Text("The banker did not approve the join request in time."),
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
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(
              CupertinoIcons.chevron_back,
              size: 22.sp,
              color: Color(0xFF689F38),
            )),
        title: const Text(
          "Choose Role",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF689F38),
            letterSpacing: 1.1,
          ),
        ),
        backgroundColor: Colors.transparent, // fresh green
        elevation: 0,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFFFF8E1), // soft light green
              Color(0xFFFFF8E1), // slightly darker soft green
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        // The role picker used to be a bare Column, so a short screen (a
        // landscape tablet, a browser window, a phone with a large text scale)
        // overflowed with no way to scroll. It now scrolls, and stays centred
        // while it still fits.
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) =>
              SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(height: 5.5.h),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6.w, vertical: 0.h),
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
                            Padding(
                              padding: const EdgeInsets.only(right: 15.0),
                              child: SizedBox(
                                height: 45.sp,
                                child: Lottie.asset(
                                  "assets/lottie/thinking.json",
                                  fit: BoxFit.contain,
                                  repeat: true,
                                ),
                              ),
                            ),
                            Text(
                              'Time to Pick a Role!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20.sp,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF33691E), // medium green
                              ),
                            ),
                            SizedBox(height: 2.5.h),
                            RoleButtonCard(
                              title: "Become a\nBanker",
                              gradientColors: const [
                                Color(0xFF81C784), // light green
                                Color(0xFF388E3C), // deep green
                              ],
                              lottieAssetPath: "assets/lottie/bank_role.json",
                              overlayImageUrl:
                                  "https://i.pinimg.com/736x/ba/71/9d/ba719dbedd1f8a0291a5415710f9ca53.jpg",
                              onTap: () => _goToBanker(context),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Be the Banker — the money master keeping track of the cash flow.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF558B2F), // medium green
                              ),
                            ),
                            const SizedBox(height: 25),
                            RoleButtonCard(
                              title: "Play as a\nPlayer",
                              gradientColors: const [
                                Color(0xFFAED581), // soft green
                                Color(0xFF558B2F), // rich green
                              ],
                              lottieAssetPath: "assets/lottie/player_role.json",
                              overlayImageUrl:
                                  "https://i.pinimg.com/1200x/ec/64/53/ec64534337b9832dcee5e7a4ab8f816d.jpg",
                              onTap: () => _goToPlayer(context),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Or be a Player — the risk-taker, deal-maker, and future millionaire!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF558B2F), // medium green
                              ),
                            ),
                            const SizedBox(height: 10),
                            /*  Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF689F38), // button green
                              foregroundColor: Colors.white, // text color
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_back_ios,
                                  size: 15.sp,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Back',
                                  style: TextStyle(fontSize: 16.sp),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ) */
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoleButtonCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Color> gradientColors;
  final String? overlayImageUrl; // Static image in the background
  final String? lottieAssetPath; // 🆕 Foreground Lottie animation
  final VoidCallback onTap;

  const RoleButtonCard({
    super.key,
    required this.title,
    required this.gradientColors,
    this.icon,
    this.overlayImageUrl,
    this.lottieAssetPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title.replaceAll('\n', ' '),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          color: Colors.transparent,
          child: Container(
            width: 70.w,
            height: 15.h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(colors: gradientColors),
            ),
            child: Stack(
              children: [
                if (overlayImageUrl != null)
                  Opacity(
                    opacity: 0.5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                          16), // Adjust the radius as needed
                      child: Image.network(
                        overlayImageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        // The background is decoration: a host that blocks
                        // hotlinking (or a web build without a CORS header) must
                        // leave the gradient and the Lottie alone, not throw.
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        loadingBuilder: (BuildContext context, Widget child,
                                ImageChunkEvent? progress) =>
                            progress == null ? child : const SizedBox.shrink(),
                      ),
                    ),
                  ),

                // 🔥 Foreground Lottie animation
                if (lottieAssetPath != null)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    top: 0,
                    child: SizedBox(
                      height: 12.h,
                      width: 12.h,
                      child: Lottie.asset(lottieAssetPath!,
                          fit: BoxFit.contain, repeat: true),
                    ),
                  ),

                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    // Vertical padding used to be 25, which left less room than
                    // two lines of title on a short window and clipped the second
                    // one inside the card's Stack.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21.sp,
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
