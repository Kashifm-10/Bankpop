import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/country_chip.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BankValueScreen extends StatefulWidget {
  const BankValueScreen({super.key});

  @override
  State<BankValueScreen> createState() => _BankValueScreenState();
}

class _BankValueScreenState extends State<BankValueScreen> {
  bool _isLoading = false;
  String _selectedOption = '';

  /// Cards game: the bank sells board properties to the players. Saved with the
  /// game so the banker screen knows to offer the Give Card flow.
  bool _playWithCards = false;

  /// The board this game is played on. It is chosen here, with the other
  /// rules, because it is one of them: the board and every Chance and Community
  /// Chest card follow it for the whole game, on every device. A signed-in
  /// banker can also pick a board they made themselves.
  String? _boardId;
  String _boardLabel = '';

  /// The boards on offer: the built-in countries plus this banker's own.
  late Future<List<BoardListing>> _boardsFuture;

  final TextEditingController _bankValueController = TextEditingController();
  final TextEditingController _playerAmountController = TextEditingController();
  final TextEditingController _advanceAmountController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _boardsFuture = BoardCatalog.available(refresh: true);
  }

  /// Opens the editor for a board of the banker's own, then offers it here.
  Future<void> _createBoard() async {
    final String? created = await context.push<String>(AppRoutes.newBoard);
    if (!mounted) return;
    setState(() => _boardsFuture = BoardCatalog.available(refresh: true));
    if (created != null && created.isNotEmpty) {
      final BoardListing? listing = await BoardCatalog.listing(created);
      if (!mounted) return;
      setState(() {
        _boardId = created;
        _boardLabel = listing?.name ?? 'Your board';
      });
    }
  }

  String generateGameId(int length) {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    Random random = Random();
    String result = '';

    for (int i = 0; i < length; i++) {
      result += characters[random.nextInt(characters.length)];
    }

    return result;
  }

  Future<void> _startGame() async {
    final String bankValueText = _bankValueController.text.trim();
    final String playerAmountText = _playerAmountController.text.trim();
    final String advanceAmountText = _advanceAmountController.text.trim();

    if (bankValueText.isEmpty ||
        playerAmountText.isEmpty ||
        advanceAmountText.isEmpty) {
      showMessage(context,
          'Fill in the bank total, the cash per player and the round advance');
      return;
    }

    // Parsed before the summary, so the dialog can show what will actually be
    // written rather than what was typed.
    final double? bankValue = double.tryParse(bankValueText);
    final double? playerValue = double.tryParse(playerAmountText);
    final double? advanceValue = double.tryParse(advanceAmountText);
    if (bankValue == null || playerValue == null || advanceValue == null) {
      showMessage(context, 'Those three amounts have to be numbers');
      return;
    }
    if (_selectedOption != 'ScanPay' && _selectedOption != 'InstantPay') {
      showMessage(context, 'Please select payment type');
      return;
    }
    final String? boardId = _boardId;
    if (boardId == null) {
      showMessage(context, 'Please choose the board');
      return;
    }

    // The summary comes before anything is written. The stake and the advance
    // become the rules of the game, and a player reads them from the session,
    // so this is the last moment a typo is free to fix.
    final bool confirmed = await showAppConfirm(
      context,
      title: 'Start this game?',
      icon: Icons.flag_outlined,
      confirmLabel: 'Start game',
      cancelLabel: 'Go back',
      message: 'These become the rules of the game: players read the stake and '
          'the advance from them, so check them now. They cannot be edited '
          'after the game starts.',
      extra: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppDialogPoint(
            label: 'Bank total',
            value: bankValue.toStringAsFixed(2),
            icon: Icons.account_balance_outlined,
          ),
          AppDialogPoint(
            label: 'Cash per player',
            value: playerValue.toStringAsFixed(2),
            icon: Icons.person_outline,
          ),
          AppDialogPoint(
            label: 'Round advance',
            value: advanceValue.toStringAsFixed(2),
            icon: Icons.trending_up,
          ),
          AppDialogPoint(
            label: 'Payment',
            value: _selectedOption,
            icon: _selectedOption == 'ScanPay'
                ? Icons.qr_code_scanner
                : Icons.touch_app_outlined,
          ),
          AppDialogPoint(
            label: 'Play with cards',
            value: _playWithCards ? 'Yes' : 'No',
            icon: Icons.style_outlined,
          ),
          AppDialogPoint(
            label: 'Board',
            value: _boardLabel.isEmpty ? 'Board' : _boardLabel,
            icon: Icons.grid_on,
          ),
        ],
      ),
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    final String gameId = generateGameId(5);
    const String role = 'banker';
    const String playerName = 'Bank';
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playerValue', playerValue);
    await prefs.setDouble('advance', advanceValue);
    final String? playerID = prefs.getString('playerID');

    // The bank row is only about the banker now: who they are and what they
    // hold. Everything that describes the game - payment mode, cards, stake,
    // advance - goes to `game_sessions`, so a player device can read the rules
    // without reading the banker's wallet.
    final Map<String, dynamic> bankRow = <String, dynamic>{
      'game_id': gameId,
      'role': role,
      'name': playerName,
      'wallet': bankValue,
      'player_id': playerID,
    };

    try {
      await Supabase.instance.client.from('players_test').insert(bankRow);
    } catch (error) {
      debugPrint('Could not create the game: $error');
      if (!mounted) return;
      // The button goes back to "Start Game" instead of spinning forever.
      setState(() => _isLoading = false);
      await showMessage(context,
          'The game could not be created. Check the connection and try again.');
      return;
    }

    await GameSession.create(
      gameId: gameId,
      bankerId: playerID ?? '',
      bankerName: playerName,
      paymentOption: _selectedOption,
      playWithCards: _playWithCards,
      playerValue: playerValue,
      advanceValue: advanceValue,
      boardId: boardId,
    );

    await prefs.setString('name', 'banker');
    await prefs.setString('role', 'banker');
    await prefs.setString('display_name', 'Bank');
    await prefs.setString('gameID', gameId);
    // Local copies, used only while the session row cannot be read (a project
    // that has not run game_sessions.sql yet, or a socket-less first frame).
    await prefs.setBool('playWithCards', _playWithCards);
    await prefs.setString('payOption', _selectedOption);
    // This device's copy of the board, so the banker screen draws the right
    // board even before the session row comes back from the server.
    await prefs.setString('board_id', boardId);
    BoardCatalog.use(boardId);
    // The board is settled for the whole game, so this device keeps its own
    // copy of it now: every board and card lookup in the game then reads from
    // the phone instead of the database.
    await BoardCatalog.cacheForGame(gameId, boardId);

    if (!mounted) return;
    // The setup screen is not somewhere the back button should return to once
    // the table exists.
    context.pushReplacement(AppRoutes.banker(gameId, bankValue: bankValue));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: IconButton(
            onPressed: () async {
              Navigator.of(context).pop();
            },
            icon: Icon(
              CupertinoIcons.chevron_back,
              size: 22.sp,
              color: Color(0xFF689F38), // deep green icon
            ),
          ),
          backgroundColor: Colors.transparent, // fresh green
          elevation: 0,
          title: const Text(
            'Enter Bank Value',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF689F38), // deep green text
            ),
          ),
        ),
        body: Container(
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
          // The form grew by the cards switch; a short screen (or a large text
          // scale) would otherwise overflow with no way to reach Start Game.
          // Centring is kept while the content still fits.
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.all(4.w),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 15.0),
                        child: SizedBox(
                          height: 50.sp,
                          child: Lottie.asset(
                            "assets/lottie/money_bag.json",
                            fit: BoxFit.contain,
                            repeat: true,
                          ),
                        ),
                      ),
                      _buildGreenTextField(
                        controller: _bankValueController,
                        label: 'Bank Total Value',
                      ),
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(5.0),
                          child: Text(
                            'Fill the total value of Bank.',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF33691E), // medium green
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 1.5.h),
                      _buildGreenTextField(
                        controller: _playerAmountController,
                        label: 'Per Player',
                      ),
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(5.0),
                          child: Text(
                            'Fill the value to be distributed to each player',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF33691E), // medium green
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 1.5.h),
                      _buildGreenTextField(
                        controller: _advanceAmountController,
                        label: 'Advance Value',
                      ),
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(5.0),
                          child: Text(
                            'Fill the value which will be granted to player at completion of each round',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF33691E), // medium green
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            // ScanPay Card
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedOption = 'ScanPay';
                                });
                              },
                              child: Card(
                                color: _selectedOption == 'ScanPay'
                                    ? const Color(
                                        0xFFC5E1A5) // light green for selected
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  side: BorderSide(
                                    color: _selectedOption == 'ScanPay'
                                        ? Color(0xFF689F38).withValues(
                                            alpha: 0.4) // medium green
                                        : Colors.grey.shade300,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 16),
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        height: 30.sp,
                                        child: Lottie.asset(
                                          "assets/lottie/scan.json",
                                          fit: BoxFit.contain,
                                          repeat: true,
                                        ),
                                      ),
                                      Text(
                                        'ScanPay',
                                        style: TextStyle(
                                          color: _selectedOption == 'ScanPay'
                                              ? const Color(
                                                  0xFF2E7D32) // calm green
                                              : Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 20),

                            // InstantPay Card
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedOption = 'InstantPay';
                                });
                              },
                              child: Card(
                                color: _selectedOption == 'InstantPay'
                                    ? const Color(0xFFC5E1A5)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  side: BorderSide(
                                    color: _selectedOption == 'InstantPay'
                                        ? Color(0xFF689F38)
                                            .withValues(alpha: 0.4)
                                        : Colors.grey.shade300,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 16),
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        height: 30.sp,
                                        child: Lottie.asset(
                                          "assets/lottie/instant.json",
                                          fit: BoxFit.contain,
                                          repeat: true,
                                        ),
                                      ),
                                      Text(
                                        'InstantPay',
                                        style: TextStyle(
                                          color: _selectedOption == 'InstantPay'
                                              ? const Color(0xFF2E7D32)
                                              : Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.all(5.0),
                          child: Text(
                            'Choose the payment type to continue',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF33691E), // medium green
                            ),
                          ),
                        ),
                      ),
                      // The board is a rule of the game like the payment type:
                      // every device at the table draws the board chosen here,
                      // and its Chance and Community Chest cards follow it.
                      Align(
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.all(5.0),
                          child: Text(
                            'Choose the board',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF33691E),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 44,
                        child: FutureBuilder<List<BoardListing>>(
                          future: _boardsFuture,
                          builder: (context, snap) {
                            final List<BoardListing> boards =
                                snap.data ?? const <BoardListing>[];
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            }
                            return ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              itemCount: boards.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (BuildContext context, int index) {
                                if (index == boards.length) {
                                  return Center(
                                    child: CountryChip(
                                      label: 'Create your own',
                                      icon: Icons.add_circle_outline,
                                      selected: false,
                                      onTap: _createBoard,
                                    ),
                                  );
                                }
                                final BoardListing board = boards[index];
                                return Center(
                                  child: CountryChip(
                                    label: board.name,
                                    flag: board.flag,
                                    icon: board.isMine
                                        ? Icons.person_outline
                                        : null,
                                    selected: _boardId == board.boardId,
                                    onTap: () => setState(() {
                                      _boardId = board.boardId;
                                      _boardLabel = board.name;
                                    }),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 2.h),
                      // Cards game: the bank sells board properties to the players.
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          'Play with Cards',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF33691E),
                          ),
                        ),
                        subtitle: Text(
                          'Enable so players can buy properties from the bank',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.black54,
                          ),
                        ),
                        value: _playWithCards,
                        activeThumbColor: const Color(0xFF689F38),
                        onChanged: (bool value) {
                          setState(() {
                            _playWithCards = value;
                          });
                        },
                      ),
                      SizedBox(height: 2.h),
                      SizedBox(
                        width: 50.w,
                        height: 6.h,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_selectedOption == 'InstantPay' ||
                                _selectedOption == 'ScanPay') {
                              _startGame();
                            } else {
                              showMessage(
                                  context, 'Please select payment type');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF689F38), // button green
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                            shadowColor:
                                const Color(0xFFB2D8A1), // soft green shadow
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF689F38),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text('Start Game',
                                  style: TextStyle(fontSize: 18.sp)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildGreenTextField({
  required TextEditingController controller,
  required String label,
}) {
  return TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF2E7D32)), // calm green
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF689F38), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF81C784), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      filled: true,
      fillColor: const Color.fromARGB(255, 255, 255, 255), // light green fill
    ),
    keyboardType: TextInputType.number,
  );
}
