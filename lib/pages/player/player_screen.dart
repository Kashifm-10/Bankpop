import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/pages/transactions/pay.dart';
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

  File? _profileImage;

  @override
  void initState() {
    super.initState();
    value = widget.bankValue;
    fetchCurrentPlayerName();
    fetchPlayers();
    startPolling();
    setAvatar();
  }

  @override
  void dispose() {
    pollingTimer?.cancel();
    super.dispose();
  }

  void startPolling() {
    pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      fetchPlayers();
      fetchMyPlayer();
    });
  }

  Future<void> fetchCurrentPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gameID', widget.gameId);

    setState(() {
      currentPlayerName = prefs.getString('profile_name');
    });
  }

  Future<void> setAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final avatar = prefs.getString('avatar_path');
    playerID = prefs.getString('playerID');

    await Supabase.instance.client
        .from('players_test')
        .update({'avatar': avatar})
        .eq('game_id', widget.gameId)
        .eq('player_id', playerID!);
  }

  Future<void> fetchPlayers() async {
    final supabase = Supabase.instance.client;
    try {
      final response = await supabase
          .from('players_test')
          .select()
          .eq('game_id', widget.gameId)
          .eq('role', 'player')
          .order('wallet', ascending: false); // Sort by wallet descending

      final data = response as List<dynamic>;
      final updatedPlayers = data.map((e) => Player.fromMap(e)).toList();

      if (!listEquals(players, updatedPlayers)) {
        setState(() {
          players = updatedPlayers;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching players: $e');
    }
  }

  void notify(String message, String value) {
    showDialog(
      barrierDismissible: false,
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext dialogContext) {
        // Auto-close after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Center(
            child: SizedBox(
              width: 60.w, // Responsive width
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Lottie.asset(
                    message == 'paid'
                        ? 'assets/lottie/paid.json'
                        : message == 'failed'
                            ? 'assets/lottie/failed.json'
                            : message == 'received'
                                ? 'assets/lottie/received.json'
                                : 'assets/lottie/paid.json',
                    repeat: false,
                  ),
                  Text(
                    "${message[0].toUpperCase()}${message.substring(1)} $value",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
                    textAlign: TextAlign.center,
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
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

/*   Future<void> fetchMyPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name');
    if (name == null) return;

    final supabase = Supabase.instance.client;
    try {
      final response = await supabase
          .from('players_test')
          .select()
          .eq('game_id', widget.gameId)
          .eq('name', name)
          .single();

      final data = response as Map<String, dynamic>;
      final wallet = data['wallet'] as num;
      setState(() {
        value = double.parse(wallet.toStringAsFixed(2));
      });
      // Show SnackBar only if there's a change
      if (previousWallet != null) {
        if (wallet > previousWallet!) {
          showSnackBar('Received');
        } else if (wallet < previousWallet!) {
          showSnackBar('Deducted');
        }
      }

      previousWallet = wallet.toDouble();
    } catch (e) {
      debugPrint('Error fetching current player: $e');
    }
  }
 */

  Future<void> fetchMyPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('profile_name');
    playerID = prefs.getString('playerID');

    if (name == null) return;

    final supabase = Supabase.instance.client;
    try {
      // Fetch all players in the game
      final allPlayersResponse = await supabase
          .from('players_test')
          .select()
          .eq('role', 'player')
          .eq('game_id', widget.gameId);

      final allPlayers = allPlayersResponse as List<dynamic>;

      // Sort players by wallet in descending order
      allPlayers
          .sort((a, b) => (b['wallet'] as num).compareTo(a['wallet'] as num));

      // Find the current player's data and position
      final currentPlayerIndex =
          allPlayers.indexWhere((player) => player['player_id'] == playerID);
      if (currentPlayerIndex == -1) {
        debugPrint('Current player not found in the list.');
        return;
      }

      final currentPlayer = allPlayers[currentPlayerIndex];
      final wallet = currentPlayer['wallet'] as num;
      final playerId = playerID;
      final option = currentPlayer['SP/IP'];

      final position = currentPlayerIndex + 1; // 1-based position
      final totalPlayers = allPlayers.length;

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

      setState(() {
        playerID = playerId;
        value = double.parse(wallet.toStringAsFixed(2));
        playerPosition = position; // Requires defining this state variable
        positionStatus = positionLabel; // Requires defining this too
        payOption = option;
      });

      // Show SnackBar only if there's a change
      if (previousWallet != null) {
        if (wallet > previousWallet!) {
          //notify('received', (wallet - previousWallet!).toStringAsFixed(2));
          notification(
              'received', (wallet - previousWallet!).toStringAsFixed(2));
          // showSnackBar('Received');
        } else if (wallet < previousWallet! && payOption == 'ScanPay') {
          //notify('paid', (previousWallet! - wallet).toStringAsFixed(2));
          notification('paid', (previousWallet! - wallet).toStringAsFixed(2));

          // showSnackBar('Deducted');
        }
      }

      previousWallet = wallet.toDouble();
    } catch (e) {
      debugPrint('Error fetching current player or rankings: $e');
    }
  }

  void showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
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
                                              '${currentPlayerName![0].toUpperCase()}${currentPlayerName!.substring(1).toLowerCase()}',
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
                                          '**** **** **** ${playerID!.replaceAll(RegExp(r'\D'), '').substring(0, 4)}', // Extracts first 4 digits from UUID
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
                                        color: Colors.white.withOpacity(0.9),
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
                                                      .withOpacity(0.7),
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
                                                      .withOpacity(0.7),
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
                                              double receiverWallet =
                                                  (receiverResponse['wallet']
                                                          as num)
                                                      .toDouble();

                                              if (payerWallet >=
                                                  enteredAmount!) {
                                                // Update wallet balances
                                                double newPayerWallet =
                                                    payerWallet -
                                                        enteredAmount!;
                                                double newReceiverWallet =
                                                    receiverWallet +
                                                        enteredAmount!;

                                                // Update Supabase records
                                                await Supabase.instance.client
                                                    .from('players_test')
                                                    .update({
                                                      'wallet': newPayerWallet
                                                    })
                                                    .eq('game_id',
                                                        widget.gameId)
                                                    .eq('player_id',
                                                        payerPlayerID);

                                                await Supabase.instance.client
                                                    .from('players_test')
                                                    .update({
                                                      'wallet':
                                                          newReceiverWallet
                                                    })
                                                    .eq('game_id',
                                                        widget.gameId)
                                                    .eq('player_id',
                                                        player.playerID);
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
        color: player.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(2.w),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18.sp,
            backgroundColor:
                Colors.transparent, // pale mint green bg for subtle pop
            backgroundImage: AssetImage(player.avatar),
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
                                              '${currentPlayerName![0].toUpperCase()}${currentPlayerName!.substring(1)}',
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
                                          '**** **** **** ${playerID!.replaceAll(RegExp(r'\D'), '').substring(0, 4)}', // Extracts first 4 digits from UUID
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
                                        color: Colors.white.withOpacity(0.9),
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
                                                      .withOpacity(0.7),
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
                                                      .withOpacity(0.7),
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                playerID!
                                                    .replaceAll(
                                                        RegExp(r'\D'), '')
                                                    .substring(playerID!
                                                            .replaceAll(
                                                                RegExp(r'\D'),
                                                                '')
                                                            .length -
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
                                              double receiverWallet =
                                                  (receiverResponse['wallet']
                                                          as num)
                                                      .toDouble();

                                              if (payerWallet >=
                                                  enteredAmount!) {
                                                // Update wallet balances
                                                double newPayerWallet =
                                                    payerWallet -
                                                        enteredAmount!;
                                                double newReceiverWallet =
                                                    receiverWallet +
                                                        enteredAmount!;

                                                // Update Supabase records
                                                await Supabase.instance.client
                                                    .from('players_test')
                                                    .update({
                                                      'wallet': newPayerWallet
                                                    })
                                                    .eq('game_id',
                                                        widget.gameId)
                                                    .eq('player_id',
                                                        payerPlayerID);

                                                await Supabase.instance.client
                                                    .from('players_test')
                                                    .update({
                                                      'wallet':
                                                          newReceiverWallet
                                                    })
                                                    .eq('game_id',
                                                        widget.gameId)
                                                    .eq('role', "banker");

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

  void showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // Disable dismissing by tapping outside
      builder: (BuildContext context) {
        return Dialog(child: Lottie.asset('assets/lottie/first.json'));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
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
                icon: const Icon(FontAwesomeIcons.history)),
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
                icon: const Icon(FontAwesomeIcons.signOutAlt)),
            const SizedBox(width: 5),
          ],
        ),
        body: isLoading
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
                                                  '${currentPlayerName![0].toUpperCase()}${currentPlayerName!.substring(1)}',
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
                                              '**** **** **** ${playerID!.replaceAll(RegExp(r'\D'), '').substring(0, 4)}', // Extracts first 4 digits from UUID
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
                                            color:
                                                Colors.white.withOpacity(0.9),
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
                                                          .withOpacity(0.7),
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
                                                          .withOpacity(0.7),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    playerID!
                                                        .replaceAll(
                                                            RegExp(r'\D'), '')
                                                        .substring(playerID!
                                                                .replaceAll(
                                                                    RegExp(
                                                                        r'\D'),
                                                                    '')
                                                                .length -
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
