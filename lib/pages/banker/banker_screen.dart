import 'dart:async';
 
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mon/pages/home.dart';
 import 'package:mon/pages/transactions/receive.dart';
import 'package:mon/pages/transactions/transactions.dart';
 import 'package:qr_flutter/qr_flutter.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';  

class BankerGameScreen extends StatefulWidget {
  final double bankValue;
  final String gameId;

  const BankerGameScreen(
      {super.key, required this.bankValue, required this.gameId});

  @override
  State<BankerGameScreen> createState() => _BankerGameScreenState();
}

class _BankerGameScreenState extends State<BankerGameScreen> {
  List<Player> players = [];
  bool isLoading = true;
  Timer? _pollingTimer;
  bool _dialogShown = false; // Track if a dialog is already shown
  double value = 0;
  String payOption = 'InstantPay';
  String ID = '';
  @override
  void initState() {
    super.initState();
    value = widget.bankValue;
    fetchPlayers(); // Initial load
    startPolling(); // Start periodic fetching every 1 second
  }

  @override
  void dispose() {
    _pollingTimer?.cancel(); // Clean up timer
    super.dispose();
  }

  void startPolling() {
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      fetchPlayers(); // Fetch every 1 second
    });
  }

  Future<void> fetchPlayers() async {
    final supabase = Supabase.instance.client;
    try {
      // Fetch players
      final response = await supabase
          .from('players_test')
          .select()
          .eq('game_id', widget.gameId)
          .eq('role', 'player')
          .order('wallet', ascending: false); // Sort by wallet descending

      final data = response as List<dynamic>;
      final updatedPlayers =
          data.map((e) => Player.fromMap(e as Map<String, dynamic>)).toList();

      if (!listEquals(players, updatedPlayers)) {
        setState(() {
          players = updatedPlayers;
          isLoading = false;
        });
      }
      final response2 = await supabase
          .from('players_test')
          .select()
          .eq('game_id', widget.gameId)
          .eq('role', 'banker');

      final data2 = response2.first["wallet"];
      final option = response2.first['SP/IP'];
      setState(() {
        value = double.parse(data2.toStringAsFixed(2));
        payOption = option;
      });
      print(data2);
      // Check for new requests
      await checkForRequests();
    } catch (e) {
      debugPrint('Error fetching players: $e');
    }
  }

  bool _isProcessingRequest = false; // Add this to your state class

  Future<void> checkForRequests() async {
    if (_isProcessingRequest) return; // Prevent concurrent calls
    _isProcessingRequest = true;

    final supabase = Supabase.instance.client;

    try {
      final requests = await supabase
          .from('request_test')
          .select()
          .eq('game_id', widget.gameId);

      final prefs = await SharedPreferences.getInstance();
      final playerID = prefs.getString('playerID');

      final playerExists = await supabase
          .from('players_test')
          .select()
          .eq('role', 'player')
          .eq('player_id', playerID!)
          .eq('game_id', widget.gameId)
          .maybeSingle();

      if (requests.isNotEmpty && playerExists == null) {
        await _processRequestsSequentially(requests);
      }
    } catch (e) {
      debugPrint('Error checking requests: $e');
    } finally {
      _isProcessingRequest = false;
    }
  }

  Future<void> _processRequestsSequentially(List<dynamic> requests) async {
    final supabase = Supabase.instance.client;

    for (final request in requests) {
      bool accepted = false;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.yellow.shade50,
            title: const Text("New Player Request"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text("Name: ${request['name']}"),
                /*   Text("Wallet: ${request['wallet']}"), */
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await supabase
                      .from('request_test')
                      .delete()
                      .eq('id', request['id']);
                  Navigator.of(context).pop();
                },
                child: const Text("Deny"),
              ),
              TextButton(
                onPressed: () async {
                  SharedPreferences prefs =
                      await SharedPreferences.getInstance();

                  double playerValue = prefs.getDouble('playerValue')!;

                  // Accept logic
                  await supabase.from('players_test').insert({
                    'name': request['name'],
                    'wallet': playerValue,
                    'game_id': widget.gameId,
                    'role': 'player',
                    'player_id': request['player_id'],
                    'SP/IP': payOption
                  });

                  await supabase
                      .from('request_test')
                      .delete()
                      .eq('id', request['id']);

                  // Update banker's wallet
                  final banker = await supabase
                      .from('players_test')
                      .select()
                      .eq('game_id', widget.gameId)
                      .eq('role', 'banker')
                      .maybeSingle();

                  if (banker != null) {
                    final updatedWallet = banker['wallet'] - playerValue;

                    await supabase.from('players_test').update({
                      'wallet': updatedWallet,
                    }).eq('id', banker['id']);

                    setState(() {
                      value = updatedWallet.toDouble();
                      ID = banker['player_id'];
                    });
                  }

                  accepted = true;
                  Navigator.of(context).pop();
                },
                child: const Text("Accept"),
              ),
            ],
          );
        },
      );

      if (accepted) {
        fetchPlayers();
        break; // stop showing dialogs after accepting one
      }
    }
  }

  void _showQRDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.yellow.shade50,
        titlePadding:
            const EdgeInsets.only(top: 10.0, left: 16.0, right: 8.0, bottom: 0),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Join Game',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: 60.w,
          height: 30.h,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: widget.gameId,
                version: QrVersions.auto,
                size: 50.sp,
                gapless: false,
              ),
              Text(
                'Game ID: ${widget.gameId}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.sp),
                textAlign: TextAlign.center,
              ),
              Text(
                'Scan or enter the Game ID to join',
                style: TextStyle(fontWeight: FontWeight.w400, fontSize: 16.sp),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerRow(BuildContext context, Player player) {
    return Container(
      height: 6.h,
      padding: EdgeInsets.symmetric(vertical: 0.h, horizontal: 2.w),
      margin: EdgeInsets.symmetric(vertical: 0.5.h),
      decoration: BoxDecoration(
        color: player.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(2.w),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              player.name,
              style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.bold,
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
                fontSize: 16.sp,
                color: player.color,
              ),
              duration: const Duration(milliseconds: 500), // optional
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Wrap(
              alignment: WrapAlignment.end,
              direction: Axis.horizontal, // Ensures horizontal layout
              spacing: 0, // Horizontal space between children
              runSpacing: 0.h, // Vertical space between lines
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final TextEditingController _amountController =
                        TextEditingController();

                    double? enteredAmount = await showDialog<double>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Enter Reward Amount'),
                          content: TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(hintText: 'e.g. 200'),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop(); // cancel
                              },
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                final value =
                                    double.tryParse(_amountController.text);
                                if (value != null && value > 0) {
                                  Navigator.of(context).pop(value);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Enter a valid reward amount')),
                                  );
                                }
                              },
                              child: const Text('Reward'),
                            ),
                          ],
                        );
                      },
                    );

                    if (enteredAmount == null)
                      return; // user cancelled or invalid input

                    final prefs = await SharedPreferences.getInstance();
                    final payerPlayerID =
                        prefs.getString('playerID') ?? 'UnknownPlayer';
                    double rewardAmount = enteredAmount;

                    final payerResponse = await Supabase.instance.client
                        .from('players_test')
                        .select('wallet')
                        .eq('game_id', widget.gameId)
                        .eq('player_id', payerPlayerID)
                        .maybeSingle();

                    final receiverResponse = await Supabase.instance.client
                        .from('players_test')
                        .select('wallet')
                        .eq('game_id', widget.gameId)
                        .eq('player_id', player.playerID)
                        .maybeSingle();

                    if (payerResponse != null &&
                        receiverResponse != null &&
                        payerResponse['wallet'] != null &&
                        receiverResponse['wallet'] != null) {
                      double payerWallet =
                          (payerResponse['wallet'] as num).toDouble();
                      double receiverWallet =
                          (receiverResponse['wallet'] as num).toDouble();

                      if (payerWallet >= rewardAmount) {
                        double newPayerWallet = payerWallet - rewardAmount;
                        double newReceiverWallet =
                            receiverWallet + rewardAmount;

                        await Supabase.instance.client
                            .from('players_test')
                            .update({'wallet': newPayerWallet})
                            .eq('game_id', widget.gameId)
                            .eq('player_id', payerPlayerID);

                        await Supabase.instance.client
                            .from('players_test')
                            .update({'wallet': newReceiverWallet})
                            .eq('game_id', widget.gameId)
                            .eq('player_id', player.playerID);
                        await Supabase.instance.client
                            .from('transactions')
                            .insert({
                          'game_id': widget.gameId,
                          'value': rewardAmount,
                          'from': "Bank",
                          'to': player.name,
                          'code': "${payerPlayerID}_${player.playerID}",
                          'date':
                              DateFormat('yyyy-MM-dd').format(DateTime.now()),
                          'time': DateFormat('HH:mm:ss').format(DateTime.now()),
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Rewarded ₹$rewardAmount to ${player.name}')),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Insufficient balance to reward ₹$rewardAmount')),
                          );
                        }
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Failed to fetch wallet data')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(5), // Remove internal padding
                    fixedSize: Size(25.sp, 20.sp), // 👈 Set button size here

                    elevation: 0,
                    foregroundColor: player.color,
                    backgroundColor: Colors.white.withOpacity(1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Image.asset(
                    'assets/images/pay.png', fit: BoxFit.contain,

                    width: 23
                        .sp, // Use MediaQuery or a fixed size if sp is undefined
                    height: 23.sp,
                    color: player.color, // Apply red color
                    colorBlendMode:
                        BlendMode.srcIn, // Ensures image is tinted red
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final payerPlayerID =
                        prefs.getString('playerID') ?? 'UnknownPlayer';
                    double advanceValue = prefs.getDouble('advance')!;
                    double advanceAmount = advanceValue;

                    // Step 1: Fetch payer's wallet
                    final payerResponse = await Supabase.instance.client
                        .from('players_test')
                        .select('wallet')
                        .eq('game_id', widget.gameId)
                        .eq('player_id', payerPlayerID)
                        .maybeSingle();

                    // Step 2: Fetch receiver's wallet
                    final receiverResponse = await Supabase.instance.client
                        .from('players_test')
                        .select('wallet')
                        .eq('game_id', widget.gameId)
                        .eq('player_id', player.playerID)
                        .maybeSingle();

                    if (payerResponse != null &&
                        receiverResponse != null &&
                        payerResponse['wallet'] != null &&
                        receiverResponse['wallet'] != null) {
                      double payerWallet =
                          (payerResponse['wallet'] as num).toDouble();
                      double receiverWallet =
                          (receiverResponse['wallet'] as num).toDouble();

                      if (payerWallet >= advanceAmount) {
                        double newPayerWallet = payerWallet - advanceAmount;
                        double newReceiverWallet =
                            receiverWallet + advanceAmount;

                        // Update payer
                        await Supabase.instance.client
                            .from('players_test')
                            .update({'wallet': newPayerWallet})
                            .eq('game_id', widget.gameId)
                            .eq('player_id', payerPlayerID);

                        // Update receiver
                        await Supabase.instance.client
                            .from('players_test')
                            .update({'wallet': newReceiverWallet})
                            .eq('game_id', widget.gameId)
                            .eq('player_id', player.playerID);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Advanced ₹$advanceAmount to ${player.name}')),
                          );
                          await Supabase.instance.client
                              .from('transactions')
                              .insert({
                            'game_id': widget.gameId,
                            'value': advanceAmount,
                            'from': "Bank (Advance)",
                            'to': player.name,
                            'code': "${payerPlayerID}_${player.playerID}",
                            'date':
                                DateFormat('yyyy-MM-dd').format(DateTime.now()),
                            'time':
                                DateFormat('HH:mm:ss').format(DateTime.now()),
                          });
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Insufficient balance to advance ₹200')),
                          );
                        }
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Failed to fetch wallet data')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    padding: const EdgeInsets.all(5), // Remove internal padding
                    fixedSize: Size(25.sp,
                        20.sp), // 👈 Set button size here                    elevation: 0,
                    foregroundColor: player.color,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Image.asset(
                    'assets/images/advance.png',
                    width: 23.sp,
                    height: 23.sp,
                    fit: BoxFit.contain,
                    color: player.color,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
              ],
            ),
          ),
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
      onWillPop: _onWillPop, // Intercept the back press and show confirmation
      child: Scaffold(
        backgroundColor: Colors.yellow.shade50,
        appBar: AppBar(
          backgroundColor: Colors.yellow.shade50,
          automaticallyImplyLeading: false,
          title: const Text(
            'Leaderboard',
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
                        playerId: ID ?? '-',
                      ),
                    ),
                  );
                },
                icon: const Icon(FontAwesomeIcons.history)),
            const SizedBox(width: 10),
            IconButton(
              onPressed: () => _showQRDialog(context),
              icon: const Icon(FontAwesomeIcons.peopleGroup),
              tooltip: 'Show Bank QR Code',
            ),
            const SizedBox(width: 10),
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
                    );
                  }
                },
                icon: const Icon(FontAwesomeIcons.signOutAlt)),
            const SizedBox(width: 5),
          ],
        ),
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 2.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              FontAwesomeIcons.buildingColumns,
                              color: Colors.blueGrey.shade700,
                              size: 22.sp,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Bank Holdings',
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
                      fractionDigits: 2,
                      textStyle: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      duration: const Duration(
                          milliseconds: 500), // optional: animation speed
                    ),
                    const SizedBox(height: 10),
                    if (payOption == 'ScanPay')
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ReceiveButton(),
                          SizedBox(width: 0),
/*                           ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      QRPayScanner(gameId: widget.gameId),
                                ),
                              );
                            },
                            icon: Icon(FontAwesomeIcons.moneyBill, size: 16.sp),
                            label: Text(
                              'Pay',
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
 */
                        ],
                      ),
                  ],
                ),
              ),
              SizedBox(height: 2.h),
              isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                      color: Colors.white,
                    ))
                  : Expanded(
                      child: ListView.builder(
                        itemCount: players.length,
                        itemBuilder: (context, index) =>
                            _buildPlayerRow(context, players[index]),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class Player {
  final String name;
  final String playerID;
  final double value;
  final Color color;

  Player(
      {required this.name,
      required this.playerID,
      required this.value,
      required this.color});

  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
      name: map['name'],
      value: map['wallet'].toDouble(),
      playerID: map['player_id'],
      color: Colors.primaries[(map['name'].hashCode) %
          Colors.primaries.length], // Assign color based on name hash
    );
  }
}
