import 'dart:async';
import 'dart:convert';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/pay.dart';
import 'package:mon/receive.dart';
import 'package:mon/transactions.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Player {
  final String name;
  final double value;
  final Color color;

  Player({required this.name, required this.value, required this.color});

  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
      name: map['name'],
      value: double.tryParse(map['wallet'].toString()) ?? 0.0,
      color: Colors.primaries[map['name'].hashCode % Colors.primaries.length],
    );
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

  @override
  void initState() {
    super.initState();
    value = widget.bankValue;
    fetchCurrentPlayerName();
    fetchPlayers();
    startPolling();
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
    setState(() {
      currentPlayerName = prefs.getString('name');
    });
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
    final name = prefs.getString('name');
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
          allPlayers.indexWhere((player) => player['name'] == name);
      if (currentPlayerIndex == -1) {
        debugPrint('Current player not found in the list.');
        return;
      }

      final currentPlayer = allPlayers[currentPlayerIndex];
      final wallet = currentPlayer['wallet'] as num;
      final playerId = currentPlayer['player_id'];
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
      });

      // Show SnackBar only if there's a change
      if (previousWallet != null) {
        if (wallet > previousWallet!) {
          notify('received', (wallet - previousWallet!).toStringAsFixed(2));
          // showSnackBar('Received');
        } else if (wallet < previousWallet!) {
          notify('paid', (previousWallet! - wallet).toStringAsFixed(2));
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

  Widget _buildPlayerRow(Player player) {
    final bool isCurrentPlayer = player.name == currentPlayerName;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 1.h, horizontal: 3.w),
      margin: EdgeInsets.symmetric(vertical: 0.5.h),
      decoration: BoxDecoration(
        color: player.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(2.w),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              !isCurrentPlayer ? player.name : "${player.name} (me)",
              style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w600,
                  color: player.color),
            ),
          ),
          Expanded(
            flex: 2,
            child: AnimatedFlipCounter(
              value: player.value,
              fractionDigits: 2,
              textStyle: TextStyle(
                fontSize: 16.sp,
                color: player.color,
              ),
              duration: const Duration(milliseconds: 900), // optional
            ),
          ),
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.yellow.shade50,
        appBar: AppBar(
          backgroundColor: Colors.yellow.shade50,
          automaticallyImplyLeading: false,
          title: const Text(
            'LeaderBoard',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
                onPressed: () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TransactionHistoryPage(
                        gameId: widget.gameId,
                        playerId: playerID??'-',
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
                    Navigator.of(context)
                        .pop(); // or your custom logic to leave the game
                  }
                },
                icon: const Icon(FontAwesomeIcons.signOutAlt)),
            const SizedBox(width: 5),
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: players.length + 1, // +1 for the top item
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Return the top item
                    return /* Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const ReceiveButton(),
                              const SizedBox(
                                width: 10,
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => QRPayScanner(
                                            gameId: widget.gameId)),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('Pay'),
                              ),
                            ],
                          )); */
                        Container(
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [Colors.white, Colors.blue.shade50],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Icon(
                                            FontAwesomeIcons.dice,
                                            color: Colors.blueGrey.shade700,
                                            size: 22.sp,
                                          ),
                                          const SizedBox(width: 20),
                                          Text(
                                            '$currentPlayerName\'s Holdings',
                                            style: TextStyle(
                                              fontSize: 18.sp,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.blueGrey.shade800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  AnimatedFlipCounter(
                                    value: value,
                                    fractionDigits: 2, // same decimal precision
                                    // suffix: "%",
                                    textStyle: TextStyle(
                                      fontSize: 28.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                    duration: const Duration(
                                        milliseconds:
                                            500), // optional: adjust animation speed
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
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const ReceiveButton(),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          QRPayScanner(gameId: widget.gameId),
                                    ),
                                  );
                                },
                                icon: Icon(FontAwesomeIcons.moneyBill,
                                    size: 16.sp),
                                label: Text(
                                  'Pay',
                                  style: TextStyle(fontSize: 16.sp),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  textStyle: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w500),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 0, // Flat look
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
