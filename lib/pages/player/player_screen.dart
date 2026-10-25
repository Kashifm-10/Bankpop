import 'dart:async';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/building_rules.dart';
import 'package:mon/services/card_requests.dart';
import 'package:mon/services/deals.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:mon/pages/transactions/receive.dart';
import 'package:mon/widgets/amount_keypad.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/bankpop_board_popup.dart';
import 'package:mon/widgets/card_owner_badge.dart';
import 'package:mon/widgets/bankpop_space_card.dart';
import 'package:mon/widgets/game_controls.dart';
import 'package:mon/widgets/game_status_banner.dart';
import 'package:mon/widgets/trade_builder_dialog.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Player {
  final String playerID;
  final String name;
  final double value;
  final Color color;
  final String avatar;

  /// At the table, departed, or removed by the banker. The roster keeps a gone
  /// player's row so the badge can sit beside their name.
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
        color: Colors.primaries[map['name'].hashCode % Colors.primaries.length],
        avatar: map['avatar'] ?? "assets/avatars/boy1.jpg",
        standing: PlayerStanding.fromRow(map));
  }

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

/// One colour group of this player's cards, in board order, as the My Cards
/// sheet draws them.
class _CardGroup {
  const _CardGroup(this.colour, this.cards);

  final String? colour;
  final List<PlayerCard> cards;
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

  /// Cards game, read from the bank row of this game. The banker flips the
  /// switch once at game start; until then, and in a game started before the
  /// flag existed, this stays false and the card buttons stay hidden.
  bool _playWithCards = false;

  /// The round advance, read from the bank row. Local prefs is a fallback
  /// while the row cannot carry it (project without
  /// shared_game_state.sql).
  double? _advanceValue;

  bool _isFetching = false; // One poll in flight at a time
  bool _isProcessingDeal = false;
  String? _bankerPlayerId;
  StreamSubscription<List<Map<String, dynamic>>>? _rosterUpdates;

  /// The game's row in `game_sessions`. It carries the rules (pay mode, cards,
  /// advance) and the lifecycle - which is how this screen learns that the
  /// banker paused or ended the game.
  GameSession? _session;
  StreamSubscription<GameSession>? _sessionUpdates;
  bool _statusDialogOpen = false;

  /// True once this device has been told it was removed, so the dialog and the
  /// trip home happen exactly once even though the roster keeps arriving.
  bool _standingHandled = false;

  /// True once the bank has been handed to this device, so the offer to open
  /// the banker table appears exactly once.
  bool _bankOfferShown = false;

  /// True when the banker paused the game, or ended it. The player can look at
  /// the table and their holdings, but nothing here may move money or property.
  bool get _viewOnly => _session?.blocksPlay ?? false;

  /// Explains, once, why an action did nothing, and reports that it was
  /// blocked. Every money-moving entry point starts with this.
  bool _guardLifecycle() {
    if (!_viewOnly) return false;
    unawaited(showMessage(
      context,
      _session?.blockedReason ??
          'The game is not running, so that cannot be done right now.',
    ));
    return true;
  }

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

  @override
  void initState() {
    super.initState();
    value = widget.bankValue;
    fetchCurrentPlayerName();
    _refreshRoster(); // Initial load
    _subscribeToRoster(); // Live updates
    _subscribeToSession(); // Live suspend / resume / end
    _loadSession(); // First read, before the socket connects
    startPolling(); // Reconciliation, in case Realtime is unavailable
    setAvatar();
    // The board this game is played on, before anything reads a card name.
    BoardCatalog.useForGame(widget.gameId);
  }

  @override
  void dispose() {
    _rosterUpdates?.cancel();
    _sessionUpdates?.cancel();
    pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSession() async {
    final GameSession? session = await GameSession.fetch(widget.gameId);
    if (session != null) {
      BoardCatalog.use(session.boardId);
      _applySession(session);
    }
  }

  /// Leaves the game because the banker removed this player.
  ///
  /// The roster row stays (that is the badge); this device just has nothing
  /// left to do here, so it says why and goes home rather than leaving a dead
  /// screen that looks like a bug.
  void _checkMyStanding(List<Map<String, dynamic>> rows) {
    if (_standingHandled) return;
    final String? me = playerID;
    if (me == null || me.isEmpty) return;
    for (final Map<String, dynamic> row in rows) {
      if (row['player_id']?.toString() != me) continue;
      if (PlayerStanding.fromRow(row) != PlayerStanding.kicked) continue;
      _standingHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _leaveAsRemoved());
      return;
    }
  }

