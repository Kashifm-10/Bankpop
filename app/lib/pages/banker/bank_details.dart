import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/card_deck.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:mon/widgets/country_chip.dart';
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

  /// The board this game is played on: one of the built-in countries. The board
  /// and its Chance and Community Chest cards follow it for the whole game, on
  /// every device, so it is chosen here with the rest of the rules.
  String? _boardId;
  String _boardLabel = '';

  /// The country boards on offer. Creating a board lives in Boards & cards, not
  /// in the middle of a game set-up.
  ///
  /// Held here rather than read by a `FutureBuilder`: that starts in `waiting`
  /// even for a future which has already completed, so flipping the cards
  /// switch flashed a spinner over a row that was about to be there. It starts
  /// from whatever the catalog already knows (warmed at startup from the copy
  /// on the device), so the flags are on screen before the switch is touched.
  List<BoardListing>? _boards = BoardCatalog.cachedListings;

  /// Read once when the screen opens, so the flags are already there by the
  /// time the cards switch is flipped.
  Future<void> _loadBoards() async {
    final List<BoardListing> cached = await BoardCatalog.available();
    if (!mounted) return;
    setState(() => _boards = cached);
    // Then the table itself, so a board created in another tab - or on another
    // device - is in the row too. The cached list stays on screen meanwhile.
    final List<BoardListing> fresh = await BoardCatalog.available(refresh: true);
    if (!mounted || identical(fresh, cached)) return;
    setState(() => _boards = fresh);
  }

  final TextEditingController _bankValueController = TextEditingController();
  final TextEditingController _playerAmountController = TextEditingController();
  final TextEditingController _advanceAmountController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBoards();
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
    if (_playWithCards && _boardId == null) {
      showMessage(context, 'Please choose the board');
      return;
    }
    // Only a cards game draws the board; a game without cards keeps the default
    // so the session still has one to name.
    final String boardId = _boardId ?? BoardCatalog.fallbackId;

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
          if (_playWithCards && _boardLabel.isNotEmpty)
            AppDialogPoint(
              label: 'Board',
              value: _boardLabel,
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

    // Everything after the bank row can fail on a slow connection - the session
    // row, the board, the card packs. The button must stop spinning either way,
    // so the whole of it is one guarded step.
    try {
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
      // Both packs are shuffled once, now, and kept with the game: every draw
      // the banker makes from here on follows that order on every device.
      try {
        final BankpopBoard board = await BoardCatalog.boardForGame(gameId);
        await CardDeck.startGame(
          gameId: gameId,
          chance: board.chanceOptions,
          chest: board.communityChest,
        );
      } catch (error) {
        // The game still plays; the banker's draw shuffles a pack of its own.
        debugPrint('Could not shuffle the card packs: $error');
      }

      if (!mounted) return;
      // The setup screen is not somewhere the back button should return to once
      // the table exists.
      context.pushReplacement(AppRoutes.banker(gameId, bankValue: bankValue));
    } catch (error) {
      debugPrint('Could not start the game: $error');
      if (!mounted) return;
      setState(() => _isLoading = false);
      await showMessage(context,
          'The game was created but could not be opened here. Pull It up '
          'again from Your Games.');
    }
  }

  /// The row of flags the board is picked with.
  ///
  /// Drawn straight from [_boards], so flipping the cards switch shows the
  /// flags that were already read instead of a spinner over them.
  Widget _buildBoardPicker() {
    final List<BoardListing>? boards = _boards;
    if (boards == null) {
      return const Center(
        child: Text(
          'Reading the boards...',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }
    if (boards.isEmpty) {
      return const Center(
        child: Text(
          'No country boards available',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: PointerDeviceKind.values.toSet(),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: boards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (BuildContext context, int index) {
          final BoardListing board = boards[index];
          final bool isSelected = _boardId == board.boardId;
          return Center(
            child: CountryChip(
              label: board.name,
              flag: board.flag,
              icon: board.isMine && board.flag.isEmpty
                  ? Icons.person_outline
                  : null,
              labelVisible: isSelected,
              selected: isSelected,
              onTap: () => setState(() {
                _boardId = board.boardId;
                _boardLabel = board.name;
              }),
            ),
          );
        },
      ),
    );
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
          // Centring is kept while the content still fits, and on a desktop
          // window the form keeps a comfortable width instead of stretching
          // its fields across the screen.
          child: AppContent(
            maxWidth: 720,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  SingleChildScrollView(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
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
                      // The board only matters in a cards game: that is the one
                      // where players buy properties, and where the board and
                      // its Chance and Community Chest cards are drawn. The
                      // picker is a row of flags; the chosen one shows its name.
                      //
                      // It stays built while the switch is off, so the flags are
                      // already laid out when it is flipped: turning cards on
                      // reveals the row instead of starting to read one.
                      Offstage(
                        offstage: !_playWithCards,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 6),
                              child: Text(
                                'Choose the board',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF33691E),
                                ),
                              ),
                            ),
                            SizedBox(height: 46, child: _buildBoardPicker()),
                          ],
                        ),
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

/// The three amounts on the setup screen are money: digits and at most one
/// decimal point, two places after it. The keyboard alone only asks the
/// platform for a number pad - a keyboard with a full key row, a paste or a
/// desktop browser can still type letters into it, and a "1,500" that parses as
/// null would reach the start button only to fail there.
final List<TextInputFormatter> _amountFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  TextInputFormatter.withFunction(
    (TextEditingValue oldValue, TextEditingValue newValue) {
      if (newValue.text.isEmpty) return newValue;
      return RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)
          ? newValue
          : oldValue;
    },
  ),
];

Widget _buildGreenTextField({
  required TextEditingController controller,
  required String label,
}) {
  return TextField(
    controller: controller,
    inputFormatters: _amountFormatters,
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
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
  );
}
