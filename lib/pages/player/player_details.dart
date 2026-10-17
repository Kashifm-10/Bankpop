import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerQRScannerScreen extends StatefulWidget {
  final bool scan;

  const PlayerQRScannerScreen({
    super.key,
    required this.scan,
  });

  @override
  State<PlayerQRScannerScreen> createState() => _PlayerQRScannerScreenState();
}

class _PlayerQRScannerScreenState extends State<PlayerQRScannerScreen> {
  // bool _scanned = false;
  // late final MobileScannerController cameraController;
  Timer? _approvalCheckTimer;
  final MobileScannerController cameraController = MobileScannerController();
  //final TextEditingController nameController = TextEditingController();
  bool _scanned = false;
  BarcodeCapture? _lastCapture;
  @override
  void initState() {
    super.initState();
    // cameraController = MobileScannerController();
  }

  @override
  void dispose() {
    cameraController.dispose();
    _approvalCheckTimer?.cancel();
    super.dispose();
  }

/*   void _showJoinDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
                      backgroundColor: Colors.yellow.shade50,

          title: Text('Enter your name'),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _scanned = false; // Reset scanned status
                cameraController.start();
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                if (_lastCapture != null) {
                  _onDetect(_lastCapture!);
                }
              },
              child: Text('Join'),
            ),
          ],
        );
      },
    );
  }
 */
  Future<void> _onDetect(BarcodeCapture capture) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? playerID = prefs.getString('playerID');
    final String playerName =
        prefs.getString('profile_name') ?? 'player${playerID!.substring(0, 3)}';

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final gameId = barcode.rawValue;

    if (gameId == null || gameId.isEmpty || playerID == null) return;

    final supabase = Supabase.instance.client;

    // Check if player already exists
    final existingPlayerResponse = await supabase
        .from('players_test')
        .select()
        .eq('game_id', gameId)
        .eq('player_id', playerID)
        .limit(1);

    final existingPlayerData = existingPlayerResponse;
    if (existingPlayerData.isEmpty) {
      // If player doesn't exist, insert a new record
      try {
        await supabase.from('request_test').insert({
          'game_id': gameId,
          'name': playerName, //nameController.text,
          'wallet': 0,
          'role': 'player',
          'player_id': playerID
        });
        await prefs.setString(
            'profile_name', playerName /* nameController.text */);
      } catch (e) {
        debugPrint('Error inserting request: $e');
        return;
      }
    } else if (existingPlayerData.isNotEmpty) {
      await Supabase.instance.client
          .from('players_test')
          .update({'name': playerName})
          .eq('game_id', gameId)
          .eq('player_id', playerID);
    }

    // ignore: use_build_context_synchronously
    _showWaitingDialog(context);

    final stopwatch = Stopwatch()..start();
    const pollInterval = Duration(seconds: 2);
    const maxWait = Duration(seconds: 10);

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

    Navigator.of(context).pop(); // Close waiting dialog

    if (approvedPlayer != null) {
      // ignore: use_build_context_synchronously
      Navigator.pop(context, approvedPlayer); // Return player data
    } else {
      _showUnableToJoinDialog();
    }
  }

  void _showWaitingDialog(BuildContext context) {
    int secondsRemaining = 15;
    late StateSetter setState;

    Timer? timer = Timer.periodic(Duration(seconds: 1), (t) {
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
              backgroundColor: Color(0xFFFFF8E1),
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
      timer
          .cancel(); // Ensure timer is cancelled if dialog is dismissed manually
    });
  }

  void _showUnableToJoinDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Color(0xFFFFF8E1),
        title: const Text("Unable to Join"),
        content: const Text("Approval not received within 1 minute."),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false), // Return to previous screen
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.yellow.shade50,
      appBar: AppBar(
        backgroundColor: Colors.yellow.shade50,
        title: const Text(
          'Scan Game QR',
          style: TextStyle(
            color: Color(0xFF689F38), // deep green icon
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: cameraController,
        onDetect: (capture) {
          if (_scanned) return;
          _scanned = true;
          _lastCapture = capture;
          cameraController.stop();
          //_showJoinDialog(context);
          _onDetect(_lastCapture!);
        },
      ),
    );
  }
}
