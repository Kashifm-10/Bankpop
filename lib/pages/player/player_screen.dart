import 'dart:async';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/pages/transactions/pay.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:mon/pages/transactions/receive.dart';
import 'package:mon/pages/transactions/transactions.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home.dart';

class Player {
  final String playerID;
  final String name;
  final double value;
  final Color color;
  final String avatar;

  Player(
      {required this.playerID,
      required this.name,
      required this.value,
      required this.color,
      required this.avatar});

  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
        playerID: map['player_id'],
        name: map['name'],
        value: double.tryParse(map['wallet'].toString()) ?? 0.0,
        color: Colors.primaries[map['name'].hashCode % Colors.primaries.length],
        avatar: map['avatar'] ?? "assets/avatars/boy1.jpg");
  }

  /// Value equality, so `listEquals` in the screens can tell "the roster did not
  /// change" apart from "the wallet moved" and skip the rebuild. `color` is
  /// derived from `name`, so it does not take part.
  @override
  bool operator ==(Object other) {
    return other is Player &&
        other.playerID == playerID &&
        other.name == name &&
        other.value == value &&
        other.avatar == avatar;
  }

  @override
  int get hashCode => Object.hash(playerID, name, value, avatar);
}

class PlayersScreen extends StatefulWidget {
  final String gameId;
  final double bankValue;

  const PlayersScreen({
    Key? key,
    required this.gameId,
    required this.bankValue,
  }) : super(key: key);

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  List<Player> players = [];
  bool isLoading = true;
  Timer? pollingTimer;
  double value = 0;
  String? playerID;
  String? currentPlayerName;
  double? previousWallet;
  int playerPosition = 1;
  String positionStatus = 'none';
  String payOption = 'InstantPay';

  bool _isFetching = false; // One poll in flight at a time
  StreamSubscription<List<Map<String, dynamic>>>? _rosterUpdates;

  /// Digits of this device's id, padded so the wallet-card slices below can
  /// never throw: the old code called `substring(0, 4)` directly, which blew up
  /// on any id with fewer than four digits and blanked the whole screen.
  String get _cardDigits =>
      (playerID ?? '').replaceAll(RegExp(r'\D'), '').padLeft(4, '0');

