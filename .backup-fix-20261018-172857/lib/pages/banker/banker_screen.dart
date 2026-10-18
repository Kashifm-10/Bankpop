import 'dart:async';

import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/pages/home.dart';
import 'package:mon/pages/transactions/receive.dart';
import 'package:mon/services/card_requests.dart';
import 'package:mon/services/deals.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:mon/pages/transactions/transactions.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/bankpop_board_popup.dart';
import 'package:mon/widgets/give_card_flow.dart';
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
  double value = 0;
  String payOption = 'InstantPay';
  String ID = '';
  bool _isFetching = false; // One fetch in flight at a time
  bool _isProcessingCardRequest = false; // A building dialog is on screen
  bool? _isAlsoPlayer; // Cached: does this device also hold a player row?

  /// Cards game, chosen on the "Enter Bank Value" screen before the game
  /// started. When on, the bank can sell board properties: by QR in a ScanPay
  /// game, by assignment to a named player in an InstantPay one.
  bool _playWithCards = false;

  /// What this device's own switch said at game start. The switch is the
  /// banker's alone, so this copy wins whenever the bank row disagrees - a game
  /// started before supabase/cards_mode.sql was run carries a false there.
  bool _cardsModeFromPrefs = false;
  StreamSubscription<List<Map<String, dynamic>>>? _rosterUpdates;
  StreamSubscription<List<Map<String, dynamic>>>? _requestUpdates;

  @override
  void initState() {
    super.initState();
    value = widget.bankValue;
    fetchPlayers(); // Initial load
    _subscribeToRoster(); // Live roster and bank header
    _subscribeToRequests(); // Live join requests
    startPolling(); // Reconciliation, in case Realtime is unavailable
    _loadStartupSettings();
  }

  @override
  void dispose() {
    _rosterUpdates?.cancel();
    _requestUpdates?.cancel();
    _pollingTimer?.cancel(); // Clean up timer
    super.dispose();
  }

  /// Live feed of this game's rows. Realtime pushes a change the moment it
  /// happens; the reconciliation timer below covers a device where the socket
  /// cannot connect, so the screen is never left stale either way.
  void _subscribeToRoster() {
    try {
      _rosterUpdates = Supabase.instance.client
          .from('players_test')
          .stream(primaryKey: const ['id'])
          .eq('game_id', widget.gameId)
          .listen(
        _applyGameRows,
        onError: (Object error) =>
            debugPrint('Roster stream error, still polling: $error'),
      );
    } catch (e) {
      debugPrint('Could not subscribe to roster updates: $e');
    }
  }

  void _subscribeToRequests() {
    try {
      _requestUpdates = Supabase.instance.client
          .from('request_test')
          .stream(primaryKey: const ['id'])
          .eq('game_id', widget.gameId)
          .listen(
        _onRequestRows,
        onError: (Object error) =>
            debugPrint('Request stream error, still polling: $error'),
      );
    } catch (e) {
      debugPrint('Could not subscribe to join requests: $e');
    }
  }

  void startPolling() {
    // Reconciliation only. Live changes arrive over the socket, so this just
    // repairs anything a missed event could have left behind.
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      fetchPlayers();
    });
  }

  Future<void> fetchPlayers() async {
    if (_isFetching) return; // Skip this tick instead of stacking requests
    _isFetching = true;
    final supabase = Supabase.instance.client;
    try {
      // One query for the whole game instead of two: the same rows carry the
      // roster and the bank header. Sorting a handful of rows here also spares
      // the database a sort on every tick.
      final response = await supabase
          .from('players_test')
          .select()
          .eq('game_id', widget.gameId);

      _applyGameRows((response as List<dynamic>).cast<Map<String, dynamic>>());

      // Check for new requests. Buildings are handled alongside them, but not
      // awaited: its approval dialog can sit open for a while, and the roster
      // has to keep updating while it does.
      await checkForRequests();
      unawaited(_checkCardRequests());
      unawaited(_checkDeals());
    } catch (e) {
      debugPrint('Error fetching players: $e');
    } finally {
      _isFetching = false;
    }
  }

  /// The single place game rows become screen state, so a live update and a
  /// polled one can never produce a different screen.
  void _applyGameRows(List<Map<String, dynamic>> rows) {
    if (!mounted) return;

    final List<Map<String, dynamic>> roster = rows
        .where((Map<String, dynamic> row) => row['role'] == 'player')
        .toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          ((b['wallet'] as num?) ?? 0).compareTo((a['wallet'] as num?) ?? 0));

    final List<Player> updatedPlayers =
        roster.map((Map<String, dynamic> row) => Player.fromMap(row)).toList();

    // `isLoading` has to clear even when nothing changed, otherwise a game whose
    // roster is empty would spin on the loading indicator forever.
    if (isLoading || !listEquals(players, updatedPlayers)) {
      setState(() {
        players = updatedPlayers;
        isLoading = false;
      });
    }

    Map<String, dynamic>? bankRow;
    for (final Map<String, dynamic> row in rows) {
      if (row['role'] == 'banker') {
        bankRow = row;
        break;
      }
    }
    if (bankRow == null) return;
    // A trade that touches a mortgaged card owes the bank 10% interest, and
    // only this id can route that payment.
    final String bankPlayerId = bankRow['player_id']?.toString() ?? '';
    if (bankPlayerId.isNotEmpty) Deals.rememberBankId(bankPlayerId);

    final double bankWallet =
        double.parse((bankRow['wallet'] as num).toStringAsFixed(2));
    final String bankPayOption = (bankRow['SP/IP'] as String?) ?? payOption;
    // The switch is this device's, so it is never switched off behind the
    // banker's back: the bank row can only add to it, which is what lets a
    // player's screen follow the same game.
    final bool bankCardsMode = _cardsModeFromPrefs ||
        (bankRow.containsKey('play_with_cards') &&
            bankRow['play_with_cards'] == true);
    // Only rebuild when the bank state actually moved.
    if (bankWallet != value ||
        bankPayOption != payOption ||
        bankCardsMode != _playWithCards) {
      setState(() {
        value = bankWallet;
        payOption = bankPayOption;
        _playWithCards = bankCardsMode;
      });
    }
  }

  bool _isProcessingRequest = false; // Add this to your state class

  /// True while a mortgage / unmortgage / sale request is being approved or
  /// declined, so the reconciler cannot open the same dialog twice.
  bool _isProcessingDeal = false;

  Future<void> checkForRequests() async {
    if (_isProcessingRequest) return; // Prevent concurrent calls
    _isProcessingRequest = true;

    try {
      final requests = await Supabase.instance.client
          .from('request_test')
          .select()
          .eq('game_id', widget.gameId);

      await _processPending(requests.cast<Map<String, dynamic>>());
    } catch (e) {
      debugPrint('Error checking requests: $e');
    } finally {
      _isProcessingRequest = false;
    }
  }

  /// Realtime entry point: the request stream hands over the pending rows, so a
  /// join request prompts straight away instead of on the next tick.
  Future<void> _onRequestRows(List<Map<String, dynamic>> requests) async {
    if (_isProcessingRequest) return; // A request dialog is already on screen
    _isProcessingRequest = true;
    try {
      await _processPending(requests);
    } catch (e) {
      debugPrint('Error handling requests: $e');
    } finally {
      _isProcessingRequest = false;
    }
  }

  /// Shared body, so a request is handled the same way whether it arrived over
  /// the socket or in a poll.
  Future<void> _processPending(List<Map<String, dynamic>> requests) async {
    // No pending requests is the common case: skip the identity lookup too.
    if (requests.isEmpty) return;

    _isAlsoPlayer ??= await _holdsPlayerRow(Supabase.instance.client);

    if (!_isAlsoPlayer!) {
      await _processRequestsSequentially(requests);
    }
  }

  /// Whether this device also holds a player row in this game. It cannot change
  /// while the screen is open, so it is resolved at most once per session
  /// instead of on every poll.
  Future<bool> _holdsPlayerRow(SupabaseClient supabase) async {
    final prefs = await SharedPreferences.getInstance();
    final playerID = prefs.getString('playerID');
    if (playerID == null) return true; // Keep the previous no-prompt path

    final playerExists = await supabase
        .from('players_test')
        .select()
        .eq('role', 'player')
        .eq('player_id', playerID)
        .eq('game_id', widget.gameId)
        .maybeSingle();

    return playerExists != null;
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
            backgroundColor: Color(0xFFFFF8E1),
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

                  final double? playerValue =
                      prefs.getDouble('playerValue');

                  if (playerValue == null) {
                    Navigator.of(context).pop();
                    return;
                  }

                  // One call seats the player, moves the stake off the bank
                  // (which is allowed to go negative) and clears the request.
                  final StakeOutcome stake = await WalletTransfer.stake(
                    gameId: widget.gameId,
                    playerId: '${request['player_id']}',
                    playerName: '${request['name']}',
                    amount: playerValue,
                    paymentOption: payOption,
                    requestId: '${request['id']}',
                  );

                  if (stake.ok) {
                    accepted = true;
                    setState(() {
                      value = stake.bankerWallet!;
                      ID = stake.bankerPlayerId ?? ID;
                    });
                  } else if (mounted) {
                    showMessage(
                        this.context,
                        'Could not accept ${request['name']} - try again');
                  }

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

  /// Reads what this device knows about the game it is hosting.
  ///
  /// The cards switch lives here rather than on the server, so it survives a
  /// rebuild but is written once per game start by bank_details.dart. [ID] is the
  /// bank row's player_id, which the history screen needs before the first join
  /// request has been accepted - it used to be filled in only from a stake.
  Future<void> _loadStartupSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool enabled = prefs.getBool('playWithCards') ?? false;
    final String ownId = prefs.getString('playerID') ?? '';
    if (!mounted) return;
    // Merge, never overwrite: the bank row may already have told us the game is
    // in cards mode (a banker who opens a game started on another device has
    // no local pref). Turning the switch off here would hide Give Card / Board
    // in a game that is actually playing with cards.
    final bool cardsMode = _playWithCards || enabled;
    final bool cardsPrefs = _cardsModeFromPrefs || enabled;
    final bool unchanged =
        cardsMode == _playWithCards && cardsPrefs == _cardsModeFromPrefs;
    if (unchanged && (ownId.isEmpty || ownId == ID)) return;
    setState(() {
      _cardsModeFromPrefs = cardsPrefs;
      _playWithCards = cardsMode;
      if (ownId.isNotEmpty) ID = ownId;
    });
  }

  /// Houses and hotels the players have asked for. Each request is a yes/no for
  /// the banker: approving charges the player and puts the building up together,
  /// declining charges nothing.
  Future<void> _checkCardRequests() async {
    if (_isProcessingCardRequest) return;
    _isProcessingCardRequest = true;

    try {
      final List<CardRequest> requests =
          await CardRequests.pending(widget.gameId);
      if (requests.isEmpty || !mounted) return;

      final Map<int, BankpopSpace> spaces = await PlayerCards.spaces();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String bankerId =
          ID.isNotEmpty ? ID : (prefs.getString('playerID') ?? '');
      if (!mounted) return;

      for (final CardRequest request in requests) {
        final BankpopSpace? space = spaces[request.cardIndex];
        final String cardName = space?.name ?? 'Card #${request.cardIndex}';
        final bool? approve = await showDialog<bool>(
          context: context,
          // A pending request needs an answer: dismissing would only make the
          // same dialog come back on the next poll.
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFFFFF8E1),
            title: const Text('Building request'),
            content: Text(
              '${request.playerName} wants to buy a ${request.kind} on '
              '$cardName for \u00a3${request.amount.toStringAsFixed(0)}.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Decline'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Approve'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        // Put aside: it stays pending and comes back with the next poll.
        if (approve == null) break;

        if (approve) {
          final BuildingOutcome outcome =
              await CardRequests.approve(request, bankerId: bankerId);
          if (!mounted) return;
          showMessage(
            context,
            outcome.ok
                ? '${request.playerName} now has a ${request.kind} on '
                    '$cardName'
                : 'Could not approve: ${outcome.error}',
            title: outcome.ok ? 'Built' : 'Could not approve',
          );
          // The bank was just paid, so the header should not wait for the tick.
          if (outcome.ok) fetchPlayers();
        } else {
          await CardRequests.decline(request);
          if (!mounted) return;
          showMessage(context, 'Declined ${request.playerName}\'s ${request.kind}',
              title: 'Declined');
        }
        // One per tick keeps the dialogs from stacking.
        break;
      }
    } catch (error) {
      debugPrint('Could not check building requests: $error');
    } finally {
      _isProcessingCardRequest = false;
    }
  }

  /// Mortgages, unmortgages and building sales: the player asks, the bank
  /// settles. Reads the queue on every reconciliation tick and shows one
  /// approve/decline dialog per request so a stack of pending deals is worked
  /// through one at a time.
  Future<void> _checkDeals() async {
    if (_isProcessingDeal) return;
    _isProcessingDeal = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String bankId =
          ID.isNotEmpty ? ID : (prefs.getString('playerID') ?? '');
      if (bankId.isEmpty) return;

      final List<DealRequest> deals =
          await Deals.pendingFor(widget.gameId, bankId);
      if (deals.isEmpty || !mounted) return;

      final Map<int, BankpopSpace> spaces = await PlayerCards.spaces();
      if (!mounted) return;

      for (final DealRequest deal in deals) {
        // Trades go to other players, not the bank; the banker only settles
        // mortgage / unmortgage / sell requests.
        if (deal.isTrade) continue;

        final bool? approve = await _showDealApproval(deal, spaces);
        if (!mounted) return;
        if (approve == null) break;

        if (approve) {
          final DealOutcome outcome = await Deals.approve(deal);
          if (!mounted) return;
          showMessage(
            context,
            outcome.ok
                ? '${deal.fromName}\'s ${deal.label} was settled'
                : 'Could not settle: ${outcome.error}',
            title: outcome.ok ? 'Settled' : 'Not settled',
          );
          if (outcome.ok) fetchPlayers();
        } else {
          await Deals.decline(deal.id);
          if (!mounted) return;
          showMessage(
            context,
            'Declined ${deal.fromName}\'s ${deal.label}',
            title: 'Declined',
          );
        }
        break; // one deal per tick keeps the dialogs from stacking
      }
    } catch (error) {
      debugPrint('Could not check deals: $error');
    } finally {
      _isProcessingDeal = false;
    }
  }

  Future<bool?> _showDealApproval(
    DealRequest deal,
    Map<int, BankpopSpace> spaces,
  ) {
    final String cards = deal.cards
        .map((int i) => spaces[i]?.name ?? 'Card #$i')
        .join(', ');
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: Text('${deal.fromName} wants to ${deal.label}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (cards.isNotEmpty) Text(cards),
              if (deal.kind == DealKind.mortgage)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'The bank pays half the printed price.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              if (deal.kind == DealKind.unmortgage)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'The player pays mortgage value plus 10% interest.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Decline'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  /// The board as a reference, opened from the app bar: an owned tile carries
  /// its owner's name, and its deed carries the owner in place of any action.
  void _showBoard() {
    showDialog<void>(
      context: context,
      builder: (_) => BankpopBoardPopup(gameId: widget.gameId),
    );
  }

  /// Board in cards mode, then a deed with a sell action on it.
  Future<void> _openGiveCardFlow() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // The bank row's player_id, which is what a card QR has to pay.
    final String bankerId = prefs.getString('playerID') ?? ID;
    if (!mounted) return;
    if (bankerId.isEmpty) {
      showMessage(context, 'This device has no player id');
      return;
    }
    await showGiveCardFlow(
      context: context,
      gameId: widget.gameId,
      payOption: payOption,
      bankerId: bankerId,
    );
  }

  void _showQRDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Color(0xFFFFF8E1),
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

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  void advancing() {
    showDialog(
      barrierDismissible: false,
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext dialogContext) {
        // Auto-close after 2 seconds
        /*  Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        }); */

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Center(
            child: SizedBox(
              width: 60.w, // Responsive width
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Lottie.asset(
                    'assets/lottie/advancing.json',
                    repeat: false,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerRow(BuildContext context, Player player) {
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
            backgroundImage:
                ResizeImage(AssetImage(player.avatar), width: 144),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: 3,
            child: Text(
              '${player.name[0].toUpperCase()}${player.name.substring(1)}',
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.bold,
                color: player.color,
              ),
              overflow: TextOverflow.ellipsis, // 👈 Truncate text with "..."
              maxLines: 1, // 👈 Limit to one line
              softWrap: false, // Optional: prevent wrapping
            ),
          ),
          Expanded(
            flex: 3,
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
          const SizedBox(width: 5),
          Expanded(
            flex: 5,
            child: Wrap(
              alignment: WrapAlignment.end,
              direction: Axis.horizontal, // Ensures horizontal layout
              spacing: 0, // Horizontal space between children
              runSpacing: 0.h, // Vertical space between lines
              children: [
                ElevatedButton(
                  onPressed: () async {
                    bool isProcessing = false;
                    final TextEditingController amountController =
                        TextEditingController();
                    isProcessing = false;
                    String statusLabel = "Enter Amount"; // dynamic label
                    await showDialog<double>(
                      barrierDismissible: false,
                      context: context,
                      builder: (context) {
                        return StatefulBuilder(
                          builder: (context, setState) {
                            return AlertDialog(
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
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
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
                                                    color: Colors.black,
                                                    fontSize: 16.sp),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                amountController.text.isEmpty
                                                    ? '0'
                                                    : amountController.text,
                                                style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 16.sp),
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
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10),
                                          children: [
                                            ElevatedButton(
                                              onPressed: isProcessing
                                                  ? null
                                                  : () {
                                                      setState(() {
                                                        amountController.text +=
                                                            '1';
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
                                                        amountController.text +=
                                                            '2';
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
                                                        amountController.text +=
                                                            '3';
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
                                                        amountController.text +=
                                                            '4';
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
                                                        amountController.text +=
                                                            '5';
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
                                                        amountController.text +=
                                                            '6';
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
                                                        amountController.text +=
                                                            '7';
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
                                                        amountController.text +=
                                                            '8';
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
                                                        amountController.text +=
                                                            '9';
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
                                                      amountController.text
                                                          .contains('.')
                                                  ? null
                                                  : () {
                                                      setState(() {
                                                        amountController.text +=
                                                            '.';
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
                                                        amountController.text +=
                                                            '0';
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
                                                          amountController
                                                                  .text =
                                                              amountController
                                                                  .text
                                                                  .substring(
                                                                      0,
                                                                      amountController
                                                                              .text
                                                                              .length -
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
                                                      Navigator.of(context)
                                                          .pop();
                                                    },
                                              style: ElevatedButton.styleFrom(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  backgroundColor: Colors.red,
                                                  foregroundColor:
                                                      Colors.white),
                                              child: const Text('X'),
                                            ),
                                            ElevatedButton(
                                              onPressed: isProcessing
                                                  ? null
                                                  : () {
                                                      setState(() {
                                                        amountController
                                                            .clear();
                                                      });
                                                    },
                                              style: ElevatedButton.styleFrom(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  backgroundColor:
                                                      Colors.yellow,
                                                  foregroundColor:
                                                      Colors.black),
                                              child: const Text('C'),
                                            ),
                                            ElevatedButton(
                                              onPressed: isProcessing
                                                  ? null
                                                  : () async {
                                                      final value =
                                                          double.tryParse(
                                                              amountController
                                                                  .text);
                                                      if (value != null &&
                                                          value > 0) {
                                                        setState(() {
                                                          isProcessing = true;
                                                          statusLabel =
                                                              "Processing payment...";
                                                        });

                                                        final prefs =
                                                            await SharedPreferences
                                                                .getInstance();
                                                        final payerPlayerID =
                                                            prefs.getString(
                                                                    'playerID') ??
                                                                'UnknownPlayer';
                                                        final rewardAmount =
                                                            value;

                                                        // Fetch payer wallet
                                                        final payerResponse =
                                                            await Supabase
                                                                .instance.client
                                                                .from(
                                                                    'players_test')
                                                                .select(
                                                                    'wallet')
                                                                .eq(
                                                                    'game_id',
                                                                    widget
                                                                        .gameId)
                                                                .eq('player_id',
                                                                    payerPlayerID)
                                                                .maybeSingle();

                                                        // Fetch receiver wallet (the selected player)
                                                        final receiverResponse =
                                                            await Supabase
                                                                .instance.client
                                                                .from(
                                                                    'players_test')
                                                                .select(
                                                                    'wallet')
                                                                .eq(
                                                                    'game_id',
                                                                    widget
                                                                        .gameId)
                                                                .eq(
                                                                    'player_id',
                                                                    player
                                                                        .playerID)
                                                                .maybeSingle();

                                                        if (payerResponse !=
                                                                null &&
                                                            receiverResponse !=
                                                                null &&
                                                            payerResponse[
                                                                    'wallet'] !=
                                                                null &&
                                                            receiverResponse[
                                                                    'wallet'] !=
                                                                null) {
                                                          double payerWallet =
                                                              (payerResponse[
                                                                          'wallet']
                                                                      as num)
                                                                  .toDouble();
                                                          if (payerWallet >=
                                                              rewardAmount) {
                                                            // One atomic call: the database locks
                                                            // both rows, re-checks the funds and
                                                            // writes both wallets, so a payment
                                                            // landing at the same moment can no
                                                            // longer lose this one.
                                                            final TransferOutcome
                                                                transfer =
                                                                await WalletTransfer
                                                                    .pay(
                                                              gameId: widget.gameId,
                                                              fromId: payerPlayerID,
                                                              fromRole: WalletTransfer
                                                                  .bankerRole,
                                                              toId: player.playerID,
                                                              toRole: WalletTransfer
                                                                  .playerRole,
                                                              amount: rewardAmount,
                                                            );

                                                            if (!transfer.ok) {
                                                              setState(() {
                                                                statusLabel =
                                                                    "Insufficient balance X";
                                                                isProcessing =
                                                                    false;
                                                              });
                                                              return;
                                                            }

                                                            // Log transaction
                                                            await Supabase
                                                                .instance.client
                                                                .from(
                                                                    'transactions')
                                                                .insert({
                                                              'game_id':
                                                                  widget.gameId,
                                                              'value':
                                                                  rewardAmount,
                                                              'from':
                                                                  "Bank", // or use actual name if needed
                                                              'to': player.name,
                                                              'code':
                                                                  "${payerPlayerID}_${player.playerID}",
                                                              'date': DateFormat(
                                                                      'yyyy-MM-dd')
                                                                  .format(DateTime
                                                                      .now()),
                                                              'time': DateFormat(
                                                                      'HH:mm:ss')
                                                                  .format(DateTime
                                                                      .now()),
                                                            });

                                                            // Show success
                                                            setState(() {
                                                              statusLabel =
                                                                  "Rewarded ₹$rewardAmount to ${player.name} ✓";
                                                            });

                                                            await Future.delayed(
                                                                const Duration(
                                                                    seconds:
                                                                        2));
                                                            if (context.mounted)
                                                              Navigator.of(
                                                                      context)
                                                                  .pop();
                                                          } else {
                                                            setState(() {
                                                              statusLabel =
                                                                  "Insufficient balance X";
                                                              isProcessing =
                                                                  false;
                                                            });
                                                          }
                                                        } else {
                                                          setState(() {
                                                            statusLabel =
                                                                "Failed to fetch wallet data ⊘";
                                                            isProcessing =
                                                                false;
                                                          });
                                                        }
                                                      } else {
                                                        setState(() {
                                                          statusLabel =
                                                              "Invalid amount !!";
                                                        });
                                                      }
                                                    },
                                              style: ElevatedButton.styleFrom(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                              ),
                                              child: const Icon(
                                                  Icons.keyboard_arrow_right),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(5), // Remove internal padding
                    fixedSize: Size(25.sp, 20.sp), // 👈 Set button size here

                    elevation: 0,
                    foregroundColor: player.color,
                    backgroundColor: Colors.white.withValues(alpha: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Image.asset(
                    'assets/images/pay.png', fit: BoxFit.contain,

                    width: 23
                        .sp, // Use MediaQuery or a fixed size if sp is undefined
                    height: 23.sp,

                    color: Color(0xFF689F38), // Apply red color
                    colorBlendMode:
                        BlendMode.srcIn, // Ensures image is tinted red
                  ),
                ),
                const SizedBox(width: 5),
                ElevatedButton(
                  onPressed: () async {
                    advancing();
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
                      if (payerWallet >= advanceAmount) {
                        // One atomic call: the database locks both rows,
                        // re-checks the funds and writes both wallets, so a
                        // payment landing at the same moment cannot lose this
                        // one.
                        final TransferOutcome transfer =
                            await WalletTransfer.pay(
                          gameId: widget.gameId,
                          fromId: payerPlayerID,
                          fromRole: WalletTransfer.bankerRole,
                          toId: player.playerID,
                          toRole: WalletTransfer.playerRole,
                          amount: advanceAmount,
                        );

                        if (!transfer.ok) {
                          Navigator.of(context).pop();
                          if (context.mounted) {
                            showMessage(context,
                                'Insufficient balance to advance ₹200');
                          }
                          return;
                        }

                        if (context.mounted) {
                          Navigator.of(context).pop();
                          if (context.mounted) {
                            showMessage(context,
                                'Advanced ₹$advanceAmount to ${player.name}');
                          }
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
                        Navigator.of(context).pop();
                        if (context.mounted) {
                          showMessage(context,
                              'Insufficient balance to advance ₹200');
                        }
                      }
                    } else {
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        showMessage(context, 'Failed to fetch wallet data');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    padding: const EdgeInsets.all(5), // Remove internal padding
                    fixedSize: Size(25.sp,
                        20.sp), // 👈 Set button size here                    elevation: 0,
                    foregroundColor: Colors.red,
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
                    color: Colors.red,
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
          backgroundColor: Color(0xFFFFF8E1),
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
    return PopScope(
      canPop: false,
      // Intercept the back press and show the confirmation instead.
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool shouldLeave = await _onWillPop();
        if (shouldLeave && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.yellow.shade50,
        appBar: AppBar(
          backgroundColor: Colors.yellow.shade50,
          automaticallyImplyLeading: false,
          title: const Text(
            'Bankpop',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF689F38)),
          ),
          actions: [
            IconButton(
                onPressed: () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TransactionHistoryPage(
                        gameId: widget.gameId,
                        playerId: ID,
                        showAllPlayers: true,
                      ),
                    ),
                  );
                },
                icon: const Icon(FontAwesomeIcons.clockRotateLeft)),
            const SizedBox(width: 5),
            // The board itself, to check who owns what. Selling stays in Give
            // Card; here a tap only ever opens a deed. Cards mode decides
            // whether there is anything to look at.
            if (_playWithCards)
              IconButton(
                onPressed: _showBoard,
                icon: const Icon(Icons.grid_on),
                tooltip: 'Board',
              ),
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
                icon: const Icon(FontAwesomeIcons.rightFromBracket)),
            const SizedBox(width: 5),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              color: const Color(0xFFFFF9C4), // soft pastel yellow
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Icon(
                                  FontAwesomeIcons.buildingColumns,
                                  color: Colors.blueGrey.shade700,
                                  size: 22.sp,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Bankpop Union',
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey.shade800,
                                  ),
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
                                  milliseconds:
                                      500), // optional: animation speed
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 42.sp,
                          child: Lottie.asset('assets/lottie/coin.json'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Give Card only exists in a game that was started with the
                    // cards switch on, so it appears with it.
                    if (payOption == 'ScanPay' || _playWithCards)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (payOption == 'ScanPay') ...[
                            const ReceiveButton(),
                            const SizedBox(width: 8),
                          ],
                          if (_playWithCards)
                            ElevatedButton.icon(
                              onPressed: _openGiveCardFlow,
                              icon: Icon(
                                FontAwesomeIcons.handHolding,
                                size: 16.sp,
                              ),
                              label: Text(
                                'Give Card',
                                style: TextStyle(fontSize: 16.sp),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                backgroundColor: const Color(0xFF1565C0),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
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
            ),
            const SizedBox(
              height: 5,
            ),
            isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF689F38)),
                  )
                : Expanded(
                    child: ListView.builder(
                      itemCount: players.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 5),
                        child: _buildPlayerRow(context, players[index]),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

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

  /// Value equality, so `listEquals` in the screen can tell an unchanged roster
  /// apart from one whose wallets moved. Without it every poll rebuilt the whole
  /// list; `color` is derived from `name`, so it stays out of the comparison.
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
