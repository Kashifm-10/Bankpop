import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/game_access.dart';

/// Where a game URL lands when this device has no seat in that game.
///
/// It never says whether the game exists: "not yours" is the same answer for a
/// typo, a game that was deleted and a table somebody else is running. A seated
/// player who opens the other role's URL gets a different sentence - they are
/// not being kept out, they are just on the wrong side of the table.
class GameAccessDeniedScreen extends StatelessWidget {
  const GameAccessDeniedScreen({
    super.key,
    required this.gameId,
    required this.reason,
    this.role,
    this.retryPath,
  });

  final String gameId;
  final String reason;
  final String? role;

  /// The game URL that was refused, used by "Try again". Only a game path is
  /// accepted, so this cannot be turned into a redirect anywhere else.
  final String? retryPath;

  GameAccess get _access => switch (reason) {
        'wrongRole' => GameAccess.wrongRole,
        'unavailable' => GameAccess.unavailable,
        _ => GameAccess.notSeated,
      };

  (String title, String message) get _copy {
    switch (_access) {
      case GameAccess.wrongRole:
        if (role == GameSeat.banker.name) {
          return (
            'The bank is not yours in this game',
            'You are at this table as a player. Paying from the bank, '
                'advancing a player and ending the game belong to the banker.',
          );
        }
        return (
          'You are the banker in this game',
          'The player screen needs a player seat. Open the banker table from '
              'Your Games instead.',
        );
      case GameAccess.unavailable:
        return (
          'Could not check your seat',
          'BankPop could not reach the game to confirm that this table is '
              'yours. Check your connection and try again.',
        );
      case GameAccess.allowed:
      case GameAccess.notSeated:
        return (
          'This game is not yours',
          'Only the players the banker has seated can open this game. Ask the '
              'banker for the Game ID and to approve your seat.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (String title, String message) = _copy;
    final bool canRetry = _access == GameAccess.unavailable &&
        (retryPath ?? '').startsWith('/game/');

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF689F38),
        foregroundColor: Colors.white,
        title: const Text(
          'Game not available',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                color: const Color(0xFFFFF9C4),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Icon(Icons.lock_outline,
                          size: 52, color: Color(0xFF689F38)),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF33691E),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: Color(0xFF558B2F),
                        ),
                      ),
                      if (gameId.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          'Game $gameId',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7CB342),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (canRetry) ...<Widget>[
                        ElevatedButton(
                          onPressed: () => context.go(retryPath!),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF689F38),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Try again',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      OutlinedButton(
                        onPressed: () => context.go(AppRoutes.games),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2E7D32),
                          side: const BorderSide(color: Color(0xFF689F38)),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Your games'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () => context.go(AppRoutes.home),
                        child: const Text(
                          'Back to home',
                          style: TextStyle(color: Color(0xFF2E7D32)),
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
