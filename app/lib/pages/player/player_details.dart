import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/bank_handover.dart';
import 'package:mon/services/camera_access.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/scanner_error_view.dart';
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

  /// The web needs a tap before it may open the camera (see ScannerStartView),
  /// but only the first time; after that CameraAccess starts it silently.
  bool _cameraOn = false;
  bool _checkedCamera = false;

  @override
  void initState() {
    super.initState();
    _prepareCamera();
  }

  Future<void> _prepareCamera() async {
    final bool granted = await CameraAccess.isGranted();
    if (!mounted) return;
    setState(() {
      _cameraOn = granted;
      _checkedCamera = true;
    });
  }

  void _startCamera() {
    CameraAccess.remember();
    setState(() => _cameraOn = true);
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
    if (_scanned) return;
    if (capture.barcodes.isEmpty) return;
    final String? raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    // The camera is released before the join flow starts its round trips, and
    // the release is awaited: an un-awaited stop() leaves the analyzer running
    // behind the waiting dialog.
    _scanned = true;
    await cameraController.stop();

    // A banker's hand-over code is not a join: it asks this player to take the
    // bank, and only a player who is not already in the game may answer it.
    final HandoverInvite? invite = BankHandover.parse(raw.trim());
    if (invite != null) {
      await _takeOverBank(invite);
      return;
    }

    await _joinGame(raw.trim());
  }

  /// Claims the bank on the banker's screen, then waits for their confirmation.
  ///
  /// Scanning alone changes nothing. The claim is queued, the banker confirms
  /// it on their own device, and this screen notices when the bank row becomes
  /// this player's - opening the banker table at that point.
  Future<void> _takeOverBank(HandoverInvite invite) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String playerID = prefs.getString('playerID') ?? '';
    final String playerName = prefs.getString('profile_name') ??
        (playerID.isEmpty
            ? 'Player'
            : 'player${playerID.substring(0, playerID.length < 3 ? playerID.length : 3)}');

    final HandoverClaim claim = await BankHandover.claim(
      invite: invite,
      playerId: playerID,
      playerName: playerName,
    );
    if (!mounted) return;
    if (!claim.queued) {
      showMessage(context, claim.rejection ?? 'The bank did not change hands.');
      _scanned = false;
      if (_cameraOn) await cameraController.start();
      return;
    }

    bool waitingOpen = true;
    bool cancelled = false;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: const Text('Waiting for the banker'),
        content: const Text(
          'The banker has been asked to hand you the bank. Keep this screen '
          'open until they confirm.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              cancelled = true;
              waitingOpen = false;
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ));

    bool promoted = false;
    // Two minutes is long enough for the banker to look up and tap, and short
    // enough that a claim is not left waiting on a table nobody is watching.
    for (int tick = 0; tick < 60 && !cancelled; tick++) {
      if (await BankHandover.holdsBank(claim.gameId, playerID)) {
        promoted = true;
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    if (mounted && waitingOpen) {
      // The dialog is the top route; the cancel button has already closed it
      // and cleared the flag in that case.
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;

    if (!promoted) {
      // Take the claim back, so the banker is not asked to confirm a player who
      // has stopped waiting.
      final List<HandoverRequest> pending =
          await BankHandover.pending(claim.gameId);
      for (final HandoverRequest request in pending) {
        if (request.playerId == playerID) await BankHandover.withdraw(request);
      }
      if (!mounted) return;
      showMessage(
        context,
        cancelled
            ? 'The bank did not change hands.'
            : 'The banker did not confirm in time, so the request was '
                'withdrawn. Scan the code again when they are ready.',
      );
      _scanned = false;
      if (_cameraOn) await cameraController.start();
      return;
    }

    await prefs.setString('gameID', claim.gameId);
    await prefs.setString('role', 'banker');
    await prefs.setString('display_name', claim.name);
    if (!mounted) return;
    showMessage(
      context,
      '${claim.name}, you are the banker now. The bank balance and every '
      'control moved to this device.',
      title: 'You have the bank',
    );
    if (!mounted) return;
    context.go(AppRoutes.banker(claim.gameId));
  }

  /// The join QR carries the bare five-character code, but the same scanner can
  /// meet a JSON payload (or a code typed in the other case). Neither should be
  /// the reason a join silently does nothing.
  static String _codeFromPayload(String raw) {
    final String trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return trimmed;
    try {
      final Map<String, dynamic> data =
          jsonDecode(trimmed) as Map<String, dynamic>;
      return (data['gameId'] ?? data['game_id'] ?? data['code'] ?? '')
          .toString()
          .trim();
    } catch (error) {
      return trimmed;
    }
  }

  /// The game's own spelling of [raw], or null when no such game exists.
  Future<String?> _resolveGameId(String raw) async {
    final String code = _codeFromPayload(raw);
    if (code.isEmpty || code.length > 64) return null;
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('players_test')
          .select('game_id')
          .ilike('game_id', code)
          .limit(1);
      if (rows.isEmpty) return null;
      return rows.first['game_id']?.toString();
    } catch (error) {
      debugPrint('Could not look up game $code: $error');
      return null;
    }
  }

  /// Everything the scanner and the manual code entry share.
  Future<void> _joinGame(String rawGameId) async {
    final String? resolved = await _resolveGameId(rawGameId);
    if (!mounted) return;
    if (resolved == null) {
      showMessage(context, 'No game found with that code.');
      // Let the player scan again instead of leaving a dead camera behind.
      _scanned = false;
      if (_cameraOn) await cameraController.start();
      return;
    }
    final String gameId = resolved;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? playerID = prefs.getString('playerID');
    if (playerID == null) {
      // Say so and hand the camera back. A silent return here looks exactly
      // like a scanner that stopped working.
      if (mounted) {
        showMessage(
            context, 'This device has no player id. Please restart the app.');
      }
      _scanned = false;
      if (_cameraOn) await cameraController.start();
      return;
    }
    final String playerName = prefs.getString('profile_name') ??
        'player${playerID.substring(0, playerID.length < 3 ? playerID.length : 3)}';

    // A game that has ended must not accept new players - the banker would
    // otherwise be approving somebody into a finished board.
    final GameSession? session = await GameSession.fetch(gameId);
    if (session != null && session.isEnded) {
      if (mounted) showMessage(context, 'That game has already ended.');
      _scanned = false;
      await cameraController.start();
      return;
    }

    final supabase = Supabase.instance.client;

    // Check if player already exists
    final existingPlayerResponse = await supabase
        .from('players_test')
        .select()
        .eq('game_id', gameId)
        .eq('player_id', playerID)
        .limit(1);

    final existingPlayerData = existingPlayerResponse;

    // A player the banker removed has no way back in: their seat, their cash
    // and their cards all went to the bank. Say so instead of quietly failing
    // to be approved.
    for (final dynamic raw in existingPlayerData) {
      final Map<String, dynamic> row = (raw as Map).cast<String, dynamic>();
      if (PlayerStanding.fromRow(row) != PlayerStanding.kicked) continue;
      if (mounted) {
        await showAppDialog<void>(
          context,
          title: 'You were removed',
          icon: Icons.person_remove_alt_1,
          accent: const Color(0xFFC62828),
          message: 'The banker removed you from this game, so there is no seat '
              'to rejoin. Ask them to start a new game if you want to play '
              'again.',
          actions: <Widget>[
            AppDialogButton(
              label: 'OK',
              primary: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      }
      _scanned = false;
      if (_cameraOn) await cameraController.start();
      return;
    }

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
        // Hand the scanner back instead of leaving a frozen camera: this is
        // the same dead end a missing player id used to create.
        _scanned = false;
        if (_cameraOn) await cameraController.start();
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
            tooltip: 'Enter the game code instead',
            icon: Image.asset(
              'assets/Icons/keypad.png',
              width: 24,
              height: 24,
              fit: BoxFit.contain,
            ),
            onPressed: _promptForGameId,
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: !_checkedCamera
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF689F38)),
            )
          : !_cameraOn
              ? ScannerStartView(
                  title: 'Scan the bank\'s QR',
                  body: 'Point the camera at the QR under the banker\'s game '
                      'code, or type the five-character code instead. The '
                      'camera is only asked once.',
                  onStart: _startCamera,
                  onManualEntry: _promptForGameId,
                  manualLabel: 'Enter game ID',
                )
              : MobileScanner(
                  controller: cameraController,
                  errorBuilder: (BuildContext context,
                      MobileScannerException error, Widget? child) {
                    // A denied or revoked permission has to be explained again
                    // next time rather than failing silently.
                    CameraAccess.forget();
                    return ScannerErrorView(
                      error: error,
                      onRetry: () => cameraController.start(),
                      onManualEntry: _promptForGameId,
                      manualLabel: 'Enter game ID',
                    );
                  },
                  onDetect: _onDetect,
                ),
    );
  }

  /// The join code is five characters shown under the bank's QR. Typing it is
  /// the only way in on a desktop browser without a camera, and the quickest
  /// way on a phone that is already holding the code in another app.
  Future<void> _promptForGameId() async {
    final TextEditingController controller = TextEditingController();
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Enter Game ID'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Game ID'),
          onSubmitted: (String value) => Navigator.pop(context, value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    final String trimmed = code?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (_scanned) return;
    _scanned = true;
    await cameraController.stop();
    // Case is resolved against the database, not by guessing here.
    await _joinGame(trimmed);
  }
}
