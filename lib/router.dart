import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/pages/auth/auth_screen.dart';
import 'package:mon/pages/auth/onboarding_screen.dart';
import 'package:mon/pages/auth/set_password_screen.dart';
import 'package:mon/pages/banker/bank_details.dart';
import 'package:mon/pages/banker/banker_screen.dart';
import 'package:mon/pages/game_access_denied_screen.dart';
import 'package:mon/pages/game_history_screen.dart';
import 'package:mon/pages/game_rules_screen.dart';
import 'package:mon/pages/home.dart';
import 'package:mon/pages/how_to_use_screen.dart';
import 'package:mon/pages/player/player_details.dart';
import 'package:mon/pages/player/player_screen.dart';
import 'package:mon/pages/splash_screen.dart';
import 'package:mon/pages/transactions/pay.dart';
import 'package:mon/pages/transactions/transactions.dart';
import 'package:mon/pages/verify_email_screen.dart';
import 'package:mon/pages/role.dart';
import 'package:mon/profile.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/game_access.dart';

/// The app's screens as URLs.
///
/// Everything that used to be a `Navigator.push` is a route here, so the web
/// build has one history entry per screen: the browser's back button walks
/// back through them, a refresh lands on the same screen, and a link can be
/// sent to another player. Dialogs and sheets stay dialogs - they are not
/// places, and the back button should close them rather than navigate.
///
/// A game's id is part of its address (`/game/ABC123/banker`), which is also
/// why the screens no longer read the id from SharedPreferences alone.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.splash,
      builder: (BuildContext context, GoRouterState state) =>
          const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (BuildContext context, GoRouterState state) =>
          const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (BuildContext context, GoRouterState state) =>
          const WelcomePage(),
    ),
    GoRoute(
      path: AppRoutes.auth,
      builder: (BuildContext context, GoRouterState state) {
        final Map<String, String> query = state.uri.queryParameters;
        return AuthScreen(
          startWithSignUp: query['mode'] == 'signup',
          returnOnSuccess: query['return'] == '1',
        );
      },
    ),
    GoRoute(
      path: AppRoutes.games,
      builder: (BuildContext context, GoRouterState state) =>
          const GameHistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.start,
      builder: (BuildContext context, GoRouterState state) =>
          const SelectRoleScreen(),
    ),
    GoRoute(
      path: AppRoutes.newGame,
      builder: (BuildContext context, GoRouterState state) =>
          const BankValueScreen(),
    ),
    GoRoute(
      path: AppRoutes.joinScan,
      builder: (BuildContext context, GoRouterState state) =>
          const PlayerQRScannerScreen(scan: true),
    ),
    GoRoute(
      path: '/game/:gameId',
      redirect: (BuildContext context, GoRouterState state) =>
          AppRoutes.player(state.pathParameters['gameId'] ?? ''),
    ),
    // The game screens are guarded before they are built: a game id in the
    // address bar is not a key, and opening the URL is not the same as having
    // a seat at that table. The bank route needs the bank seat and the player
    // route needs a player seat; history and the scanner need any seat.
    GoRoute(
      path: '/game/:gameId/banker',
      redirect: (BuildContext context, GoRouterState state) =>
          _guardGame(state, GameSeat.banker),
      builder: (BuildContext context, GoRouterState state) => BankerGameScreen(
        bankValue: _money(state),
        gameId: state.pathParameters['gameId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/game/:gameId/player',
      redirect: (BuildContext context, GoRouterState state) =>
          _guardGame(state, GameSeat.player),
      builder: (BuildContext context, GoRouterState state) => PlayersScreen(
        bankValue: _money(state),
        gameId: state.pathParameters['gameId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/game/:gameId/history',
      redirect: (BuildContext context, GoRouterState state) =>
          _guardGame(state, null),
      builder: (BuildContext context, GoRouterState state) {
        final Map<String, String> query = state.uri.queryParameters;
        return TransactionHistoryPage(
          gameId: state.pathParameters['gameId'] ?? '',
          playerId: query['playerId'] ?? '-',
          showAllPlayers: query['all'] == '1',
        );
      },
    ),
    GoRoute(
      path: '/game/:gameId/scan-pay',
      redirect: (BuildContext context, GoRouterState state) =>
          _guardGame(state, null),
      builder: (BuildContext context, GoRouterState state) => QRPayScanner(
        gameId: state.pathParameters['gameId'] ?? '',
      ),
    ),
    GoRoute(
      path: AppRoutes.gameDenied,
      builder: (BuildContext context, GoRouterState state) {
        final Map<String, String> query = state.uri.queryParameters;
        return GameAccessDeniedScreen(
          gameId: query['game'] ?? '',
          reason: query['reason'] ?? 'notSeated',
          role: query['role'],
          retryPath: query['from'],
        );
      },
    ),
    GoRoute(
      path: AppRoutes.profile,
      builder: (BuildContext context, GoRouterState state) =>
          const ProfilePage(),
    ),
    GoRoute(
      path: AppRoutes.changePassword,
      builder: (BuildContext context, GoRouterState state) =>
          const SetPasswordScreen(forced: false),
    ),
    GoRoute(
      path: AppRoutes.setPassword,
      builder: (BuildContext context, GoRouterState state) =>
          const SetPasswordScreen(forced: true),
    ),
    GoRoute(
      path: AppRoutes.howToUse,
      builder: (BuildContext context, GoRouterState state) =>
          const HowToUseScreen(),
    ),
    GoRoute(
      path: AppRoutes.gameRules,
      builder: (BuildContext context, GoRouterState state) =>
          const GameRulesScreen(),
    ),
    GoRoute(
      path: AppRoutes.verifyEmail,
      builder: (BuildContext context, GoRouterState state) =>
          VerifyEmailScreen(token: state.uri.queryParameters['token']),
    ),
  ],
  errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
    backgroundColor: const Color(0xFFFFF8E1),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.wrong_location_outlined,
                size: 52, color: Color(0xFF689F38)),
            const SizedBox(height: 14),
            const Text(
              'This screen does not exist',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF33691E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              state.uri.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF7CB342)),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.home),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF689F38),
                foregroundColor: Colors.white,
              ),
              child: const Text('Back to the home screen'),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// The bank total is only a starting number - every game screen reads the real
/// one from the bank row - so a missing query parameter means "start at zero",
/// not "this route is broken".
double _money(GoRouterState state) =>
    double.tryParse(state.uri.queryParameters['bank'] ?? '') ?? 0;

/// Runs before a game screen is built. The database row is the only proof of a
/// seat, so the answer can take a moment; go_router waits for it, which is why
/// this is `FutureOr` rather than a synchronous check against local state.
Future<String?> _guardGame(GoRouterState state, GameSeat? seat) async {
  final String gameId = state.pathParameters['gameId'] ?? '';
  final GameAccess access = await GameGate.check(gameId: gameId, seat: seat);
  if (access == GameAccess.allowed) return null;
  return AppRoutes.denied(
    gameId: gameId,
    reason: access.name,
    role: seat?.name,
    from: state.uri.toString(),
  );
}
