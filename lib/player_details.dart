import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerQRScannerScreen extends StatefulWidget {
  final String playerName;
  final double wallet;

  const PlayerQRScannerScreen({
    super.key,
    required this.playerName,
    required this.wallet,
  });

  @override
  State<PlayerQRScannerScreen> createState() => _PlayerQRScannerScreenState();
}

class _PlayerQRScannerScreenState extends State<PlayerQRScannerScreen> {
  // bool _scanned = false;
  // late final MobileScannerController cameraController;
  Timer? _approvalCheckTimer;
  bool _approved = false;
  final MobileScannerController cameraController = MobileScannerController();
  final TextEditingController nameController = TextEditingController();
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

  void _showJoinDialog(BuildContext context) {
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

  Future<void> _onDetect(BarcodeCapture capture) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? playerID = prefs.getString('playerID');

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

    final existingPlayerData = existingPlayerResponse as List<dynamic>;
    if (existingPlayerData.isEmpty) {
      // If player doesn't exist, insert a new record
      try {
        await supabase.from('request_test').insert({
          'game_id': gameId,
          'name': nameController.text,
          'wallet': 0,
          'role': 'player',
          'player_id': playerID
        });
        await prefs.setString('name', nameController.text);
      } catch (e) {
        debugPrint('Error inserting request: $e');
        return;
      }
    }

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
          //.eq('name', nameController.text)
          .limit(1);

      final data = response as List<dynamic>;
      if (data.isNotEmpty) {
        approvedPlayer = data.first as Map<String, dynamic>;
        break;
      }

      await Future.delayed(pollInterval);
    }

    Navigator.of(context).pop(); // Close waiting dialog

    if (approvedPlayer != null) {
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

  void _showUnableToJoinDialog() {
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
        title: const Text('Scan Game QR'),
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
          _showJoinDialog(context);
        },
      ),
    );
  }
}
