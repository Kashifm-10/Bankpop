import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:mon/services/bank_handover.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One game this account played, with the thing it needs to offer next.
class _GameEntry {
  _GameEntry({
    required this.gameId,
    required this.role,
    required this.name,
    this.session,
  });

  final String gameId;

  /// 'banker' or 'player' - this account's role in this game.
  final String role;

  /// The name used in that game (a player may have been renamed since).
  final String name;

  /// Null for a game started before game_sessions.sql was applied. The card
  /// still lists it, treating it as playable, which is what the app did before
  /// sessions existed.
  final GameSession? session;

  bool get isBanker => role == 'banker';

  /// The banker who handed the bank over keeps a viewing seat, so the game
  /// still shows up here - with the role they have now, not the one they had.
  bool get isExBanker => role == BankHandover.exBankerRole;
  String get status => session?.status ?? GameSession.active;
  DateTime? get startedAt => session?.startedAt;
  DateTime? get endedAt => session?.endedAt;
}

/// The account's games, newest first.
///
/// A game row itself already knows the role (`players_test.role`); the status
/// and the dates come from `game_sessions`. Together they answer the two things
/// a returning player asks: "which game was I in?" and "can I go back in?".
class GameHistoryScreen extends StatefulWidget {
  const GameHistoryScreen({super.key});

  @override
  State<GameHistoryScreen> createState() => _GameHistoryScreenState();
}