  Future<void> _leaveAsRemoved() async {
    if (!mounted) return;
    await showAppDialog<void>(
      context,
      title: 'Removed from the game',
      icon: Icons.person_remove_alt_1,
      accent: const Color(0xFFC62828),
      barrierDismissible: false,
      message: 'The banker removed you from this game. Your cash went to the '
          'bank and your cards went back on the market, so this device no '
          'longer has a seat at the table.',
      actions: <Widget>[
        AppDialogButton(
          label: 'Back to home',
          primary: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
    if (!mounted) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('gameID');
    if (!mounted) return;
    context.go(AppRoutes.home);
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

  void _applySession(GameSession session) {
    if (!mounted || session.gameId != widget.gameId) return;
    final bool rulesChanged = _playWithCards != session.playWithCards ||
        _advanceValue != session.advanceValue ||
        payOption != session.paymentOption;
    final String? previousStatus = _session?.status;
    final String previousBanker = _session?.bankerId ?? '';
    setState(() {
      _session = session;
      _playWithCards = session.playWithCards;
      _advanceValue = session.advanceValue;
      payOption = session.paymentOption;
    });
    if (rulesChanged) setState(() {});

    // Only a change that happens while the table is open is announced. A game
    // that was already paused or ended when it was opened is explained by the
    // banner and nothing else, so returning to look at an old table does not
    // start with a dialog.
    if (previousStatus != null && previousStatus != session.status) {
      if (session.isSuspended) {
        _showGameStatusDialog(suspended: true);
      } else if (session.isEnded) {
        _showGameStatusDialog(suspended: false);
      } else if (_statusDialogOpen) {
        // The banker resumed while the player was reading the pause dialog.
        Navigator.of(context).maybePop();
      }
    }

    // The bank has just been handed to this device: its seat now holds the bank
    // row, so offer the banker's table instead of leaving it with a player's
    // view of a game it runs.
    final String? me = playerID;
    if (me != null &&
        me.isNotEmpty &&
        previousBanker != me &&
        session.bankerId == me) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _offerBankRole(session));
    }
  }

  /// This device has become the banker by hand-over. Staying here is allowed -
  /// it is still a seat at the table - but the controls it now has live on the
  /// banker's screen.
  Future<void> _offerBankRole(GameSession session) async {
    if (_bankOfferShown || !mounted) return;
    _bankOfferShown = true;

    final bool open = await showAppConfirm(
      context,
      title: 'You are the banker',
      icon: Icons.account_balance,
      confirmLabel: 'Open banker table',
      cancelLabel: 'Stay here',
      message: 'The bank has been handed to you, so this device now pays, '
          'advances, pauses and ends the game. The balance is unchanged.',
    );
    if (!open || !mounted) return;

    context.pushReplacement(AppRoutes.banker(widget.gameId));
  }

  /// The banker paused (or ended) the game. A paused game is resumable and
  /// continues exactly where it stopped, so this is a message and a way out,
  /// not an error - and it is not dismissible: the player either stays to look
  /// at the board or goes back to the title screen.
  Future<void> _showGameStatusDialog({required bool suspended}) async {
    final GameSession? session = _session;
    if (_statusDialogOpen || !mounted || session == null) return;
    if (session.isSuspended != suspended) return;
    _statusDialogOpen = true;
    await showGameStatusDialog(
      context,
      session: session,
      onReturnToTitle: _returnToTitle,
    );
    _statusDialogOpen = false;
  }

  /// Leaves the table for the title screen. The game itself is untouched: a
  /// pause can still be resumed, and an ended game is still in Your Games to
  /// look at.
  ///
  /// `pushReplacement` so the browser's back button does not reopen the table
  /// this button just closed.
  Future<void> _returnToTitle() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('gameID');
    if (!mounted) return;
    context.pushReplacement(AppRoutes.home);
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
      // The bank row comes along too, because it carries the cards flag.
      final response = await Supabase.instance.client
          .from('players_test')
          .select()
          .eq('game_id', widget.gameId);

      _applyRosterRows(
          (response as List<dynamic>).cast<Map<String, dynamic>>());
      unawaited(_loadSession());
      unawaited(_checkDeals());
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

    // A removed player keeps their row: the badge next to the name is how the
    // table sees what happened. They sort to the bottom, under the live players.
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

    // Before the list is drawn: if this device is the one that was removed, it
    // has to leave rather than keep a seat it no longer has.
    _checkMyStanding(rows);

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

    // The rules of the game come from `game_sessions` (see _applySession).
    // The bank row is only needed here for the banker's id: a trade that
    // touches a mortgaged card owes the bank 10% interest, and only the id can
    // route it. On a project without the session table the bank row still
    // carries the old copies of the rules, so they are read as a fallback.
    bool legacyCards = _playWithCards;
    double? legacyAdvance = _advanceValue;
    for (final Map<String, dynamic> row in rows) {
      if (row['role'] == 'banker') {
        final String? bankId = row['player_id']?.toString();
        if (bankId != null && bankId.isNotEmpty) {
          _bankerPlayerId = bankId;
          Deals.rememberBankId(bankId);
        }
        if (_session == null) {
          if (row['play_with_cards'] is bool) {
            legacyCards = row['play_with_cards'] == true;
          }
          if (row['advance_value'] is num) {
            legacyAdvance = (row['advance_value'] as num).toDouble();
          }
        }
        break;
      }
    }
    if (_session == null &&
        (legacyCards != _playWithCards || legacyAdvance != _advanceValue)) {
      setState(() {
        _playWithCards = legacyCards;
        _advanceValue = legacyAdvance;
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

    // Keep the QR mirror (role / display_name) in step with the row, so a
    // banker who renames a player does not leave this device sending a QR
    // with the old name. One cheap read and only one write when it changed.
    _syncQrMirror(name);

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

  /// Keeps `display_name` and `role` in prefs in step with the roster row.
  /// receive.dart reads them to build a QR; without this a rename on the
  /// bank's screen never reaches the player's QR.
  Future<void> _syncQrMirror(String? liveName) async {
    if (liveName == null || liveName.isEmpty) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getString('display_name') == liveName &&
        prefs.getString('role') == 'player') {
      return;
    }
    await prefs.setString('display_name', liveName);
    await prefs.setString('role', 'player');
  }

  Future<void> fetchCurrentPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gameID', widget.gameId);

    // role / display_name are a local mirror of the roster row so
    // receive.dart can build a QR without a database read. They are
    // refreshed from the live roster in _applyMyPlayer below; this method
    // only seeds them, so a device that has just opened the game has
    // something to send before the first tick lands.
    final profileName = prefs.getString('profile_name');
    await prefs.setString('role', 'player');
    if (!prefs.containsKey('display_name') ||
        prefs.getString('display_name')!.isEmpty) {
      await prefs.setString('display_name', profileName ?? 'Player');
    }

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

  /// The board as a reference, opened from the app bar: an owned tile carries
  /// its owner's name, and its deed carries the owner in place of any action.
  void _showBoard() {
    showDialog<void>(
      context: context,
      builder: (_) => BankpopBoardPopup(gameId: widget.gameId),
    );
  }

  /// A yes/no confirmation with the Bankpop style. Used before a deal is
  /// committed so a single tap cannot mortgage a card by accident.
  Future<bool> _confirm(String title, String message, String action) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Live trades addressed to this player. Polled on every reconciliation tick;
  /// trades are between players, so mortgage requests never show up here.
  Future<void> _checkDeals() async {
    if (_viewOnly) return;
    if (_isProcessingDeal) return;
    final String? id = playerID;
    if (id == null || id.isEmpty) return;
    _isProcessingDeal = true;
    try {
      final List<DealRequest> deals = await Deals.pendingFor(widget.gameId, id);
      if (deals.isEmpty || !mounted) return;

      final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
      if (!mounted) return;

      for (final DealRequest deal in deals) {
        if (!deal.isTrade) continue;
        await _showTradeOffer(deal, spaces);
        if (!mounted) return;
        break; // one dialog per tick
      }
    } catch (error) {
      debugPrint('Could not check deals: $error');
    } finally {
      _isProcessingDeal = false;
    }
  }

  Future<void> _showTradeOffer(
    DealRequest deal,
    Map<int, BankpopSpace> spaces,
  ) async {
    String? autoClosed;
    Timer? poll;
    final String? result = await showDialog<String>(
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
          backgroundColor: const Color(0xFFFFF8E1),
          title: Text('Trade from ${deal.fromName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (deal.cards.isNotEmpty) ...<Widget>[
                  const Text('They give:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final int i in deal.cards)
                    Text('  - ${spaces[i]?.name ?? 'Card #$i'}'),
                ],
                if (deal.offerCash > 0)
                  Text('  - \u00a3${deal.offerCash.toStringAsFixed(0)} cash'),
                if (deal.wants.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  const Text('They want:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final int i in deal.wants)
                    Text('  - ${spaces[i]?.name ?? 'Card #$i'}'),
                ],
                if (deal.wantsCash > 0)
                  Text('  - \u00a3${deal.wantsCash.toStringAsFixed(0)} cash'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop('reject');
              },
              child: const Text('Reject'),
            ),
            TextButton(
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop('counter');
              },
              child: const Text('Counter'),
            ),
            TextButton(
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop('accept');
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
    poll?.cancel();
    if (!mounted) return;
    if (autoClosed != null) {
      await showMessage(
        context,
        autoClosed == 'cancelled'
            ? '${deal.fromName} cancelled this trade.'
            : 'This trade was already settled.',
        title: autoClosed == 'cancelled' ? 'Cancelled' : 'Already settled',
      );
      return;
    }

    if (result == 'accept') {
      final DealOutcome outcome = await Deals.approve(deal);
      if (!mounted) return;
      showMessage(
        context,
        outcome.ok
            ? 'Trade with ${deal.fromName} settled'
            : 'Trade failed: ${outcome.error}',
        title: outcome.ok ? 'Trade complete' : 'Not settled',
      );
      if (outcome.ok) _refreshRoster();
    } else if (result == 'reject') {
      await Deals.decline(deal.id);
    } else if (result == 'counter') {
      // Without this the original deal stays pending and re-prompts on the
      // next reconciliation tick, sitting on top of the counter the player
      // just sent.
      await Deals.decline(deal.id);
      if (!mounted) return;
      await _openTradeBuilder(counterTo: deal);
    }
  }

  Future<void> _openTradeBuilder({DealRequest? counterTo}) async {
    if (_guardLifecycle()) return;

    final String id = playerID ?? '';
    if (id.isEmpty) return;
    final List<PlayerCard> myCards =
        await PlayerCards.forPlayer(gameId: widget.gameId, playerId: id);
    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
    final List<dynamic> roster = await Supabase.instance.client
        .from('players_test')
        .select('name, player_id')
        .eq('game_id', widget.gameId)
        .eq('role', 'player');
    if (!mounted) return;

    final SentTradeOffer? sent = await showDialog<SentTradeOffer>(
      context: context,
      builder: (_) => TradeBuilderDialog(
        gameId: widget.gameId,
        myId: id,
        myName: currentPlayerName ?? 'Player',
        myCards: myCards,
        spaces: spaces,
        players: roster.cast<Map<String, dynamic>>(),
        counterTo: counterTo,
      ),
    );
    if (sent == null || !mounted) return;

    // The offer is out there now, so the sender waits on it - with a cancel
    // button, because until the other side answers only the sender can pull it
    // back. Cancelling flips the row to `cancelled`, and the other player's
    // dialog closes itself on the next poll.
    final bool accepted = await _waitForDeal(
      dealId: sent.id,
      what: 'trade',
      title: 'Waiting for ${sent.toName}',
      body: '${sent.toName} is reviewing your offer.\n'
          'You can cancel it until they answer.',
      declinedBy: sent.toName,
    );
    if (!mounted) return;
    if (accepted) {
      await showMessage(
        context,
        '${sent.toName} accepted the trade',
        title: 'Trade complete',
      );
      if (mounted) _refreshRoster();
    }
  }

  // ---------------------------------------------------------------------
  // Mortgage / unmortgage / sell-a-building
  //
  // Every one of these writes a DealRequest addressed to the bank, then waits
  // for the banker's approve/decline. Nothing moves until the banker settles
  // it; the rules live in services/deals.dart, not here.
  // ---------------------------------------------------------------------

  Future<void> _mortgageCard({
    required BankpopSpace space,
    required PlayerCard card,
    required List<PlayerCard> myCards,
    required VoidCallback onBuilt,
  }) async {
    if (_guardLifecycle()) return;

    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) {
      if (!mounted) return;
      await showMessage(context, 'Cannot find the bank in this game');
      return;
    }
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
    final bool builtInGroup = myCards.any((PlayerCard c) {
      final BankpopSpace? s = spaces[c.cardIndex];
      return s?.color == space.color && (c.houses > 0 || c.hotels > 0);
    });
    if (!mounted) return;
    if (builtInGroup) {
      await showMessage(
        context,
        'Sell the buildings in the ${space.color} group first',
        title: 'Cannot mortgage yet',
      );
      return;
    }

    final int halfValue = (space.price ?? 0) ~/ 2;
    final bool confirmed = await _confirm(
      'Mortgage ${space.name}?',
      'The bank will pay you \u00a3$halfValue and the card stops '
          'collecting rent until you unmortgage it.',
      'Mortgage',
    );
    if (!confirmed || !mounted) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.mortgage,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted) return;
    if (dealId == null) {
      await showMessage(context, 'Could not ask to mortgage ${space.name}');
      return;
    }
    final bool approved = await _waitForDeal(dealId: dealId, what: 'mortgage');
    if (approved && mounted) {
      // Write to myCards, refresh the sheet, then close the deed one frame
      // later. Without the deferred pop the sheet's rebuild could race the
      // deed's dismissal and the mini card would stay stale.
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(mortgaged: true);
      }
      onBuilt();
      _refreshRoster();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  Future<void> _unmortgageCard({
    required PlayerCard card,
    required List<PlayerCard> myCards,
    required VoidCallback onBuilt,
  }) async {
    if (_guardLifecycle()) return;

    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) return;
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
    final int unmortgageValue = card.unmortgageCost(spaces[card.cardIndex]);
    final bool confirmed = await _confirm(
      'Unmortgage ${spaces[card.cardIndex]?.name ?? "this card"}?',
      'You will pay the bank \u00a3$unmortgageValue to clear the mortgage '
          'and start collecting rent again.',
      'Unmortgage',
    );
    if (!confirmed || !mounted) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.unmortgage,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted || dealId == null) return;
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'unmortgage');
    if (approved && mounted) {
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(mortgaged: false);
      }
      onBuilt();
      _refreshRoster();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  Future<void> _sellHouse({
    required PlayerCard card,
    required List<PlayerCard> myCards,
    required VoidCallback onBuilt,
  }) async {
    if (_guardLifecycle()) return;

    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) return;
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
    final BankpopSpace? space = spaces[card.cardIndex];
    final int refund = (space?.houseCost ?? 0) ~/ 2;
    final bool confirmed = await _confirm(
      'Sell a house on ${space?.name ?? "this card"}?',
      'The bank will pay you \u00a3$refund and one house will be removed '
          'from the card.',
      'Sell house',
    );
    if (!confirmed || !mounted) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.sellHouse,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted || dealId == null) return;
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'house sale');
    if (approved && mounted) {
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(
          houses: (myCards[idx].houses - 1).clamp(0, 4),
        );
      }
      onBuilt();
      _refreshRoster();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  Future<void> _sellHotel({
    required PlayerCard card,
    required List<PlayerCard> myCards,
    required VoidCallback onBuilt,
  }) async {
    if (_guardLifecycle()) return;

    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) return;
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
    final BankpopSpace? space = spaces[card.cardIndex];
    final int refund = (space?.hotelCost ?? 0) ~/ 2;
    final bool confirmed = await _confirm(
      'Sell the hotel on ${space?.name ?? "this card"}?',
      'The bank will pay you \u00a3$refund and the hotel will be removed '
          'from the card.',
      'Sell hotel',
    );
    if (!confirmed || !mounted) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.sellHotel,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted || dealId == null) return;
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'hotel sale');
    if (approved && mounted) {
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(hotels: 0);
      }
      onBuilt();
      _refreshRoster();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  /// Waits out a bank deal. Same shape as `_waitForApproval` for buildings, but
  /// polls `Deals.statusOf` instead of `CardRequests.statusOf`.
  Future<bool> _waitForDeal({
    required int dealId,
    required String what,
    String title = 'Waiting for the banker',
    String? body,
    String declinedBy = 'The banker',
  }) async {
    if (!mounted) return false;
    String? outcome;
    Timer? poll;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        poll = Timer.periodic(const Duration(seconds: 2), (Timer _) async {
          final String? status = await Deals.statusOf(dealId);
          if (!dialogContext.mounted || status == null) return;
          if (status == 'pending') return;
          outcome = status;
          Navigator.of(dialogContext).pop();
        });
        return AlertDialog(
          backgroundColor: const Color(0xFFFFF8E1),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(color: Color(0xFF689F38)),
              const SizedBox(height: 14),
              Text(body ?? 'The banker is reviewing your $what.'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                outcome = 'cancelled';
                Deals.cancel(dealId);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel request'),
            ),
          ],
        );
      },
    );
    poll?.cancel();
    if (!mounted) return false;
    if (outcome == 'approved') return true;
    if (outcome == 'rejected') {
      await showMessage(
        context,
        '$declinedBy turned down your $what.',
        title: 'Not approved',
      );
    }
    return false;
  }

  /// The properties this player has bought, newest first.
  ///
  /// The table stores the board index, so the name and group colour are looked
  /// up from the bundled board - that keeps a card readable even if the row was
  /// written on another device.
  Future<void> _showMyCards() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String id = playerID ?? prefs.getString('playerID') ?? '';
    if (id.isEmpty) return;

    if (!mounted) return;

    final List<PlayerCard> cards;
    try {
      cards = await PlayerCards.forPlayer(gameId: widget.gameId, playerId: id);
    } catch (error) {
      debugPrint('Could not load cards: $error');
      if (!mounted) return;
      showMessage(context, 'Could not load your cards');
      return;
    }
    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
    if (!mounted) return;

    // The sheet keeps its own mutable copy so a house that has just been
    // approved changes the mini card's rent in place, without reopening.
    final List<PlayerCard> mine = List<PlayerCard>.of(cards);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.yellow.shade50,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context,
              void Function(void Function()) setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              builder: (BuildContext context, ScrollController controller) {
                final List<_CardGroup> groups = _groupCards(mine, spaces);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
                      child: Row(
                        children: [
                          Text(
                            'My Cards',
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF689F38),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: groups.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'You do not own any cards yet.\nThe bank '
                                  'sells properties during the game.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15.sp,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            )
                          : ListView(
                              controller: controller,
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              children: <Widget>[
                                for (final _CardGroup group in groups) ...[
                                  _groupHeader(group),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: <Widget>[
                                      for (final PlayerCard card in group.cards)
                                        _miniCard(
                                          card: card,
                                          space: spaces[card.cardIndex]!,
                                          myCards: mine,
                                          setSheetState: setSheetState,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                ],
                              ],
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// The player's cards, laid out by colour group: a mini card each, showing the
  /// name and the rent that is due on it right now.
  static List<_CardGroup> _groupCards(
    List<PlayerCard> mine,
    Map<int, BankpopSpace> spaces,
  ) {
    final Map<String?, List<PlayerCard>> byColour =
        <String?, List<PlayerCard>>{};
    final Map<String?, int> order = <String?, int>{};

    // Board order, so the groups come out as they do on the board itself.
    final List<BankpopSpace> ordered = spaces.values.toList()
      ..sort((BankpopSpace a, BankpopSpace b) => a.index.compareTo(b.index));
    final Map<int, PlayerCard> mineByIndex = <int, PlayerCard>{
      for (final PlayerCard card in mine) card.cardIndex: card,
    };

    for (final BankpopSpace space in ordered) {
      final PlayerCard? card = mineByIndex[space.index];
      if (card == null) continue;
      final String? colour = space.color;
      order[colour] = order.length;
      (byColour[colour] ??= <PlayerCard>[]).add(card);
    }

    final List<_CardGroup> groups = <_CardGroup>[];
    byColour.forEach((String? colour, List<PlayerCard> cards) {
      groups.add(_CardGroup(colour, cards));
    });
    groups.sort((a, b) => order[a.colour]!.compareTo(order[b.colour]!));
    return groups;
  }

  /// The colour header above one group, so a set reads as a set.
  Widget _groupHeader(_CardGroup group) {
    final String? colour = group.colour;
    final String label = (colour == null || colour.isEmpty)
        ? 'Other'
        : colour[0].toUpperCase() + colour.substring(1);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(BankpopBoard.colorForGroup(colour)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF33691E),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${group.cards.length}',
            style: TextStyle(fontSize: 12.sp, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  /// The mini card in the sheet: name, what is built on it, and the rent it
  /// currently pays. Tapping opens the full deed for that card.
  Widget _miniCard({
    required PlayerCard card,
    required BankpopSpace space,
    required List<PlayerCard> myCards,
    required void Function(void Function()) setSheetState,
  }) {
    final Color groupColor = Color(BankpopBoard.colorForGroup(space.color));

    return SizedBox(
      width: 154,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openCardDetail(
          space: space,
          card: card,
          myCards: myCards,
          onBuilt: () => setSheetState(() {}),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: groupColor, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                space.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (card.mortgaged)
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'M',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else if (card.hasHotel)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.shade700,
                      ),
                    )
                  else
                    for (int i = 0; i < card.houses; i++)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.shade800,
                        ),
                      ),
                  const Spacer(),
                  Text(
                    'Rent £${_currentRent(space, card)}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF33691E),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The rent this card is due right now: base rent while it is bare, the house
  /// level while it has 1-4, and the hotel line once it has one.
  static int _currentRent(BankpopSpace space, PlayerCard card) {
    final List<int>? rent = space.rent;
    if (rent == null || rent.isEmpty) return 0;
    if (card.hasHotel) return rent[rent.length > 5 ? 5 : rent.length - 1];
    if (card.houses > 0) {
      return rent[card.houses.clamp(0, rent.length - 1)];
    }
    return rent[0];
  }

  /// Opens the full deed for one of this player's cards, with what is built on
  /// it and a plus beside the level that could be bought next.
  ///
  /// The deed holds its own counts, so an approval turns that plus into a tick in
  /// place; this closes the loop with the sheet as well, so the mini card shows
  /// the new rent without being reopened.
  Future<void> _openCardDetail({
    required BankpopSpace space,
    required PlayerCard card,
    required List<PlayerCard> myCards,
    required VoidCallback onBuilt,
  }) async {
    final int index =
        myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
    final PlayerCard live = index == -1 ? card : myCards[index];

    await showBankpopSpaceCard(
      context,
      space,
      actionWidget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CardOwnerBadge(
            owner: CardOwner(
              name: live.to,
              playerId: playerID,
              houses: live.houses,
              hotels: live.hotels,
              mortgaged: live.mortgaged,
            ),
          ),
          if (!_viewOnly) const SizedBox(height: 6),
          if (!_viewOnly)
            _CardManageBar(
              card: live,
              onMortgage: () => _mortgageCard(
                space: space,
                card: live,
                myCards: myCards,
                onBuilt: onBuilt,
              ),
              onUnmortgage: () => _unmortgageCard(
                card: live,
                myCards: myCards,
                onBuilt: onBuilt,
              ),
              onSellHouse: () =>
                  _sellHouse(card: live, myCards: myCards, onBuilt: onBuilt),
              onSellHotel: () =>
                  _sellHotel(card: live, myCards: myCards, onBuilt: onBuilt),
            ),
        ],
      ),
      houses: live.houses,
      hotels: live.hotels,
      onBuild: _viewOnly
          ? null
          : (int step) async {
              final int idx = myCards
                  .indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
              final PlayerCard liveCard = idx == -1 ? card : myCards[idx];
              final bool approved = await _buyBuilding(
                space: space,
                card: liveCard,
                myCards: myCards,
                step: step,
              );
              if (!approved || idx == -1) return approved;
              myCards[idx] = liveCard.copyWith(
                houses: step >= 5 ? liveCard.houses : liveCard.houses + 1,
                hotels: step >= 5 ? 1 : liveCard.hotels,
              );
              onBuilt();
              return true;
            },
    );
  }

  /// One step of building: the rules, the ask, then the wait for the banker.
  ///
  /// Returns true only when the banker has approved, which is the only outcome
  /// that puts a house up. Anything else is a dialog saying why, never a charge.
  Future<bool> _buyBuilding({
    required BankpopSpace space,
    required PlayerCard card,
    required List<PlayerCard> myCards,
    required int step,
  }) async {
    if (_guardLifecycle()) return false;

    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(widget.gameId);
    final List<BankpopSpace> set = spaces.values
        .where((BankpopSpace s) => s.color == space.color)
        .toList();

    // Full set, even build, hotel last: the rules live in BuildingRules so they
    // are the same everywhere and can be tested on their own.
    final BuildingDecision decision = BuildingRules.next(
      space: space,
      set: set,
      ownedCards: myCards.map((PlayerCard c) => c.cardIndex).toSet(),
      houses: card.houses,
      hotels: card.hotels,
      housesByCard: <int, int>{
        for (final PlayerCard c in myCards) c.cardIndex: c.houses,
      },
    );
    final BuildingKind wanted =
        step >= 5 ? BuildingKind.hotel : BuildingKind.house;
    if (!mounted) return false;
    if (!decision.allowed || decision.kind != wanted) {
      await showMessage(
        context,
        decision.reason ??
            'Build evenly: every card in the set has to be level before the '
                'next house.',
        title: 'Cannot build yet',
      );
      return false;
    }

    final String id = playerID ??
        (await SharedPreferences.getInstance()).getString('playerID') ??
        '';
    if (id.isEmpty) {
      if (!mounted) return false;
      await showMessage(context, 'This device has no player id');
      return false;
    }

    final AskOutcome asked = await CardRequests.ask(
      gameId: widget.gameId,
      cardIndex: card.cardIndex,
      playerId: id,
      playerName: card.to,
      kind: wanted == BuildingKind.hotel ? 'hotel' : 'house',
      amount: decision.price.toDouble(),
    );
    if (!mounted) return false;
    if (!asked.sent) {
      await showMessage(
        context,
        switch (asked.result) {
          AskResult.waiting =>
            'That card already has a request waiting for the banker.',
          AskResult.failed =>
            'Could not send the request. Has supabase/buildings.sql been run?',
          AskResult.sent => 'Could not send the request.',
        },
        title: 'Request not sent',
      );
      return false;
    }

    return _waitForApproval(
      requestId: asked.requestId!,
      what: wanted == BuildingKind.hotel ? 'hotel' : 'house',
      where: space.name,
    );
  }

  /// Sits with the request until the banker settles it. Closes itself on success;
  /// cancelling takes the request back, and a refusal comes back as a dialog.
  Future<bool> _waitForApproval({
    required int requestId,
    required String what,
    required String where,
  }) async {
    if (!mounted) return false;

    String? outcome; // 'approved' | 'rejected' | 'cancelled'
    Timer? poll;

    await showDialog<void>(
      context: context,
      // A request is waiting on an answer either way; dismissing would only bring
      // the same dialog back on the next poll.
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        poll = Timer.periodic(const Duration(seconds: 2), (Timer _) async {
          final String? status = await CardRequests.statusOf(requestId);
          if (!dialogContext.mounted || status == null) return;
          if (status == 'pending') return;
          outcome = status;
          Navigator.of(dialogContext).pop();
        });
        return AlertDialog(
          backgroundColor: const Color(0xFFFFF8E1),
          title: const Text('Waiting for the banker'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(color: Color(0xFF689F38)),
              const SizedBox(height: 14),
              Text(
                'The banker is approving your $what on $where.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                outcome = 'cancelled';
                CardRequests.cancel(requestId);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel request'),
            ),
          ],
        );
      },
    );
    poll?.cancel();
    if (!mounted) return false;

    if (outcome == 'approved') return true;
    if (outcome == 'rejected') {
      await showMessage(
        context,
        'The banker turned down the $what on $where.',
        title: 'Not approved',
      );
    }
    return false;
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

  /// Moves money from this device to [toId] and writes the ledger row.
  ///
  /// Returns null when the money moved, or the sentence to show when it did
  /// not. [WalletTransfer.pay] is one atomic call, so two payments landing at
  /// the same moment cannot both spend the same balance.
  Future<String?> _moveMoney({
    required String fromId,
    required String toId,
    required String toRole,
    required String toName,
    required double amount,
  }) async {
    final TransferOutcome transfer = await WalletTransfer.pay(
      gameId: widget.gameId,
      fromId: fromId,
      fromRole: WalletTransfer.playerRole,
      toId: toId,
      toRole: toRole,
      amount: amount,
    );
    if (!transfer.ok) {
      return transfer.failure == TransferFailure.insufficientFunds
          ? 'Insufficient balance'
          : 'The payment did not go through - try again';
    }

    try {
      await Supabase.instance.client.from('transactions').insert({
        'game_id': widget.gameId,
        'value': amount,
        'from': currentPlayerName,
        'to': toName,
        'code': '${fromId}_$toId',
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': DateFormat('HH:mm:ss').format(DateTime.now()),
      });
    } catch (error) {
      // The money has already moved; this row is the history of it.
      debugPrint('Could not record the payment: $error');
    }
    return null;
  }

  /// Pays another player at the table.
  Future<void> payPlayer(Player player) async {
    if (_guardLifecycle()) return;

    final String id = playerID ??
        (await SharedPreferences.getInstance()).getString('playerID') ??
        '';
    if (id.isEmpty) {
      if (!mounted) return;
      await showMessage(context, 'This device has no player id');
      return;
    }

    final bool paid = await showAmountKeypad(
      context,
      title: 'Pay ${player.name}',
      payee: player.name,
      holderName: _cardName,
      cardDigits: _cardDigits,
      onPay: (double amount) => _moveMoney(
        fromId: id,
        toId: player.playerID,
        toRole: WalletTransfer.playerRole,
        toName: player.name,
        amount: amount,
      ),
    );
    if (!paid || !mounted) return;
    _refreshRoster();
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
          if (payOption != 'ScanPay' && !player.standing.isGone && !_viewOnly)
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
    return showAppConfirm(
      context,
      title: 'Leave game?',
      icon: Icons.logout,
      confirmLabel: 'Leave game',
      cancelLabel: 'Stay',
      destructive: true,
      message: 'The game keeps going without you. Your balance and your cards '
          'stay on the board, so you can come back to the same game by joining '
          'with the same Game ID.',
    );
  }

  /// Pays the bank: the stake, a fine, or anything else the rules hand it.
  Future<void> payBank() async {
    if (_guardLifecycle()) return;

    final String id = playerID ??
        (await SharedPreferences.getInstance()).getString('playerID') ??
        '';
    if (id.isEmpty) {
      if (!mounted) return;
      await showMessage(context, 'This device has no player id');
      return;
    }

    final Map<String, dynamic>? bankRow = await Supabase.instance.client
        .from('players_test')
        .select('player_id, name')
        .eq('game_id', widget.gameId)
        .eq('role', WalletTransfer.bankerRole)
        .maybeSingle();
    if (!mounted) return;
    if (bankRow == null || bankRow['player_id'] == null) {
      await showMessage(context, 'Cannot find the bank in this game');
      return;
    }
    final String bankName = bankRow['name']?.toString() ?? 'the bank';

    final bool paid = await showAmountKeypad(
      context,
      title: 'Pay the bank',
      payee: bankName,
      holderName: _cardName,
      cardDigits: _cardDigits,
      onPay: (double amount) => _moveMoney(
        fromId: id,
        toId: bankRow['player_id'].toString(),
        toRole: WalletTransfer.bankerRole,
        toName: bankName,
        amount: amount,
      ),
    );
    if (!paid || !mounted) return;
    _refreshRoster();
  }

  /// A ScanPay game has one scanner: it reads a player's pay QR and the bank's
  /// card QR alike, so paying and buying are the same button. An InstantPay
  /// game has no QR at all, so its action pays the bank directly. The icon and
  /// the legend sentence follow the mode.
  GameControl get _payControl =>
      payOption == 'ScanPay' ? GameControls.scan : GameControls.payBank;

  /// Exactly the icons this screen is showing, so the info sheet never explains
  /// a button that is not there.
  List<GameControl> get _screenControls => <GameControl>[
        GameControls.history,
        if (_playWithCards) GameControls.board,
        GameControls.leave,
        if (payOption == 'ScanPay') GameControls.receive,
        GameControls.myCards,
        if (_playWithCards) GameControls.trade,
        _payControl,
      ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // Intercept the back press and show the confirmation instead.
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool shouldLeave = await _onWillPop();
        // A game screen can be the only route (Continue game replaces the
        // title screen), so popping it would leave an empty navigator. Going
        // back to the title screen is the same place from either route.
        if (shouldLeave && mounted) await _returnToTitle();
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
          // Icon-only, in the same sticker style as the actions under the
          // wallet. Each one keeps its name in a tooltip, and the info button
          // lists them all for a first-time player.
          actions: [
            Row(
              children: <Widget>[
                GameIconButton(
                  control: GameControls.history,
                  size: 36,
                  onPressed: () => context.push(
                    AppRoutes.history(
                      widget.gameId,
                      playerId: playerID ?? '-',
                    ),
                  ),
                ),
                if (_playWithCards) const SizedBox(width: 4),
                // The board itself, to check who owns what. A tap only opens a
                // deed, and only a cards game has anything to look at.
                if (_playWithCards)
                  GameIconButton(
                    control: GameControls.board,
                    size: 36,
                    onPressed: _showBoard,
                  ),
                const SizedBox(width: 4),
                GameIconButton(
                  control: GameControls.leave,
                  size: 36,
                  onPressed: () async {
                    final bool shouldLeave = await _onWillPop();
                    if (!shouldLeave) return;
                    final SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    await prefs.remove('gameID');
                    if (!mounted) return;
                    context.pushReplacement(AppRoutes.home);
                  },
                ),
                const SizedBox(width: 4),
                GameInfoButton(
                  title: 'Player controls',
                  controls: _screenControls,
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        // playerID comes from local prefs, so this gate clears within a frame or
        // two; it just keeps the card from being built before it exists.
        body: isLoading || playerID == null
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF689F38)),
              )
            : Column(
                children: <Widget>[
                  // Paused or ended: the band explains why the pay, trade and
                  // building controls are gone, and who can lift the pause.
                  if (_session != null && _session!.blocksPlay)
                    GameStatusBanner(
                      session: _session!,
                      onDetails: () => _showGameStatusDialog(
                        suspended: _session!.isSuspended,
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
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
                                        cacheWidth:
                                            160, // see the note on the other two
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Row for Cardholder's Name and Card Number
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              // Expanded so the number shrinks instead of
                                              // pushing the position Lottie off a narrow
                                              // phone's card.
                                              Expanded(
                                                child: Column(
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
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.white,
                                                          ),
                                                        )
                                                      ],
                                                    ),
                                                    const SizedBox(height: 5),
                                                    // Dummy credit card number
                                                    FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      child: Text(
                                                        '**** **** **** ${_cardDigits.substring(0, 4)}', // First 4 digits of this device's id
                                                        style: TextStyle(
                                                          fontSize: 22.sp,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.blueGrey
                                                              .shade100,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Lottie.asset(
                                                positionStatus == "first"
                                                    ? 'assets/lottie/first.json'
                                                    : positionStatus == "second"
                                                        ? 'assets/lottie/second.json'
                                                        : positionStatus ==
                                                                "almostlast"
                                                            ? 'assets/lottie/almost_last.json'
                                                            : positionStatus ==
                                                                    "last"
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
                                              Expanded(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: AnimatedFlipCounter(
                                                    value: value,
                                                    fractionDigits: 2,
                                                    textStyle: TextStyle(
                                                      fontSize: 28.sp,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.9),
                                                    ),
                                                    duration: const Duration(
                                                        milliseconds: 500),
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10.0),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
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
                                                        const SizedBox(
                                                            height: 5),
                                                        Text(
                                                          DateFormat('MM/yy')
                                                              .format(DateTime
                                                                  .now()),
                                                          style: TextStyle(
                                                            fontSize: 16.sp,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors
                                                                .blueGrey
                                                                .shade100,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(width: 20),
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
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
                                                        const SizedBox(
                                                            height: 5),
                                                        Text(
                                                          _cardDigits.substring(
                                                              _cardDigits
                                                                      .length -
                                                                  3), // Dummy CVV
                                                          style: TextStyle(
                                                            fontSize: 16.sp,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors
                                                                .blueGrey
                                                                .shade100,
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
                                // Three buttons no longer fit on one line on a narrow
                                // phone, so they wrap instead of overflowing.
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 10,
                                  runSpacing: 6,
                                  children: [
                                    if (payOption == 'ScanPay' && !_viewOnly)
                                      const ReceiveButton(),
                                    // Always available: a player should be able to look
                                    // at what they hold, cards game or not.
                                    GameIconButton(
                                      control: GameControls.myCards,
                                      onPressed: _showMyCards,
                                    ),
                                    if (_playWithCards && !_viewOnly)
                                      GameIconButton(
                                        control: GameControls.trade,
                                        onPressed: _openTradeBuilder,
                                      ),
                                    if (!_viewOnly)
                                      GameIconButton(
                                        control: _payControl,
                                        onPressed: () {
                                          if (payOption == 'ScanPay') {
                                            context.push(
                                              AppRoutes.scanPay(widget.gameId),
                                            );
                                          } else {
                                            payBank();
                                          }
                                        },
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
                ],
              ),
      ),
    );
  }
}

/// The manage bar shown in a deed opened from the player's own hand: mortgage,
/// unmortgage, sell a house, or sell a hotel, each subject to the bank's
/// approval (see the rules in `services/deals.dart`).
class _CardManageBar extends StatelessWidget {
  const _CardManageBar({
    required this.card,
    required this.onMortgage,
    required this.onUnmortgage,
    required this.onSellHouse,
    required this.onSellHotel,
  });

  final PlayerCard card;
  final Future<void> Function() onMortgage;
  final Future<void> Function() onUnmortgage;
  final Future<void> Function() onSellHouse;
  final Future<void> Function() onSellHotel;

  @override
  Widget build(BuildContext context) {
    final bool canMortgage =
        !card.mortgaged && card.houses == 0 && card.hotels == 0;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: <Widget>[
        if (canMortgage) _chip('Mortgage', const Color(0xFF616161), onMortgage),
        if (card.mortgaged)
          _chip('Unmortgage', const Color(0xFF2E7D32), onUnmortgage),
        if (card.houses > 0 && !card.hasHotel)
          _chip('Sell house', const Color(0xFFE65100), onSellHouse),
        if (card.hasHotel)
          _chip('Sell hotel', const Color(0xFFB71C1C), onSellHotel),
      ],
    );
  }

  Widget _chip(String label, Color colour, Future<void> Function() onTap) {
    return SizedBox(
      height: 24,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: colour,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10)),
      ),
    );
  }
}