  /// Cardholder name, safe to render before prefs have loaded and for an empty
  /// name (the old code indexed `[0]` and threw).
  String get _cardName {
    final String? raw = currentPlayerName;
    if (raw == null || raw.isEmpty) return '';
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

  String get _cardNameLowered {
    final String? raw = currentPlayerName;
    if (raw == null || raw.isEmpty) return '';
    return '${raw[0].toUpperCase()}${raw.substring(1).toLowerCase()}';
  }

  @override
  void initState() {
    super.initState();
    value = widget.bankValue;
    fetchCurrentPlayerName();
    _refreshRoster(); // Initial load
    _subscribeToRoster(); // Live updates
    startPolling(); // Reconciliation, in case Realtime is unavailable
    setAvatar();
  }

  @override
  void dispose() {
    _rosterUpdates?.cancel();
    pollingTimer?.cancel();
    super.dispose();
  }

  /// Live roster for this game. Supabase Realtime pushes a change the moment a
  /// wallet moves, so the screen no longer has to ask for one. If the socket is
  /// unavailable the stream reports the error and the reconciliation timer
  /// below keeps the screen correct anyway.
  void _subscribeToRoster() {
    try {
      _rosterUpdates = Supabase.instance.client
          .from('players_test')
          .stream(primaryKey: const ['id'])
          .eq('game_id', widget.gameId)
          .listen(
            _applyRosterRows,
            onError: (Object error) =>
                debugPrint('Roster stream error, still polling: $error'),
          );
    } catch (e) {
      debugPrint('Could not subscribe to roster updates: $e');
    }
  }

  void startPolling() {
    // Reconciliation only: live changes arrive over the socket, so this is a
    // safety net rather than the way the screen stays up to date.
    pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshRoster();
    });
  }

  /// One request at a time, so a slow tick cannot stack up requests.
  Future<void> _refreshRoster() async {
    if (_isFetching) return; // Skip this tick instead of stacking requests
    _isFetching = true;
    try {
      // No server-side sort: the roster is a handful of rows and sorting them
      // here means the indexed (game_id, role) lookup is all the backend does.
      final response = await Supabase.instance.client
          .from('players_test')
          .select()
          .eq('game_id', widget.gameId)
          .eq('role', 'player');

      _applyRosterRows(
          (response as List<dynamic>).cast<Map<String, dynamic>>());
    } catch (e) {
      debugPrint('Error fetching players: $e');
    } finally {
      _isFetching = false;
    }
  }

  /// The single place roster rows become screen state. Both the Realtime stream
  /// and the reconciliation poll land here, so a live update and a polled one
  /// can never produce a different screen.
  void _applyRosterRows(List<Map<String, dynamic>> rows) {
    if (!mounted) return;

    final List<Map<String, dynamic>> roster = rows
        .where((Map<String, dynamic> row) => row['role'] == 'player')
        .toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          ((b['wallet'] as num?) ?? 0).compareTo((a['wallet'] as num?) ?? 0));

    final List<Player> updatedPlayers =
        roster.map((Map<String, dynamic> row) => Player.fromMap(row)).toList();

    // `isLoading` has to clear even when the roster is unchanged, otherwise an
    // empty game would spin on the loading indicator forever.
    if (isLoading || !listEquals(players, updatedPlayers)) {
      setState(() {
        players = updatedPlayers;
        isLoading = false;
      });
    }

    _applyMyPlayer(roster);
  }

  /// Derives this device's wallet, rank and pay option from the roster that was
  /// just received, instead of asking the backend for them separately.
  void _applyMyPlayer(List<Map<String, dynamic>> roster) {
    final String? id = playerID;
    if (id == null) return;

    final int index =
        roster.indexWhere((Map<String, dynamic> row) => row['player_id'] == id);
    if (index == -1) {
      debugPrint('Current player not found in the list.');
      return;
    }

    final Map<String, dynamic> currentPlayer = roster[index];
    final num wallet = (currentPlayer['wallet'] as num?) ?? 0;
    final int position = index + 1; // 1-based position
    final int totalPlayers = roster.length;

    // Determine position label
    String positionLabel;
    if (position == 1) {
      positionLabel = 'first';
    } else if (position == 2) {
      positionLabel = 'second';
    } else if (position == totalPlayers) {
      positionLabel = 'last';
    } else if (position == totalPlayers - 1) {
      positionLabel = 'almostlast';
    } else {
      positionLabel = ''; // Optional: handle other positions if needed
    }

    // The wallet card renders this name, so fall back to the roster's copy when
    // this device has no profile name stored yet.
    final String? name = currentPlayerName ?? currentPlayer['name'] as String?;
    final double newValue = double.parse(wallet.toStringAsFixed(2));
    final String newPayOption =
        (currentPlayer['SP/IP'] as String?) ?? payOption;

    // `_applyRosterRows` above skips its setState when the roster is unchanged,
    // but a setState here would mark the screen dirty anyway - and this runs on
    // every roster event and every reconciliation tick, so an idle game was
    // still rebuilding the whole screen every 5 seconds. Compare before
    // rebuilding, the way the banker screen already does for its bank header.
    if (currentPlayerName != name ||
        value != newValue ||
        playerPosition != position ||
        positionStatus != positionLabel ||
        payOption != newPayOption) {
      setState(() {
        currentPlayerName = name;
        value = newValue;
        playerPosition = position;
        positionStatus = positionLabel;
        payOption = newPayOption;
      });
    }

    // Show SnackBar only if there's a change
    if (previousWallet != null) {
      if (wallet > previousWallet!) {
        notification('received', (wallet - previousWallet!).toStringAsFixed(2));
      } else if (wallet < previousWallet! && payOption == 'ScanPay') {
        notification('paid', (previousWallet! - wallet).toStringAsFixed(2));
      }
    }

    previousWallet = wallet.toDouble();
  }

  Future<void> fetchCurrentPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gameID', widget.gameId);

    // This device is playing as a player in this game. Store the role and the
    // display name in prefs so the QR generator (receive.dart) can build the
    // correct payload without a database round-trip.
    final profileName = prefs.getString('profile_name');
    await prefs.setString('role', 'player');
    await prefs.setString('display_name', profileName ?? 'Player');

    if (!mounted) return;
    setState(() {
      // Read once at startup instead of on every tick.
      playerID ??= prefs.getString('playerID');
      currentPlayerName ??= profileName;
    });
  }

  Future<void> setAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final avatar = prefs.getString('avatar_path');
    playerID = prefs.getString('playerID');
    if (playerID == null) return;

    final supabase = Supabase.instance.client;
    try {
      // This runs on every screen open, and the stored avatar is almost always
      // already current. One write per open also invalidates every other device
      // in the game, so compare first and write only on a real change.
      final existing = await supabase
          .from('players_test')
          .select('avatar')
          .eq('game_id', widget.gameId)
          .eq('player_id', playerID!)
          .maybeSingle();

      if (existing != null && existing['avatar'] == avatar) return;

      await supabase
          .from('players_test')
          .update({'avatar': avatar})
          .eq('game_id', widget.gameId)
          .eq('player_id', playerID!);
    } catch (e) {
      debugPrint('Error updating avatar: $e');
    }
  }

  void notification(String message, String value) {
    final contentType = {
          'paid': ContentType.success,
          'received': ContentType.success,
          'failed': ContentType.failure,
          'warning': ContentType.warning,
          'help': ContentType.help,
        }[message.toLowerCase()] ??
        ContentType.help;

    final materialBanner = MaterialBanner(
      shadowColor: Colors.transparent,
      forceActionsBelow: true,
      backgroundColor: Colors.transparent,
      elevation: 1,
      content: AwesomeSnackbarContent(
        title: _getSnackbarTitle(message),
        message: "${message[0].toUpperCase()}${message.substring(1)} $value",
        contentType: contentType,
        inMaterialBanner: true,
      ),
      actions: const [SizedBox.shrink()],
    );

    // Show the MaterialBanner
    ScaffoldMessenger.of(context)
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(materialBanner);

    // Auto-dismiss after 2 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (ScaffoldMessenger.of(context).mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });
  }

  String _getSnackbarTitle(String message) {
    switch (message.toLowerCase()) {
      case 'paid':
        return 'Payment Successful';
      case 'received':
        return 'Received';
      case 'failed':
        return 'Transaction Failed';
      case 'warning':
        return 'Warning';
      case 'help':
        return 'Help';
      default:
        return 'Notice';
    }
  }

  Future<void> payPlayer(Player player) async {
    bool isProcessing = false;
    final TextEditingController amountController = TextEditingController();
    isProcessing = false;
    double? enteredAmount;
    String statusLabel = "Enter Amount"; // dynamic label
    enteredAmount = await showDialog<double>(
      barrierDismissible: false,
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Stack(
              children: [
                Positioned(
                  bottom: 27.h,
                  right: 0,
                  left: 0,
                  child: Transform.rotate(
                    angle: 1.5708, // 90 degrees in radians
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      color: Colors.blueGrey.shade500,
                      elevation: 2,
                      child: Stack(
                        children: [
                          Positioned(
                            bottom: 0,
                            right: 10,
                            child: Image.asset(
                              'assets/images/c_logo.png',
                              fit: BoxFit.contain,
                              // Decoded at 160px wide. The source is 2456x1612,
                              // so drawing it at 23.sp used to hold 15 MB of
                              // bitmap and pay the full decode for a logo this
                              // size. 160 leaves room for wide phones.
                              cacheWidth: 160,

                              width: 23
                                  .sp, // Use MediaQuery or a fixed size if sp is undefined
                              height: 23.sp,
                              colorBlendMode: BlendMode
                                  .srcIn, // Ensures image is tinted red
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Row for Cardholder's Name and Card Number
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Cardholder's name
                                        Row(
                                          children: [
                                            Text(
                                              _cardNameLowered,
                                              style: TextStyle(
                                                fontSize: 18.sp,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            )
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        // Dummy credit card number
                                        Text(
                                          '**** **** **** ${_cardDigits.substring(0, 4)}', // First 4 digits of this device's id
                                          style: TextStyle(
                                            fontSize: 22.sp,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blueGrey.shade100,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Lottie.asset(
                                      positionStatus == "first"
                                          ? 'assets/lottie/first.json'
                                          : positionStatus == "second"
                                              ? 'assets/lottie/second.json'
                                              : positionStatus == "almostlast"
                                                  ? 'assets/lottie/almost_last.json'
                                                  : positionStatus == "last"
                                                      ? 'assets/lottie/last.json'
                                                      : 'assets/lottie/neutral.json',
                                      height: 10.h,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 15),

                                // Row for Expiration Date and CVV
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    AnimatedFlipCounter(
                                      value: value,
                                      fractionDigits: 2,
                                      textStyle: TextStyle(
                                        fontSize: 28.sp,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                      ),
                                      duration:
                                          const Duration(milliseconds: 500),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'EXPIRY',
                                                style: TextStyle(
                                                  fontSize: 12.sp,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.7),
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                DateFormat('MM/yy')
                                                    .format(DateTime.now()),
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      Colors.blueGrey.shade100,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 20),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'CVV',
                                                style: TextStyle(
                                                  fontSize: 12.sp,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.7),
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                '***', // Dummy CVV
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      Colors.blueGrey.shade100,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AlertDialog(
                  backgroundColor: Colors.grey.shade500,
                  content: SizedBox(
                    width: 50.w, // adjust as needed
                    //  height: 30.h, // adjust as needed

                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          children: [
                            const SizedBox(height: 10),
                            Container(
                              margin: const EdgeInsets.symmetric(
                                  vertical: 0, horizontal: 10),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 10),
                              width: double.infinity,
                              // height: 7.h,
                              decoration: BoxDecoration(
                                color: Colors.green.shade400,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  /*  Align(alignment: Alignment.topLeft,
                                    child: Text(
                                      "Paying to ${player.name}",
                                      style: const TextStyle(color: Colors.black),
                                    ),
                                  ), */
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                        color: Colors.black, fontSize: 16.sp),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    amountController.text.isEmpty
                                        ? '0'
                                        : amountController.text,
                                    style: TextStyle(
                                        color: Colors.black, fontSize: 16.sp),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Row 1
                            GridView.count(
                              childAspectRatio: 2,
                              shrinkWrap: true,
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              children: [
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '1';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '1',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '2';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '2',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '3';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '3',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '4';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '4',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '5';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '5',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '6';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '6',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '7';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '7',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '8';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '8',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '9';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '9',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing ||
                                          amountController.text.contains('.')
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '.';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '0';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '0',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            if (amountController
                                                .text.isNotEmpty) {
                                              amountController.text =
                                                  amountController.text
                                                      .substring(
                                                          0,
                                                          amountController
                                                                  .text.length -
                                                              1);
                                            }
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Icon(Icons.backspace,
                                      color: Colors.grey),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          Navigator.of(context).pop();
                                        },
                                  style: ElevatedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white),
                                  child: const Text('X'),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.clear();
                                          });
                                        },
                                  style: ElevatedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      backgroundColor: Colors.yellow,
                                      foregroundColor: Colors.black),
                                  child: const Text('C'),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () async {
                                          final value = double.tryParse(
                                              amountController.text);
                                          if (value != null && value > 0) {
                                            setState(() {
                                              isProcessing = true;
                                              statusLabel =
                                                  "Processing payment...";
                                            });

                                            // Simulate the processing delay
                                            await Future.delayed(
                                                const Duration(seconds: 2));

                                            // Perform the actual payment logic
                                            final prefs =
                                                await SharedPreferences
                                                    .getInstance();
                                            final payerPlayerID =
                                                prefs.getString('playerID') ??
                                                    'UnknownPlayer';
                                            enteredAmount =
                                                value; // Set enteredAmount here

                                            // Fetch player and banker wallet data from Supabase
                                            final payerResponse = await Supabase
                                                .instance.client
                                                .from('players_test')
                                                .select('wallet')
                                                .eq('game_id', widget.gameId)
                                                .eq('player_id', payerPlayerID)
                                                .maybeSingle();

                                            final receiverResponse =
                                                await Supabase.instance.client
                                                    .from('players_test')
                                                    .select('wallet')
                                                    .eq('game_id',
                                                        widget.gameId)
                                                    .eq('player_id',
                                                        player.playerID)
                                                    .maybeSingle();

                                            if (payerResponse != null &&
                                                receiverResponse != null &&
                                                payerResponse['wallet'] !=
                                                    null &&
                                                receiverResponse['wallet'] !=
                                                    null) {
                                              double payerWallet =
                                                  (payerResponse['wallet']
                                                          as num)
                                                      .toDouble();
                                              if (payerWallet >=
                                                  enteredAmount!) {
                                                // One atomic call: the database
                                                // locks both rows, re-checks the
                                                // funds and writes both wallets,
                                                // so a payment landing at the same
                                                // moment can no longer lose this
                                                // one.
                                                final TransferOutcome transfer =
                                                    await WalletTransfer.pay(
                                                  gameId: widget.gameId,
                                                  fromId: payerPlayerID,
                                                  fromRole:
                                                      WalletTransfer.playerRole,
                                                  toId: player.playerID,
                                                  toRole:
                                                      WalletTransfer.playerRole,
                                                  amount: enteredAmount!,
                                                );

                                                if (!transfer.ok) {
                                                  setState(() {
                                                    statusLabel =
                                                        "Insufficient balance X";
                                                    isProcessing =
                                                        false; // Allow retry
                                                  });
                                                  return;
                                                }
                                                await Supabase.instance.client
                                                    .from('transactions')
                                                    .insert({
                                                  'game_id': widget.gameId,
                                                  'value': enteredAmount!,
                                                  'from': currentPlayerName,
                                                  'to': player.name,
                                                  'code':
                                                      "${payerPlayerID}_${player.playerID}",
                                                  'date': DateFormat(
                                                          'yyyy-MM-dd')
                                                      .format(DateTime.now()),
                                                  'time': DateFormat('HH:mm:ss')
                                                      .format(DateTime.now()),
                                                });
                                                // Show success message
                                                setState(() {
                                                  statusLabel =
                                                      "Payment Successful ✓";
                                                });

                                                // Close the dialog after a delay
                                                await Future.delayed(
                                                    const Duration(seconds: 2));
                                                Navigator.of(context).pop();
                                              } else {
                                                // Insufficient funds
                                                setState(() {
                                                  statusLabel =
                                                      "Insufficient balance X";
                                                  isProcessing =
                                                      false; // Allow retry
                                                });
                                              }
                                            } else {
                                              // Failed to fetch wallet data
                                              setState(() {
                                                statusLabel =
                                                    "Failed to fetch wallet data ⊘";
                                              });

                                              /*  await Future.delayed(
                                                  const Duration(seconds: 2));
                                              Navigator.of(context).pop(); */
                                            }
                                          } else {
                                            // Invalid amount entered
                                            setState(() {
                                              statusLabel = "Invalid amount !!";
                                            });
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white),
                                  child: const Icon(Icons.keyboard_arrow_right),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (enteredAmount == null) return; // user cancelled or invalid input
  }

  Widget _buildPlayerRow(Player player) {
    final bool isCurrentPlayer = player.name == currentPlayerName;

    return Container(
      height: 6.h,
      padding: EdgeInsets.symmetric(vertical: 0.h, horizontal: 10),
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: player.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2.w),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18.sp,
            backgroundColor:
                Colors.transparent, // pale mint green bg for subtle pop
            // Decoded at 144px: the source avatars are 500-1200px, so a 36.sp
            // circle was pulling a multi-megabyte bitmap into memory per player.
            backgroundImage: ResizeImage(AssetImage(player.avatar), width: 144),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(
              !isCurrentPlayer
                  ? '${player.name[0].toUpperCase()}${player.name.substring(1)}'
                  : "${player.name[0].toUpperCase()}${player.name.substring(1)} (me)",
              style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w600,
                  color: player.color),
            ),
          ),
          Expanded(
            flex: 4,
            child: AnimatedFlipCounter(
              mainAxisAlignment: MainAxisAlignment.end,
              value: player.value,
              fractionDigits: 2,
              textStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16.sp,
                color: player.color,
              ),
              duration: const Duration(milliseconds: 500), // optional
            ),
          ),
          const SizedBox(width: 10),
          if (payOption != 'ScanPay')
            Padding(
              padding: const EdgeInsets.all(5.0),
              child: ElevatedButton(
                onPressed: () async {
                  if (!isCurrentPlayer && payOption != 'ScanPay') {
                    payPlayer(player);
                  }
                },
                style: ElevatedButton.styleFrom(
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.all(5), // Remove internal padding

                  fixedSize: Size(25.sp, 20.sp), // 👈 Set button size here

                  elevation: 0,
                  foregroundColor: player.color,
                  backgroundColor: isCurrentPlayer && payOption != 'ScanPay'
                      ? Colors.transparent
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Image.asset(
                  'assets/images/pay.png', fit: BoxFit.contain,

                  width: 23
                      .sp, // Use MediaQuery or a fixed size if sp is undefined
                  height: 23.sp,
                  color: isCurrentPlayer && payOption != 'ScanPay'
                      ? Colors.transparent
                      : Color(0xFF689F38), // Apply red color
                  colorBlendMode:
                      BlendMode.srcIn, // Ensures image is tinted red
                ),
              ),
            )

          /*  if (!isCurrentPlayer)
            Expanded(
              flex: 5,
              child: Wrap(
                spacing: 2.w,
                runSpacing: 1.h,
                children: [
                  /*  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Receive from ${player.name}')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: Size(22.w, 5.h),
                    ),
                    child: const Text('Receive'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Pay to ${player.name}')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: Size(22.w, 5.h),
                    ),
                    child: const Text('Pay'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Advance for ${player.name}')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      minimumSize: Size(22.w, 5.h),
                    ),
                    child: const Text('Advance'),
                  ), */
                ],
              ),
            ), */
        ],
      ),
    );
  }

  Future<bool> _onWillPop() async {
    // Show confirmation dialog before leaving the game
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFFF8E1),
          title: const Text("Leave Game"),
          content: const Text("Are you sure you want to leave the game?"),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Leave"),
            ),
          ],
        );
      },
    );

    return shouldLeave ??
        false; // If the user cancels, return false, else return true to pop
  }

  Future<void> payBank() async {
    bool isProcessing = false;
    final TextEditingController amountController = TextEditingController();
    isProcessing = false;
    double? enteredAmount;
    String statusLabel = "Enter Amount"; // dynamic label
    enteredAmount = await showDialog<double>(
      barrierDismissible: false,
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Stack(
              children: [
                Positioned(
                  bottom: 27.h,
                  right: 0,
                  left: 0,
                  child: Transform.rotate(
                    angle: 1.5708, // 90 degrees in radians
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      color: Colors.blueGrey.shade500,
                      elevation: 2,
                      child: Stack(
                        children: [
                          Positioned(
                            bottom: 0,
                            right: 10,
                            child: Image.asset(
                              'assets/images/c_logo.png',
                              fit: BoxFit.contain,
                              // Decoded at 160px wide. The source is 2456x1612,
                              // so drawing it at 23.sp used to hold 15 MB of
                              // bitmap and pay the full decode for a logo this
                              // size. 160 leaves room for wide phones.
                              cacheWidth: 160,

                              width: 23
                                  .sp, // Use MediaQuery or a fixed size if sp is undefined
                              height: 23.sp,
                              colorBlendMode: BlendMode
                                  .srcIn, // Ensures image is tinted red
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Row for Cardholder's Name and Card Number
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Cardholder's name
                                        Row(
                                          children: [
                                            Text(
                                              _cardName,
                                              style: TextStyle(
                                                fontSize: 18.sp,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            )
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        // Dummy credit card number
                                        Text(
                                          '**** **** **** ${_cardDigits.substring(0, 4)}', // First 4 digits of this device's id
                                          style: TextStyle(
                                            fontSize: 22.sp,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blueGrey.shade100,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Lottie.asset(
                                      positionStatus == "first"
                                          ? 'assets/lottie/first.json'
                                          : positionStatus == "second"
                                              ? 'assets/lottie/second.json'
                                              : positionStatus == "almostlast"
                                                  ? 'assets/lottie/almost_last.json'
                                                  : positionStatus == "last"
                                                      ? 'assets/lottie/last.json'
                                                      : 'assets/lottie/neutral.json',
                                      height: 10.h,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 15),

                                // Row for Expiration Date and CVV
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    AnimatedFlipCounter(
                                      value: value,
                                      fractionDigits: 2,
                                      textStyle: TextStyle(
                                        fontSize: 28.sp,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                      ),
                                      duration:
                                          const Duration(milliseconds: 500),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'EXPIRY',
                                                style: TextStyle(
                                                  fontSize: 12.sp,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.7),
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                DateFormat('MM/yy')
                                                    .format(DateTime.now()),
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      Colors.blueGrey.shade100,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 20),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'CVV',
                                                style: TextStyle(
                                                  fontSize: 12.sp,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.7),
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _cardDigits.substring(
                                                    _cardDigits.length -
                                                        3), // Dummy CVV
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      Colors.blueGrey.shade100,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AlertDialog(
                  backgroundColor: Colors.grey.shade500,
                  content: SizedBox(
                    width: 50.w, // adjust as needed
                    //  height: 30.h, // adjust as needed

                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          children: [
                            const SizedBox(height: 10),
                            Container(
                              margin: const EdgeInsets.symmetric(
                                  vertical: 0, horizontal: 10),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 10),
                              width: double.infinity,
                              // height: 7.h,
                              decoration: BoxDecoration(
                                color: Colors.green.shade400,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  /*  Align(alignment: Alignment.topLeft,
                                    child: Text(
                                      "Paying to ${player.name}",
                                      style: const TextStyle(color: Colors.black),
                                    ),
                                  ), */
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                        color: Colors.black, fontSize: 16.sp),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    amountController.text.isEmpty
                                        ? '0'
                                        : amountController.text,
                                    style: TextStyle(
                                        color: Colors.black, fontSize: 16.sp),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Row 1
                            GridView.count(
                              childAspectRatio: 2,
                              shrinkWrap: true,
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              children: [
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '1';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '1',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '2';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '2',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '3';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '3',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '4';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '4',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '5';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '5',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '6';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '6',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '7';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '7',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '8';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '8',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '9';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '9',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing ||
                                          amountController.text.contains('.')
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '.';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.text += '0';
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Text(
                                    '0',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            if (amountController
                                                .text.isNotEmpty) {
                                              amountController.text =
                                                  amountController.text
                                                      .substring(
                                                          0,
                                                          amountController
                                                                  .text.length -
                                                              1);
                                            }
                                          });
                                        },
                                  style: _buttonStyle(),
                                  child: const Icon(Icons.backspace,
                                      color: Colors.grey),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          Navigator.of(context).pop();
                                        },
                                  style: ElevatedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white),
                                  child: const Text('X'),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () {
                                          setState(() {
                                            amountController.clear();
                                          });
                                        },
                                  style: ElevatedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      backgroundColor: Colors.yellow,
                                      foregroundColor: Colors.black),
                                  child: const Text('C'),
                                ),
                                ElevatedButton(
                                  onPressed: isProcessing
                                      ? null
                                      : () async {
                                          final value = double.tryParse(
                                              amountController.text);
                                          if (value != null && value > 0) {
                                            setState(() {
                                              isProcessing = true;
                                              statusLabel =
                                                  "Processing payment...";
                                            });

                                            // Simulate the processing delay
                                            await Future.delayed(
                                                const Duration(seconds: 2));

                                            // Perform the actual payment logic
                                            final prefs =
                                                await SharedPreferences
                                                    .getInstance();
                                            final payerPlayerID =
                                                prefs.getString('playerID') ??
                                                    'UnknownPlayer';
                                            enteredAmount =
                                                value; // Set enteredAmount here

                                            // Fetch player and banker wallet data from Supabase
                                            final payerResponse = await Supabase
                                                .instance.client
                                                .from('players_test')
                                                .select('wallet')
                                                .eq('game_id', widget.gameId)
                                                .eq('player_id', payerPlayerID)
                                                .maybeSingle();

                                            final receiverResponse =
                                                await Supabase
                                                    .instance.client
                                                    .from('players_test')
                                                    .select(
                                                        'wallet, player_id, name')
                                                    .eq('game_id',
                                                        widget.gameId)
                                                    .eq('role', "banker")
                                                    .maybeSingle();

                                            if (payerResponse != null &&
                                                receiverResponse != null &&
                                                payerResponse['wallet'] !=
                                                    null &&
                                                receiverResponse['wallet'] !=
                                                    null) {
                                              double payerWallet =
                                                  (payerResponse['wallet']
                                                          as num)
                                                      .toDouble();

                                              if (payerWallet >=
                                                  enteredAmount!) {
                                                // One atomic call: the database
                                                // locks both rows, re-checks the
                                                // funds and writes both wallets,
                                                // so a payment landing at the same
                                                // moment can no longer lose this
                                                // one.
                                                final TransferOutcome transfer =
                                                    await WalletTransfer.pay(
                                                  gameId: widget.gameId,
                                                  fromId: payerPlayerID,
                                                  fromRole:
                                                      WalletTransfer.playerRole,
                                                  toId: receiverResponse[
                                                          'player_id']
                                                      .toString(),
                                                  toRole:
                                                      WalletTransfer.bankerRole,
                                                  amount: enteredAmount!,
                                                );

                                                if (!transfer.ok) {
                                                  setState(() {
                                                    statusLabel =
                                                        "Insufficient balance X";
                                                    isProcessing =
                                                        false; // Allow retry
                                                  });
                                                  return;
                                                }

                                                // Log the transaction
                                                await Supabase.instance.client
                                                    .from('transactions')
                                                    .insert({
                                                  'game_id': widget.gameId,
                                                  'value': enteredAmount!,
                                                  'from': currentPlayerName,
                                                  'to':
                                                      receiverResponse['name'],
                                                  'code':
                                                      "${payerPlayerID}_${receiverResponse['player_id']}",
                                                  'date': DateFormat(
                                                          'yyyy-MM-dd')
                                                      .format(DateTime.now()),
                                                  'time': DateFormat('HH:mm:ss')
                                                      .format(DateTime.now()),
                                                });

                                                // Show success message
                                                setState(() {
                                                  statusLabel =
                                                      "Payment Successful ✓";
                                                });

                                                // Close the dialog after a delay
                                                await Future.delayed(
                                                    const Duration(seconds: 2));
                                                // ignore: use_build_context_synchronously
                                                Navigator.of(context).pop();
                                              } else {
                                                // Insufficient funds
                                                setState(() {
                                                  statusLabel =
                                                      "Insufficient balance X";
                                                  isProcessing =
                                                      false; // Allow retry
                                                });
                                              }
                                            } else {
                                              // Failed to fetch wallet data
                                              setState(() {
                                                statusLabel =
                                                    "Failed to fetch wallet data ⊘";
                                              });

                                              /*  await Future.delayed(
                                                const Duration(seconds: 2));
                                            Navigator.of(context).pop(); */
                                            }
                                          } else {
                                            // Invalid amount entered
                                            setState(() {
                                              statusLabel = "Invalid amount !!";
                                            });
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white),
                                  child: const Icon(Icons.keyboard_arrow_right),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (enteredAmount == null) return; // user cancelled or invalid input
  }

  // Button style helper
  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // Intercept the back press and show the confirmation instead.
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool shouldLeave = await _onWillPop();
        if (shouldLeave && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF8E1),
        appBar: AppBar(
          backgroundColor: Colors.yellow.shade50,
          automaticallyImplyLeading: false,
          title: Text(
            'Bankpop Wallet',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20.sp,
              color: const Color(0xFF689F38), // deep green icon
            ),
          ),
          actions: [
            IconButton(
                onPressed: () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TransactionHistoryPage(
                        gameId: widget.gameId,
                        playerId: playerID ?? '-',
                      ),
                    ),
                  );
                },
                icon: const Icon(FontAwesomeIcons.clockRotateLeft)),
            const SizedBox(width: 5),
            IconButton(
                onPressed: () async {
                  bool shouldLeave = await _onWillPop();
                  if (shouldLeave) {
                    SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    await prefs.remove('gameID');

                    // ignore: use_build_context_synchronously
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const WelcomePage()),
                      (Route<dynamic> route) => false,
                    ); // or your custom logic to leave the game
                  }
                },
                icon: const Icon(FontAwesomeIcons.rightFromBracket)),
            const SizedBox(width: 5),
          ],
        ),
        // playerID comes from local prefs, so this gate clears within a frame or
        // two; it just keeps the card from being built before it exists.
        body: isLoading || playerID == null
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF689F38)),
              )
            : ListView.builder(
                itemCount: players.length + 1, // +1 for the top item
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Return the top item
                    return Column(
                      children: [
                        const SizedBox(height: 10),
                        Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          color: Colors.blueGrey.shade500,
                          elevation: 5,
                          child: Stack(
                            children: [
                              Positioned(
                                bottom: 0,
                                right: 10,
                                child: Image.asset(
                                  'assets/images/c_logo.png',
                                  fit: BoxFit.contain,
                                  cacheWidth: 160, // see the note on the other two
                                  width: 23
                                      .sp, // Use MediaQuery or a fixed size if sp is undefined
                                  height: 23.sp,
                                  colorBlendMode: BlendMode
                                      .srcIn, // Ensures image is tinted red
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Row for Cardholder's Name and Card Number
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Cardholder's name
                                            Row(
                                              children: [
                                                Text(
                                                  _cardName,
                                                  style: TextStyle(
                                                    fontSize: 20.sp,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              ],
                                            ),
                                            const SizedBox(height: 5),
                                            // Dummy credit card number
                                            Text(
                                              '**** **** **** ${_cardDigits.substring(0, 4)}', // First 4 digits of this device's id
                                              style: TextStyle(
                                                fontSize: 22.sp,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.blueGrey.shade100,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Lottie.asset(
                                          positionStatus == "first"
                                              ? 'assets/lottie/first.json'
                                              : positionStatus == "second"
                                                  ? 'assets/lottie/second.json'
                                                  : positionStatus ==
                                                          "almostlast"
                                                      ? 'assets/lottie/almost_last.json'
                                                      : positionStatus == "last"
                                                          ? 'assets/lottie/last.json'
                                                          : 'assets/lottie/neutral.json',
                                          height: 10.h,
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 15),

                                    // Row for Expiration Date and CVV
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        AnimatedFlipCounter(
                                          value: value,
                                          fractionDigits: 2,
                                          textStyle: TextStyle(
                                            fontSize: 28.sp,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white
                                                .withValues(alpha: 0.9),
                                          ),
                                          duration:
                                              const Duration(milliseconds: 500),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10.0),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'EXPIRY',
                                                    style: TextStyle(
                                                      fontSize: 12.sp,
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.7),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    DateFormat('MM/yy')
                                                        .format(DateTime.now()),
                                                    style: TextStyle(
                                                      fontSize: 16.sp,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors
                                                          .blueGrey.shade100,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(width: 20),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'CVV',
                                                    style: TextStyle(
                                                      fontSize: 12.sp,
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.7),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    _cardDigits.substring(
                                                        _cardDigits.length -
                                                            3), // Dummy CVV
                                                    style: TextStyle(
                                                      fontSize: 16.sp,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors
                                                          .blueGrey.shade100,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 10),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (payOption == 'ScanPay') const ReceiveButton(),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: () {
                                  payOption == 'ScanPay'
                                      ? Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => QRPayScanner(
                                                gameId: widget.gameId),
                                          ),
                                        )
                                      : payBank();
                                },
                                icon: Icon(FontAwesomeIcons.moneyBill,
                                    size: 16.sp),
                                label: Text(
                                  payOption == 'ScanPay'
                                      ? 'Pay'
                                      : 'Pay To Bank',
                                  style: TextStyle(fontSize: 16.sp),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        )
                      ],
                    );
                  } else {
                    // Return the list items (shifted by -1)
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 5),
                      child: _buildPlayerRow(players[index - 1]),
                    );
                  }
                },
              ),
      ),
    );
  }
}