class _GameHistoryScreenState extends State<GameHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<_GameEntry> _games = <_GameEntry>[];

  /// A guest's games are only reachable from this device, so the list carries
  /// the same reminder the home screen does.
  bool _signedIn = true;

  static final DateFormat _dateFormat = DateFormat('d MMM yyyy, h:mm a');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool signedIn = await Account.isSignedIn();
    if (mounted) setState(() => _signedIn = signedIn);
    final String? playerId = prefs.getString('playerID');
    if (playerId == null || playerId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('players_test')
          .select('game_id, role, name')
          .eq('player_id', playerId);

      // One entry per game. A device can hold a banker row and a player row in
      // the same game (it also joined); the banker role wins because that is
      // the stronger capability.
      final Map<String, Map<String, dynamic>> byGame =
          <String, Map<String, dynamic>>{};
      for (final dynamic raw in rows) {
        final Map<String, dynamic> row = (raw as Map).cast<String, dynamic>();
        final String? gameId = row['game_id']?.toString();
        if (gameId == null || gameId.isEmpty) continue;
        final Map<String, dynamic>? existing = byGame[gameId];
        if (existing == null ||
            (row['role'] == 'banker' && existing['role'] != 'banker')) {
          byGame[gameId] = row;
        }
      }

      final List<String> ids = byGame.keys.toList();
      final Map<String, GameSession> sessions = <String, GameSession>{};
      if (ids.isNotEmpty) {
        final List<dynamic> sessionRows = await Supabase.instance.client
            .from('game_sessions')
            .select()
            .inFilter('game_id', ids);
        for (final dynamic raw in sessionRows) {
          final GameSession? session =
              GameSession.fromRow((raw as Map).cast<String, dynamic>());
          if (session != null) sessions[session.gameId] = session;
        }
      }

      final List<_GameEntry> entries = byGame.entries.map((entry) {
        final Map<String, dynamic> row = entry.value;
        return _GameEntry(
          gameId: entry.key,
          role: row['role']?.toString() ?? 'player',
          name: row['name']?.toString() ?? '',
          session: sessions[entry.key],
        );
      }).toList()
        ..sort((a, b) {
          final DateTime? left = a.startedAt;
          final DateTime? right = b.startedAt;
          if (left == null && right == null) return 0;
          if (left == null) return 1;
          if (right == null) return -1;
          return right.compareTo(left);
        });

      if (!mounted) return;
      setState(() {
        _games = entries;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      debugPrint('Could not load the games: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your games. Pull to refresh to try again.';
      });
    }
  }

  /// Opens a game. A running game is entered to play it; a paused or an ended
  /// one is opened to look at it - both screens read the lifecycle themselves
  /// and hide every control that would move money or property.
  ///
  /// The banker tapping a paused game resumes it for everyone, because the
  /// banker is the only one who can lift the pause.
  Future<void> _open(_GameEntry entry) async {
    // Every game opens the same way: a running one to play, a paused or ended
    // one to look at. The screens read the lifecycle themselves, so a paused
    // table shows its banner and disables its buttons instead of being resumed
    // from here; the banker resumes it from that banner.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('gameID', entry.gameId);
    if (!mounted) return;

    // The address carries the game and the role, so a refresh on the table
    // keeps it open and the back button returns to this list.
    context.push(
      entry.isBanker
          ? AppRoutes.banker(entry.gameId)
          : AppRoutes.player(entry.gameId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Your Games',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF689F38),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF689F38)),
      ),
      body: AppContent(
        maxWidth: 900,
        child: RefreshIndicator(
          color: const Color(0xFF689F38),
          onRefresh: _load,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF689F38)))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: <Widget>[
                  if (!_signedIn) _guestBanner(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFC62828)),
                      ),
                    ),
                  if (!_loading && _games.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 20.h),
                      child: Column(
                        children: <Widget>[
                          const Icon(Icons.casino_outlined,
                              size: 56, color: Color(0xFFAED581)),
                          const SizedBox(height: 12),
                          Text(
                            'No games yet',
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF33691E),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Games you host or join are listed here, so you can '
                            'return to one after closing the app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF558B2F)),
                          ),
                        ],
                      ),
                    ),
                  for (final _GameEntry game in _games) _card(game),
                ],
              ),
        ),
      ),
    );
  }

  /// The reminder above a guest's list, with a way to fix it.
  Widget _guestBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC5E1A5)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These games are not linked to an account. Create an account or '
              'sign in to keep them on this device and any other.',
              style: TextStyle(
                fontSize: 12.sp,
                height: 1.3,
                color: const Color(0xFF33691E),
              ),
            ),
          ),
          TextButton(
            onPressed: _openAccount,
            child: Text(
              'Sign in',
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Signing in from the banner: the account screen pops back here, so the
  /// list redraws with the account's games and without the reminder.
  Future<void> _openAccount() async {
    final bool? signedIn = await context.push<bool>(AppRoutes.authReturning);
    if (signedIn != true || !mounted) return;
    setState(() => _loading = true);
    await _load();
  }

  Widget _card(_GameEntry game) {
    final (Color color, String label, IconData icon) = switch (game.status) {
      GameSession.suspended => (
          const Color(0xFFFFA000),
          'Suspended',
          Icons.pause_circle_outline
        ),
      GameSession.ended => (
          const Color(0xFF9E9E9E),
          'Ended',
          Icons.flag_outlined
        ),
      _ => (const Color(0xFF43A047), 'Active', Icons.play_circle_outline),
    };

    final String roleLabel = game.isBanker
        ? 'Banker'
        : game.isExBanker
            ? 'Ex-banker (view only)'
            : 'Player';
    final DateTime? started = game.startedAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFFFFF9C4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  // The game id is a join code, not a title: it stays in the
                  // game screen's QR and is not printed in the list.
                  child: Text(
                    game.isBanker
                        ? 'Your table'
                        : game.isExBanker
                            ? 'A table you handed over'
                            : 'Your game',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF33691E),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Icon(
                  game.isBanker ? Icons.account_balance : Icons.person,
                  size: 15,
                  color: const Color(0xFF689F38),
                ),
                const SizedBox(width: 5),
                Text(
                  'You were the $roleLabel',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF558B2F)),
                ),
              ],
            ),
            if (started != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Started ${_dateFormat.format(started.toLocal())}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7CB342)),
              ),
            ],
            if (game.endedAt != null)
              Text(
                'Ended ${_dateFormat.format(game.endedAt!.toLocal())}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7CB342)),
              ),
            if (game.status == GameSession.suspended && game.session != null)
              Text(
                'Paused by ${game.session!.bankerName} - only the banker can '
                'resume it',
                style: const TextStyle(fontSize: 12, color: Color(0xFFEF6C00)),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _open(game),
                child: Text(
                  switch (game.status) {
                    GameSession.ended => 'Open game',
                    GameSession.suspended => 'Open game',
                    _ => 'Return to game',
                  },
                  style: TextStyle(
                    color: game.status == GameSession.ended
                        ? const Color(0xFF757575)
                        : const Color(0xFF2E7D32),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
