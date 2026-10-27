/// Every screen the app can show, as a URL path.
///
/// The web build puts these in the address bar, so a refresh, a bookmark or a
/// link pasted into a chat lands on the same screen. The other platforms never
/// see the paths, but they navigate through the same names, which is what keeps
/// the two builds from drifting apart.
///
/// A path is assembled here rather than at each call site because a game id is
/// player-typed and may contain characters that mean something in a URL.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String auth = '/auth';
  static const String games = '/games';
  static const String start = '/start';
  static const String newGame = '/start/banker';
  static const String joinScan = '/join/scan';
  static const String profile = '/profile';
  static const String changePassword = '/profile/password';
  static const String setPassword = '/set-password';
  static const String howToUse = '/how-to-use';
  static const String gameRules = '/rules';
  static const String verifyEmail = '/verify';
  static const String gameDenied = '/game-denied';

  /// The boards and their cards, before a game exists.
  static const String boards = '/boards';

  /// The editor for a signed-in player's own board.
  static const String newBoard = '/boards/new';

  /// `/auth?return=1` - opened from a screen that stays put, so a successful
  /// sign-in pops back to it instead of replacing the whole stack.
  static const String authReturning = '/auth?return=1';

  /// `/auth?mode=signup` - the create-an-account half of the same screen.
  static const String signUp = '/auth?mode=signup';

  static String game(String gameId) => '/game/${Uri.encodeComponent(gameId)}';

  static String banker(String gameId, {double bankValue = 0}) =>
      '${game(gameId)}/banker?bank=${_money(bankValue)}';

  static String player(String gameId, {double bankValue = 0}) =>
      '${game(gameId)}/player?bank=${_money(bankValue)}';

  static String history(
    String gameId, {
    String playerId = '-',
    bool showAllPlayers = false,
  }) =>
      '${game(gameId)}/history?playerId=${Uri.encodeComponent(playerId)}'
      '${showAllPlayers ? '&all=1' : ''}';

  static String scanPay(String gameId) => '${game(gameId)}/scan-pay';

  /// Where a game URL lands when this device has no seat in it.
  ///
  /// [role] is the table that was asked for (`banker` or `player`), [reason]
  /// comes from the access check, and [from] is the refused location so the
  /// "Try again" button can repeat exactly what was typed.
  static String denied({
    required String gameId,
    required String reason,
    String? role,
    String? from,
  }) {
    return Uri(
      path: gameDenied,
      queryParameters: <String, String>{
        'game': gameId,
        'reason': reason,
        if (role != null) 'role': role,
        if (from != null) 'from': from,
      },
    ).toString();
  }

  /// The verification link in the email points here, so it must be stable.
  static String verify(String token) =>
      '$verifyEmail?token=${Uri.encodeComponent(token)}';

  static String _money(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
}
