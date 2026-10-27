import 'dart:async';
import 'dart:math' as math;

import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/pages/transactions/receive.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/bank_handover.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/card_deck.dart';
import 'package:mon/services/card_requests.dart';
import 'package:mon/services/deals.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/bank_handover_qr.dart';
import 'package:mon/widgets/banker_board_panel.dart';
import 'package:mon/widgets/card_effect_flow.dart';
import 'package:mon/widgets/player_badge.dart';
import 'package:mon/widgets/game_controls.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/player_palette.dart';
import 'package:mon/widgets/game_status_banner.dart';
import 'package:mon/widgets/qr_box.dart';
import 'package:mon/widgets/app_metrics.dart';
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

  /// Cards game, read from the bank row of this game. The banker writes it
  /// once at game start; every device reads it back from the same row.
  bool _playWithCards = false;

  /// Stake and round advance, read from the bank row. The device that
  /// started the game typed them, but a second banker device (or this one
  /// after prefs were cleared) has to be able to read them back.
  ///
  /// Null means "not yet known". The prefs copies are consulted as a
  /// fallback only while the columns are missing from the row.
  double? _playerValue;
  double? _advanceValue;

  /// The game's row in `game_sessions`: the rules and the lifecycle. Null on a
  /// project that has not run game_sessions.sql yet, in which case the screen
  /// keeps using its local copies exactly as before.
  GameSession? _session;
  StreamSubscription<List<Map<String, dynamic>>>? _rosterUpdates;
  StreamSubscription<List<Map<String, dynamic>>>? _requestUpdates;
  StreamSubscription<GameSession>? _sessionUpdates;

  @override
  void initState() {
    super.initState();
    value = widget.bankValue;
    fetchPlayers(); // Initial load
    _subscribeToRoster(); // Live roster and bank header
    _subscribeToRequests(); // Live join requests
    _subscribeToSession(); // Live suspend/resume/end
    _loadSession(); // First read, before the socket connects
    startPolling(); // Reconciliation, in case Realtime is unavailable
    _loadStartupSettings();
    // The board this game was started on, before anything reads a card name.
    BoardCatalog.useForGame(widget.gameId);
  }

  @override
  void dispose() {
    _rosterUpdates?.cancel();
    _requestUpdates?.cancel();
    _sessionUpdates?.cancel();
    _pollingTimer?.cancel(); // Clean up timer
    super.dispose();
  }

  Future<void> _loadSession() async {
    final GameSession? session = await GameSession.fetch(widget.gameId);
    if (session != null) {
      BoardCatalog.use(session.boardId);
      _applySession(session);
    }
  }

  void _subscribeToSession() {
    try {
      _sessionUpdates = GameSession.stream(widget.gameId).listen(
        _applySession,
        onError: (Object error) =>
            debugPrint('Session stream error, still polling: $error'),
      );
    } catch (e) {
      debugPrint('Could not subscribe to the game session: $e');
    }
  }

  /// The single place a session row becomes screen state, so a live update and
  /// a polled one cannot disagree.
  void _applySession(GameSession session) {
    if (!mounted || session.gameId != widget.gameId) return;
    final bool changed = _session?.status != session.status ||
        payOption != session.paymentOption ||
        _playWithCards != session.playWithCards ||
        _playerValue != session.playerValue ||
        _advanceValue != session.advanceValue;
    if (!changed && _session != null) return;
    setState(() {
      _session = session;
      payOption = session.paymentOption;
      _playWithCards = session.playWithCards;
      _playerValue = session.playerValue;
      _advanceValue = session.advanceValue;
    });
  }

  /// Suspend, resume or end this game.
  Future<void> _setSessionStatus(String status) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(status == GameSession.ended
            ? 'End this game?'
            : status == GameSession.suspended
                ? 'Suspend this game?'
                : 'Resume this game?'),
        content: Text(
          status == GameSession.ended
              ? 'The game is marked as finished and cannot be resumed. '
                  'Players will be told it ended.'
              : status == GameSession.suspended
                  ? 'Every player device is told the game is paused. Nothing '
                      'is lost - resuming continues exactly where you stopped.'
                  : 'Players can play again from where the game was paused.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(status == GameSession.ended ? 'End game' : 'Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final bool ok = await GameSession.setStatus(widget.gameId, status);
    if (!mounted) return;
    if (!ok) {
      showMessage(context, 'Could not update the game - try again');
      return;
    }
    setState(() {
      _session = _session?.copyWith(status: status);
    });
    showMessage(
      context,
      status == GameSession.ended
          ? 'Game ended.'
          : status == GameSession.suspended
              ? 'Game suspended. Resume it from here or from Your Games.'
              : 'Game resumed.',
    );
  }

  /// Moves the bank to a player who is not at the table yet.
  ///
  /// The banker shows a QR; a player who is not already in this game scans it,
  /// and this screen asks the banker to confirm before anything moves. The
  /// bank's wallet travels with the role, unchanged, and the previous banker
  /// keeps a view-only row so they can watch the game - or open it later from
  /// Your Games - without being able to pay, advance or pause anything.
  Future<void> _handOverBank() async {
    if (_session?.isEnded ?? false) {
      await showMessage(context, 'This game has ended - the bank cannot move.');
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String myId =
        ID.isNotEmpty ? ID : (prefs.getString('playerID') ?? '');
    if (!mounted) return;
    if (myId.isEmpty) {
      await showMessage(context, 'This device has no player id.');
      return;
    }
    final String myName = prefs.getString('profile_name') ??
        prefs.getString('display_name') ??
        'Ex-banker';
    final String? myAvatar = prefs.getString('avatar_path');

    while (mounted) {
      final HandoverRequest? claim = await showDialog<HandoverRequest>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => BankHandoverQrDialog(
          gameId: widget.gameId,
          bankerId: myId,
        ),
      );
      if (!mounted || claim == null) return;

      final bool confirmed = await showAppConfirm(
        context,
        title: '${claim.name} scanned your code',
        icon: Icons.swap_horiz,
        confirmLabel: 'Hand over',
        message:
            'Make ${claim.name} the banker? They get the bank balance exactly '
            'as it is now, and every control that comes with it.\n\n'
            'You stay at the table as an ex-banker: you can watch the game and '
            'find it in Your Games, but only the new banker can pay, advance, '
            'pause or end it.',
      );
      if (!mounted) return;
      if (!confirmed) {
        // Declined: the claim goes away and the code stays up for somebody
        // else rather than quietly handing the bank to the next scan.
        await BankHandover.withdraw(claim);
        continue;
      }

      // The code may have been left open on a screen that no longer holds the
      // bank. Check the live row before moving anything.
      final bool stillBanker =
          await BankHandover.holdsBank(widget.gameId, myId);
      if (!mounted) return;
      if (!stillBanker) {
        await BankHandover.withdraw(claim);
        await showMessage(
          context,
          'This device is no longer the banker, so the bank did not move.',
          title: 'Nothing changed',
        );
        return;
      }

      final bool ok = await BankHandover.complete(
        gameId: widget.gameId,
        oldBankerId: myId,
        oldBankerName: myName,
        oldBankerAvatar: myAvatar,
        newBankerId: claim.playerId,
        newBankerName: claim.name,
      );
      if (!mounted) return;
      if (!ok) {
        await BankHandover.withdraw(claim);
        await showMessage(context, 'Could not hand over the bank - try again');
        return;
      }

      await showMessage(
        context,
        '${claim.name} is the banker now. You can watch this table, but only '
        'they can pay, advance, pause or end it. The game stays in Your Games.',
        title: 'Bank handed over',
      );
      if (!mounted) return;
      // Stay at the table as an ex-banker instead of going home.
      context.go(AppRoutes.player(widget.gameId));
      return;
    }
  }

  void _showGameMenu() {
    final bool suspended = _session?.isSuspended ?? false;
    final bool ended = _session?.isEnded ?? false;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFF8E1),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                suspended
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline,
                color: const Color(0xFF689F38),
              ),
              title: Text(suspended ? 'Resume game' : 'Suspend game'),
              subtitle: Text(
                suspended
                    ? 'Let everyone continue where they stopped'
                    : 'Pause the game; players can return later',
              ),
              enabled: !ended,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setSessionStatus(
                  suspended ? GameSession.active : GameSession.suspended,
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.flag_outlined, color: Color(0xFFC62828)),
              title: const Text('End game'),
              subtitle: const Text('Mark the game as finished for good'),
              enabled: !ended,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setSessionStatus(GameSession.ended);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Color(0xFF2E7D32)),
              title: const Text('Hand over the bank'),
              subtitle: const Text(
                  'Another player takes over paying, advancing and pausing'),
              enabled: !ended,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _handOverBank();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
      // Reconciliation for the session too: the socket may be down, and a
      // suspension must not be missed because of it.
      unawaited(_loadSession());

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

    // Removed players stay in the list: the badge beside the name is how the
    // banker (and everyone else) sees who is gone and why. They sort to the
    // bottom so the live table stays at the top of the screen.
    final List<Map<String, dynamic>> roster = rows
        .where((Map<String, dynamic> row) =>
            row['role'] == 'player' ||
            row['role'] == PlayerStanding.kicked.name)
        .toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final bool aGone = PlayerStanding.fromRow(a).isGone;
        final bool bGone = PlayerStanding.fromRow(b).isGone;
        if (aGone != bGone) return aGone ? 1 : -1;
        return ((b['wallet'] as num?) ?? 0)
            .compareTo((a['wallet'] as num?) ?? 0);
      });

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

    // The rules of the game (pay mode, cards switch, stake, advance) are read
    // from `game_sessions` by _applySession, not from the banker's wallet row:
    // they describe the game, and a player device should not have to read the
    // bank's balance to learn them. This only owns the header.
    if (_session == null) {
      // A project that has not run game_sessions.sql yet still keeps the rules
      // on the banker's row. Read them there, exactly as before, so the screen
      // does not lose ScanPay or cards the moment the session is missing.
      final String bankPayOption = (bankRow['SP/IP'] as String?) ?? payOption;
      final bool bankCardsMode = bankRow.containsKey('play_with_cards')
          ? bankRow['play_with_cards'] == true
          : _playWithCards;
      double? nextPlayerValue = _playerValue;
      if (bankRow['player_value'] is num) {
        nextPlayerValue = (bankRow['player_value'] as num).toDouble();
      }
      double? nextAdvanceValue = _advanceValue;
      if (bankRow['advance_value'] is num) {
        nextAdvanceValue = (bankRow['advance_value'] as num).toDouble();
      }
      if (bankPayOption != payOption ||
          bankCardsMode != _playWithCards ||
          nextPlayerValue != _playerValue ||
          nextAdvanceValue != _advanceValue) {
        setState(() {
          payOption = bankPayOption;
          _playWithCards = bankCardsMode;
          _playerValue = nextPlayerValue;
          _advanceValue = nextAdvanceValue;
        });
      }
    }
    if (bankWallet != value) {
      setState(() => value = bankWallet);
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
    // A hand-over claim is answered on the QR dialog, with a confirmation that
    // says what it does. It must never appear as somebody asking for a seat.
    final List<Map<String, dynamic>> joins = requests
        .where((Map<String, dynamic> row) => !BankHandover.isClaim(row))
        .toList();
    if (joins.isEmpty) return;
    // A finished game takes no new seats. A paused one still does - a player
    // waiting on approval has not moved any money, so they may sit down and
    // wait for the resume like everyone else.
    if (_session?.isEnded ?? false) return;

    _isAlsoPlayer ??= await _holdsPlayerRow(Supabase.instance.client);

    if (!_isAlsoPlayer!) {
      await _processRequestsSequentially(joins);
    }
  }

  /// Whether this device also holds a player row in this game. It cannot change
  /// while the screen is open, so it is resolved at most once per session
  /// instead of on every poll.
  Future<bool> _holdsPlayerRow(SupabaseClient supabase) async {
    final prefs = await SharedPreferences.getInstance();
    final playerID = prefs.getString('playerID');
    if (playerID == null) return true; // Keep the previous no-prompt path

    // A player row can also be the fallback `role = 'kicked'` marker on a
    // project without player_status.sql; either way this device is holding a
    // seat, so the banker must not be asked to approve itself.
    final List<dynamic> rows = await supabase
        .from('players_test')
        .select('id')
        .inFilter('role', <String>['player', PlayerStanding.kicked.name])
        .eq('player_id', playerID)
        .eq('game_id', widget.gameId)
        .limit(1);

    return rows.isNotEmpty;
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
                  // The stake is a property of the game, read from the bank
                  // row. prefs is only a fallback while the row cannot carry
                  // it (project without shared_game_state.sql).
                  final double? stakeAmount = _playerValue;
                  if (stakeAmount == null) {
                    Navigator.of(context).pop();
                    if (mounted) {
                      showMessage(this.context,
                          'Could not read the player stake - try again');
                    }
                    return;
                  }

                  // One call seats the player, moves the stake off the bank
                  // (which is allowed to go negative) and clears the request.
                  final StakeOutcome stake = await WalletTransfer.stake(
                    gameId: widget.gameId,
                    playerId: '${request['player_id']}',
                    playerName: '${request['name']}',
                    amount: stakeAmount,
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
                    showMessage(this.context,
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

  /// Seeds the screen's local fallbacks before the first bank row arrives.
  ///
  /// The cards switch is not read here any more: it is written on the bank row
  /// at game start and read back by _applyGameRows, which runs on the same
  /// first tick. [ID] and the two amounts are seeded from prefs only so the
  /// screen has something to show while the row is in flight, or on a project
  /// where the row cannot carry them. The row overwrites them the moment it
  /// lands.
  Future<void> _loadStartupSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String ownId = prefs.getString('playerID') ?? '';
    final double? stake = prefs.getDouble('playerValue');
    final double? advance = prefs.getDouble('advance');
    final String payPreference = prefs.getString('payOption') ?? '';
    final bool? cardsPreference = prefs.getBool('playWithCards');
    if (!mounted) return;
    setState(() {
      if (ownId.isNotEmpty) ID = ownId;
      // The session, when this project has one, is the source of truth and has
      // already won any race: these locals only fill the gap on an old project.
      if (_session != null) return;
      _playerValue ??= stake;
      _advanceValue ??= advance;
      if (payPreference.isNotEmpty) payOption = payPreference;
      if (cardsPreference != null) _playWithCards = cardsPreference;
    });
  }

  /// Houses and hotels the players have asked for. Each request is a yes/no for
  /// the banker: approving charges the player and puts the building up together,
  /// declining charges nothing.
  Future<void> _checkCardRequests() async {
    // Building is play: a request waits until the banker resumes the table, and
    // is never settled into an ended game.
    if (_viewOnly) return;
    if (_isProcessingCardRequest) return;
    _isProcessingCardRequest = true;

    try {
      final List<CardRequest> requests =
          await CardRequests.pending(widget.gameId);
      if (requests.isEmpty || !mounted) return;

      final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
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
          showMessage(
              context, 'Declined ${request.playerName}\'s ${request.kind}',
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
    // Mortgages, building sales and trades move money, so they wait for the
    // resume and never land after the end.
    if (_viewOnly) return;
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

      final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
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
  ) async {
    final String cards =
        deal.cards.map((int i) => spaces[i]?.name ?? 'Card #$i').join(', ');
    String? autoClosed;
    Timer? poll;
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        poll = Timer.periodic(const Duration(seconds: 2), (Timer t) async {
          final String? status = await Deals.statusOf(deal.id);
          if (!dialogContext.mounted) {
            t.cancel();
            return;
          }
          if (status == null || status == 'pending') return;
          t.cancel();
          autoClosed = status;
          Navigator.of(dialogContext).pop(null);
        });
        return AlertDialog(
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
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
    poll?.cancel();
    if (autoClosed != null && mounted) {
      await showMessage(
        context,
        autoClosed == 'cancelled'
            ? '${deal.fromName} cancelled the request.'
            : 'The request was already settled.',
        title: autoClosed == 'cancelled' ? 'Cancelled' : 'Already settled',
      );
      return null;
    }
    return result;
  }

  /// The banker's card draw: pick Chance or Community Chest, and the next card
  /// of that pack is shown to the table.
  ///
  /// The packs are shuffled once when the game starts and then dealt in order,
  /// so this shows how many cards are left in each. The picks are listed as
  /// they are dealt; the shuffle option here is for a pack that has been worked
  /// through (a draw does that on its own) or for a banker who wants a fresh
  /// order.
  Future<void> _showCardDecks() async {
    final BankpopBoard board;
    try {
      board = await BoardCatalog.boardForGame(widget.gameId);
    } catch (error) {
      debugPrint('Could not read the board for a card draw: $error');
      if (!mounted) return;
      showMessage(context, 'The board could not be read - try again.');
      return;
    }
    if (!mounted) return;

    final int chanceLeft = await CardDeck.left(
      gameId: widget.gameId,
      kind: CardDeckKind.chance,
      cards: board.chanceOptions,
    );
    final int chestLeft = await CardDeck.left(
      gameId: widget.gameId,
      kind: CardDeckKind.chest,
      cards: board.communityChest,
    );
    if (!mounted) return;

    final Object? picked = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: const Color(0xFFFFF8E1),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Draw a card',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF33691E),
                ),
              ),
            ),
            for (final CardDeckKind option in CardDeckKind.values)
              ListTile(
                leading: Icon(
                  option == CardDeckKind.chance
                      ? Icons.casino_outlined
                      : Icons.inventory_2_outlined,
                  color: const Color(0xFF6A1B9A),
                ),
                title: Text(option.label),
                subtitle: Text(
                  _packStatus(
                    option,
                    option == CardDeckKind.chance ? chanceLeft : chestLeft,
                    option == CardDeckKind.chance
                        ? board.chanceOptions.length
                        : board.communityChest.length,
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.shuffle, color: Color(0xFF6A1B9A)),
              title: const Text('Shuffle both packs'),
              subtitle: const Text(
                'Deals a fresh order from the top of each pack.',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.of(sheetContext).pop('shuffle'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;

    if (picked == 'shuffle') {
      await CardDeck.shuffle(
        gameId: widget.gameId,
        kind: CardDeckKind.chance,
        cards: board.chanceOptions,
      );
      await CardDeck.shuffle(
        gameId: widget.gameId,
        kind: CardDeckKind.chest,
        cards: board.communityChest,
      );
      if (!mounted) return;
      await showMessage(
        context,
        'Both packs are shuffled and ready to be drawn again.',
        title: 'Packs shuffled',
      );
      return;
    }

    await _drawCard(picked as CardDeckKind);
  }

  /// What one pack's row says under its name.
  String _packStatus(CardDeckKind kind, int left, int total) {
    if (total == 0) {
      return 'This board has no ${kind.label.toLowerCase()} cards.';
    }
    if (left <= 0) {
      return 'The pack has been worked through: the next draw shuffles it again.';
    }
    return '$left of $total left. The next card comes off the top.';
  }

  /// Deals the next card of [kind]'s pack and shows it. The card is not put
  /// back in the middle of the pack: the pack is worked through in order, and
  /// once it has all been seen the next draw shuffles it again.
  Future<void> _drawCard(CardDeckKind kind) async {
    final BankpopBoard board;
    try {
      board = await BoardCatalog.boardForGame(widget.gameId);
    } catch (error) {
      debugPrint('Could not read the board for a card draw: $error');
      if (!mounted) return;
      showMessage(context, 'The board could not be read - try again.');
      return;
    }
    if (!mounted) return;

    final List<String> cards = kind == CardDeckKind.chance
        ? board.chanceOptions
        : board.communityChest;
    if (cards.isEmpty) {
      showMessage(context, 'This board has no ${kind.label.toLowerCase()} cards.');
      return;
    }

    final CardDeckDraw? draw = await CardDeck.draw(
      gameId: widget.gameId,
      kind: kind,
      cards: cards,
    );
    if (!mounted) return;
    if (draw == null) {
      showMessage(context, 'There is no card to draw.');
      return;
    }

    // The card is shown with whatever it asks the table to do: a reward, a
    // fine, repairs billed on what the player built, a collection from every
    // other player, or a jail-free card that goes into a player's hand.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String bankerId = prefs.getString('playerID') ?? ID;
    if (!mounted) return;
    await showCardEffectFlow(
      context,
      gameId: widget.gameId,
      bankerId: bankerId,
      cardText: draw.card,
      kind: kind,
      currency: board.currency,
    );
    if (!mounted) return;
    if (draw.reshuffled) {
      await showMessage(
        context,
        'The ${kind.label.toLowerCase()} pack had been worked through, so it '
        'was shuffled again and this was the first card of the new deal.',
        title: 'Pack reshuffled',
      );
    }
  }

  void _showQRDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
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
          width: 70.w,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            mainAxisSize: MainAxisSize.min,
            children: [
              // A phone camera needs modules it can resolve. The old 50.sp
              // code was too small to scan, which is why joining by scan kept
              // failing; but `gapless: true` then drew the modules of this
              // very small (version 1) code as one solid block, so the finder
              // patterns blurred together and the scanner never locked on.
              // The pay and card codes, which keep the gap between modules,
              // were read without trouble - so this one does too.
              QrBox(
                data: widget.gameId,
                size: 58.w,
                padding: const EdgeInsets.all(10),
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
            backgroundImage: ResizeImage(AssetImage(player.avatar), width: 144),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: 3,
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    '${player.name[0].toUpperCase()}${player.name.substring(1)}',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.bold,
                      // A removed player is greyed out so the list reads at a
                      // glance: the live table on top, the gone ones faded.
                      color: player.standing.isGone
                          ? player.color.withValues(alpha: 0.55)
                          : player.color,
                      decoration: player.standing.isGone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
                // REMOVED, so the banker can see at a glance whose seat the
                // bank has taken back.
                PlayerStandingBadge(
                  standing: player.standing,
                  compact: true,
                ),
              ],
            ),
          ),
          // scaleDown lets a long balance shrink into its third of the row
          // instead of pushing the action buttons past the right edge on a
          // narrow phone.
          Expanded(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
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
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: 5,
            // A Row, not a Wrap: the icon buttons always belong side by side,
            // and a Wrap would drop one onto a hidden second line whenever the
            // slot got tight (as it did at 320 px). They are wrapped in a
            // scaleDown so the third button (remove) shrinks the row instead of
            // overflowing it on the narrowest phone.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // A player who is gone has nothing to pay or advance: both
                  // buttons would only fail against a closed row.
                  if (!player.standing.isGone && !_viewOnly)
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
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 0,
                                                      horizontal: 10),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                      horizontal: 10),
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
                                                    amountController
                                                            .text.isEmpty
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10),
                                              children: [
                                                ElevatedButton(
                                                  onPressed: isProcessing
                                                      ? null
                                                      : () {
                                                          setState(() {
                                                            amountController
                                                                .text += '1';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '1',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '2';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '2',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '3';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '3',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '4';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '4',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '5';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '5',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '6';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '6',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '7';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '7',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '8';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '8',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '9';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '9',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '.';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '.',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                            amountController
                                                                .text += '0';
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Text(
                                                    '0',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                                .text
                                                                .isNotEmpty) {
                                                              amountController
                                                                      .text =
                                                                  amountController
                                                                      .text
                                                                      .substring(
                                                                          0,
                                                                          amountController.text.length -
                                                                              1);
                                                            }
                                                          });
                                                        },
                                                  style: _buttonStyle(),
                                                  child: const Icon(
                                                      Icons.backspace,
                                                      color: Colors.grey),
                                                ),
                                                ElevatedButton(
                                                  onPressed: isProcessing
                                                      ? null
                                                      : () {
                                                          Navigator.of(context)
                                                              .pop();
                                                        },
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10),
                                                          ),
                                                          backgroundColor:
                                                              Colors.red,
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
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
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
                                                              isProcessing =
                                                                  true;
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
                                                            final payerResponse = await Supabase
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
                                                            final receiverResponse = await Supabase
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

                                                            if (payerResponse != null &&
                                                                receiverResponse !=
                                                                    null &&
                                                                payerResponse[
                                                                        'wallet'] !=
                                                                    null &&
                                                                receiverResponse[
                                                                        'wallet'] !=
                                                                    null) {
                                                              double
                                                                  payerWallet =
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
                                                                  gameId: widget
                                                                      .gameId,
                                                                  fromId:
                                                                      payerPlayerID,
                                                                  fromRole:
                                                                      WalletTransfer
                                                                          .bankerRole,
                                                                  toId: player
                                                                      .playerID,
                                                                  toRole: WalletTransfer
                                                                      .playerRole,
                                                                  amount:
                                                                      rewardAmount,
                                                                );

                                                                if (!transfer
                                                                    .ok) {
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
                                                                    .instance
                                                                    .client
                                                                    .from(
                                                                        'transactions')
                                                                    .insert({
                                                                  'game_id':
                                                                      widget
                                                                          .gameId,
                                                                  'value':
                                                                      rewardAmount,
                                                                  'from':
                                                                      "Bank", // or use actual name if needed
                                                                  'to': player
                                                                      .name,
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
                                                                if (context
                                                                    .mounted)
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
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    backgroundColor:
                                                        Colors.green,
                                                    foregroundColor:
                                                        Colors.white,
                                                  ),
                                                  child: const Icon(Icons
                                                      .keyboard_arrow_right),
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
                        // The old 25.sp box plus 5 px of padding was narrower than
                        // the 23.sp icon inside it, which overflowed the row on a
                        // 320 px phone. Zero padding, and an icon that is smaller
                        // than the box, keeps the content inside the button.
                        padding: EdgeInsets.zero,
                        // Logical pixels, not `.sp`: these are icon buttons whose
                        // size should stay a comfortable tap target at every text
                        // scale, and the row they sit in is a fixed height. The
                        // padded tap target would add a 48x48 box around each of
                        // them and push the pair out of the row.
                        fixedSize: const Size(36, 30),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        elevation: 0,
                        foregroundColor: player.color,
                        backgroundColor: Colors.white.withValues(alpha: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Image.asset(
                        'assets/images/pay.png',
                        fit: BoxFit.contain,
                        width: 20.sp,
                        height: 20.sp,
                        color: const Color(0xFF689F38),
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                  if (!player.standing.isGone && !_viewOnly)
                    const SizedBox(width: 4),
                  if (!player.standing.isGone && !_viewOnly)
                    ElevatedButton(
                      onPressed: () async {
                        advancing();
                        final prefs = await SharedPreferences.getInstance();
                        final payerPlayerID =
                            prefs.getString('playerID') ?? 'UnknownPlayer';
                        // The advance is a property of the game, read from the
                        // bank row; prefs is only a fallback while the row cannot
                        // carry it.
                        final double advanceAmount = _advanceValue ?? 0;
                        if (advanceAmount <= 0) {
                          if (context.mounted) {
                            showMessage(context,
                                'Could not read the advance amount - try again');
                          }
                          return;
                        }

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
                                'date': DateFormat('yyyy-MM-dd')
                                    .format(DateTime.now()),
                                'time': DateFormat('HH:mm:ss')
                                    .format(DateTime.now()),
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
                        padding: EdgeInsets.zero,
                        fixedSize: const Size(36, 30),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Colors.red,
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Image.asset(
                        'assets/images/advance.png',
                        width: 20.sp,
                        height: 20.sp,
                        fit: BoxFit.contain,
                        color: Colors.red,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                  // Remove: the one action that is only ever offered for a
                  // player who is still at the table.
                  if (!player.standing.isGone && !_viewOnly) ...<Widget>[
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () => _removePlayer(player),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        fixedSize: const Size(30, 30),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        elevation: 0,
                        foregroundColor: const Color(0xFFC62828),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Icon(Icons.person_remove_alt_1,
                          size: 16.sp, color: const Color(0xFFC62828)),
                    ),
                  ],
                  // Restore: the way back for a removal that was a mistake.
                  // The player returns to the same game with an empty wallet
                  // and no cards, because their cash and their land already
                  // went back into the game.
                  if (player.standing == PlayerStanding.kicked &&
                      !_viewOnly) ...<Widget>[
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () => _restorePlayer(player),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        fixedSize: const Size(30, 30),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        elevation: 0,
                        foregroundColor: const Color(0xFF2E7D32),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Icon(Icons.person_add_alt_1,
                          size: 16.sp, color: const Color(0xFF2E7D32)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Removes a player from the game: their cash, their cards and the houses and
  /// hotels standing on them go back to the bank, and the row is stamped so
  /// every device shows the REMOVED badge from then on.
  ///
  /// Confirmed first, because the money and the property cannot be handed back
  /// by un-removing the player.
  Future<void> _removePlayer(Player player) async {
    // Removing a player moves money and property, so it is subject to the same
    // lifecycle as every other action: not while the table is paused, and not
    // after the game has ended.
    if (_viewOnly) {
      await showMessage(
        context,
        _session?.blockedReason ??
            'The game is not running, so players cannot be removed.',
      );
      return;
    }

    final String bankerId = ID.isNotEmpty
        ? ID
        : ((await SharedPreferences.getInstance()).getString('playerID') ?? '');
    if (bankerId.isEmpty) {
      if (mounted) {
        await showMessage(context,
            'This device has no player id, so the bank cannot be paid.');
      }
      return;
    }

    // What the removal would move, read before anything moves, so the
    // confirmation names the buildings instead of promising to sell them.
    final KickPreview preview = await PlayerExit.preview(
      gameId: widget.gameId,
      playerId: player.playerID,
      playerName: player.name,
    );
    if (!mounted) return;
    final double cash = preview.cash > 0 ? preview.cash : player.value;

    final bool confirmed = await showAppConfirm(
      context,
      title: 'Remove ${player.name}?',
      icon: Icons.person_remove_alt_1,
      destructive: true,
      confirmLabel: 'Remove player',
      message: 'This cannot be undone: they lose their seat at this table for '
          'good, and everyone will see the REMOVED badge next to their name.\n\n'
          'Their cash goes to the bank and every card they hold goes back on '
          'the market unowned. Houses and hotels are sold back with the cards, '
          'so each property starts empty again and can be bought by anyone.',
      extra: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppDialogPoint(
            label: 'Cash to the bank',
            value: cash.toStringAsFixed(2),
            icon: Icons.payments_outlined,
          ),
          AppDialogPoint(
            label: 'Cards back on the market, unowned',
            value: '${preview.cards}',
            icon: Icons.style_outlined,
          ),
          if (preview.hasBuildings)
            AppDialogPoint(
              label: 'Houses and hotels sold back',
              value: preview.buildingSummary,
              icon: Icons.home_work_outlined,
            ),
        ],
      ),
    );
    if (!confirmed || !mounted) return;

    final KickOutcome outcome = await PlayerExit.kick(
      gameId: widget.gameId,
      playerId: player.playerID,
      playerName: player.name,
      bankerId: bankerId,
    );
    if (!mounted) return;

    if (!outcome.ok) {
      await showMessage(
          context, outcome.failure ?? 'Could not remove the player');
      return;
    }

    await fetchPlayers();
    if (!mounted) return;

    final List<String> moved = <String>[
      if (outcome.cash > 0) outcome.cash.toStringAsFixed(2),
      if (outcome.cards > 0)
        '${outcome.cards} card${outcome.cards == 1 ? '' : 's'}'
            '${outcome.buildings > 0 ? " (${outcome.buildings} building${outcome.buildings == 1 ? '' : 's'})" : ''}',
    ];
    await showMessage(
      context,
      moved.isEmpty
          ? '${player.name} was removed. They held nothing, so nothing moved.'
          : '${player.name} was removed. ${moved.join(' and ')} went back to '
              'the bank. Their pending asks were withdrawn.',
      title: 'Player removed',
    );
  }

  /// Puts a removed player back at the table for this game.
  ///
  /// A fresh seat rather than an undo: the money and the cards they held when
  /// they were removed are gone - the bank has the cash and the land is on the
  /// market, possibly already bought - so nothing is taken back off anyone. The
  /// confirmation says so before the seat is handed out.
  Future<void> _restorePlayer(Player player) async {
    if (_viewOnly) {
      await showMessage(
        context,
        _session?.blockedReason ??
            'The game is not running, so a player cannot be restored.',
      );
      return;
    }

    final bool confirmed = await showAppConfirm(
      context,
      title: 'Put ${player.name} back?',
      icon: Icons.person_add_alt_1,
      confirmLabel: 'Restore player',
      cancelLabel: 'Cancel',
      message: 'They come back to this game with an empty wallet and no cards. '
          'The cash and the properties they held when they were removed went '
          'back into the game, so nothing is returned - any card they used to '
          'own belongs to whoever holds it now.\n\n'
          'They rejoin on their own device with this Game ID.',
    );
    if (!confirmed || !mounted) return;

    final RestoreOutcome outcome = await PlayerExit.restore(
      gameId: widget.gameId,
      playerId: player.playerID,
    );
    if (!mounted) return;

    if (!outcome.ok) {
      await showMessage(
          context, outcome.failure ?? 'Could not restore the player');
      return;
    }

    await fetchPlayers();
    if (!mounted) return;
    await showMessage(
      context,
      '${player.name} has a seat again with 0.00 and no cards. They can '
      'rejoin with the Game ID.',
      title: 'Player restored',
    );
  }

  /// Leaves for the title screen and forgets the stored game id, so the next
  /// launch asks what to play instead of reopening this table.
  ///
  /// `pushReplacement`: leaving is a decision, so the browser's back button
  /// must not walk straight back into the table that was just left.
  Future<void> _returnToTitle() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('gameID');
    if (!mounted) return;
    context.pushReplacement(AppRoutes.home);
  }

  Future<bool> _onWillPop() async {
    return showAppConfirm(
      context,
      title: 'Leave game?',
      icon: Icons.logout,
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
      destructive: true,
      message:
          'The game keeps running for the players, and you can come back to '
          'it from Your Games. Do you want to leave this screen?',
    );
  }

  /// True while the game's lifecycle forbids play - paused by the banker, or
  /// ended. The banker keeps the menu and the resume control; every action that
  /// moves money or property is hidden.
  bool get _viewOnly => _session?.blocksPlay ?? false;

  /// Suspend and resume are the same button in two states, so its icon and its
  /// sentence in the legend follow the session.
  GameControl get _suspendControl => (_session?.isSuspended ?? false)
      ? const GameControl(
          icon: Icons.play_circle_outline,
          label: 'Resume / end',
          detail: 'The table is suspended. Resume it for everyone, or end the '
              'game for good.',
          color: Color(0xFF689F38),
        )
      : GameControls.suspend;

  /// Exactly the icons this screen is showing.
  /// The banker's controls, as the info button lists them. The board and Give
  /// Card are gone: the board is part of the screen now, and a tap on one of
  /// its cards is the way a card is given.
  List<GameControl> get _screenControls => <GameControl>[
        GameControls.history,
        GameControls.drawCard,
        GameControls.showBankQr,
        _suspendControl,
        GameControls.leave,
        if (payOption == 'ScanPay') GameControls.receive,
      ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // Intercept the back press and show the confirmation instead.
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool shouldLeave = await _onWillPop();
        // See the player screen: the banker may have entered this game with
        // pushReplacement, so popping would leave nothing underneath.
        if (shouldLeave && mounted) await _returnToTitle();
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
          // Icon-only, in the same sticker style as the buttons on the bank
          // card. The info button explains all of them.
          actions: [
            Row(
              children: <Widget>[
                GameIconButton(
                  control: GameControls.history,
                  size: 36,
                  onPressed: () => context.push(
                    AppRoutes.history(
                      widget.gameId,
                      playerId: ID,
                      showAllPlayers: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Chance and Community Chest are dealt by the banker, not
                // shown as a list of the whole pack.
                GameIconButton(
                  control: GameControls.drawCard,
                  size: 36,
                  onPressed: _showCardDecks,
                ),
                const SizedBox(width: 4),
                GameIconButton(
                  control: GameControls.showBankQr,
                  size: 36,
                  onPressed: () => _showQRDialog(context),
                ),
                const SizedBox(width: 4),
                // Suspend / resume / end. A suspended game is the only way a
                // player can leave and come back to the same board later, so
                // this is one tap rather than a buried settings page.
                GameIconButton(
                  control: _suspendControl,
                  size: 36,
                  onPressed: _showGameMenu,
                ),
                const SizedBox(width: 4),
                GameIconButton(
                  control: GameControls.leave,
                  size: 36,
                  onPressed: () async {
                    final bool shouldLeave = await _onWillPop();
                    if (!shouldLeave) return;
                    await _returnToTitle();
                  },
                ),
                const SizedBox(width: 4),
                GameInfoButton(
                  title: 'Banker controls',
                  controls: _screenControls,
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: AppContent(
          maxWidth: 1100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Paused or ended: the same band the players see, with the way
            // out of the pause offered here rather than hidden in the menu.
            if (_session != null && _session!.blocksPlay)
              GameStatusBanner(
                session: _session!,
                bankerView: true,
                onResume: _session!.isSuspended
                    ? () => _setSessionStatus(GameSession.active)
                    : null,
              ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              color: const Color(0xFFFFF9C4), // soft pastel yellow
              elevation: 3,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: <Widget>[
                    // What the bank is holding, and the code a player pays it
                    // with, in the one row above the board.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Icon(
                                FontAwesomeIcons.buildingColumns,
                                color: Colors.blueGrey.shade700,
                                size: 22.sp,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  'Bankpop Union',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: AnimatedFlipCounter(
                              value: value,
                              fractionDigits: 2,
                              textStyle: TextStyle(
                                fontSize: 26.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              duration: const Duration(milliseconds: 500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (payOption == 'ScanPay' && !_viewOnly) ...<Widget>[
                      const ReceiveButton(),
                      const SizedBox(width: 6),
                    ],
                    SizedBox(
                      height: 38.sp,
                      child: Lottie.asset('assets/lottie/coin.json'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(
              height: 5,
            ),
            const SizedBox(height: 6),
            // A wide window (a monitor, or a tablet in landscape) has the room
            // for the board and the players side by side; a phone keeps them
            // stacked, board over players.
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints area) {
                  final Widget board = Padding(
                    // The inset a player row has, so on a phone the board is
                    // exactly as wide as the list under it.
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: BankerBoardPanel(
                      gameId: widget.gameId,
                      payOption: payOption,
                      bankerId: ID,
                      canGiveCards: _playWithCards && !_viewOnly,
                      // In a row with the players the board starts where they
                      // start - at the top - instead of hanging below a band
                      // of empty paper.
                      alignment: Alignment.topCenter,
                    ),
                  );
                  // The key names this half of the screen, so the layout can
                  // be checked as one region while it is still loading and has
                  // no player rows in it.
                  final Widget playerList = KeyedSubtree(
                    key: const ValueKey<String>('banker-players'),
                    child: isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF689F38)),
                          )
                        : ListView.builder(
                            itemCount: players.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 5),
                              child: _buildPlayerRow(context, players[index]),
                            ),
                          ),
                  );

                  if (area.maxWidth < 720) {
                    // Stacked: the board gets a region of its own height, as
                    // wide as a player row (the width less the same inset) and
                    // as tall as that is wide, so the square fills the column
                    // and no empty paper is left down either side of it. What
                    // is left below it belongs to the players, and it scrolls.
                    final double rowWidth = area.maxWidth - 32;
                    final double side = math.min(
                      rowWidth,
                      math.max(0.0, area.maxHeight - 200),
                    );
                    return Column(
                      children: <Widget>[
                        SizedBox(height: side, child: board),
                        const SizedBox(height: 4),
                        Expanded(child: playerList),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(flex: 3, child: board),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: playerList),
                    ],
                  );
                },
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
  final String playerID;
  final String name;
  final double value;
  final Color color;
  final String avatar;

  /// At the table, or removed by the banker. Drives the badge and whether this
  /// row still offers pay / advance / remove.
  final PlayerStanding standing;

  Player(
      {required this.playerID,
      required this.name,
      required this.value,
      required this.color,
      required this.avatar,
      this.standing = PlayerStanding.active});

  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
        playerID: map['player_id'],
        name: map['name'],
        value: double.tryParse(map['wallet'].toString()) ?? 0.0,
        color: PlayerPalette.forName(map['name'].toString()),
        avatar: map['avatar'] ?? "assets/avatars/boy1.jpg",
        standing: PlayerStanding.fromRow(map));
  }

  /// Value equality, so `listEquals` in the screens can tell an unchanged roster
  /// apart from one whose wallets moved. Without it every poll rebuilt the whole
  /// list; `color` is derived from `name`, so it stays out of the comparison.
  @override
  bool operator ==(Object other) {
    return other is Player &&
        other.playerID == playerID &&
        other.name == name &&
        other.value == value &&
        other.avatar == avatar &&
        other.standing == standing;
  }

  @override
  int get hashCode => Object.hash(playerID, name, value, avatar, standing);
}
