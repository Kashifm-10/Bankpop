import 'package:flutter/foundation.dart';
import 'package:mon/routes.dart';

/// Keeps a device inside the game it is playing.
///
/// A phone at a table has nothing to do on the title screen mid-game: the
/// board, the players and the money are all on the game screen. The game
/// screens register themselves here while their table is live, and the router
/// sends any other page back to them - which is what makes the browser's
/// address bar, a stale bookmark or a deep link land where the player actually
/// is instead of in a second lobby.
///
/// Three things deliberately turn it off, because in each of them leaving is
/// exactly what should happen:
///
///  * the player left on purpose (Leave game, or confirming the back dialog),
///  * the banker suspended the table - players are paused, not playing,
///  * the game was ended.
///
/// It is in memory only. A cold start has no game yet; the home screen's
/// Continue path is what reopens one, and the screen then registers itself.
abstract final class GameGuard {
  static String? _gameId;
  static bool _banker = false;
  static bool _live = false;

  /// The game screen has the table: from now until [leave], any other page
  /// belongs to this game. Called with the session's own flags, so suspending
  /// or ending the game stops the redirect on the spot.
  static void enter({
    required String gameId,
    required bool banker,
    required bool suspended,
    required bool ended,
  }) {
    if (gameId.isEmpty) return;
    _gameId = gameId;
    _banker = banker;
    _live = !suspended && !ended;
  }

  /// This device is out: the player chose to go, or was removed. Nothing is
  /// redirected any more until a game screen registers again.
  static void leave() {
    _live = false;
    _gameId = null;
  }

  /// True while another page must not be shown.
  static bool get active => _live && (_gameId?.isNotEmpty ?? false);

  /// Bumped when something outside the game was asked for while [active] - the
  /// browser's back button, or an address typed into the bar.
  ///
  /// The router sends the device back to its table and bumps this, and the game
  /// screen answers with the same question the back button asks. Without it the
  /// browser's back would silently do nothing: the URL would simply be put back
  /// where it was, with no way to say "yes, leave".
  static final ValueNotifier<int> leaveRequests = ValueNotifier<int>(0);

  /// Called by the router when it turns a request for another page around.
  static void requestLeavePrompt() {
    leaveRequests.value++;
  }

  /// Where the router should send the player back to, or null when they are
  /// free to go wherever they asked for.
  static String? get gameRoute {
    if (!active) return null;
    final String id = _gameId!;
    return _banker ? AppRoutes.banker(id) : AppRoutes.player(id);
  }
}
