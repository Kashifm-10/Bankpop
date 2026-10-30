// The router asks GameGuard one question on every navigation: should this
// device be sent back to its table? These pin the four answers it can give,
// because getting one wrong either traps a player in a game they left or drops
// them out of one they are still playing.

import 'package:flutter_test/flutter_test.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/game_guard.dart';

void main() {
  tearDown(GameGuard.leave);

  test('a live game keeps the device on its own route', () {
    GameGuard.enter(gameId: 'ABC123', banker: true, suspended: false, ended: false);

    expect(GameGuard.active, isTrue);
    expect(GameGuard.gameRoute, AppRoutes.banker('ABC123'));

    GameGuard.enter(
        gameId: 'ABC123', banker: false, suspended: false, ended: false);
    expect(GameGuard.gameRoute, AppRoutes.player('ABC123'));
  });

  test('a suspended or ended table lets the device go', () {
    GameGuard.enter(
        gameId: 'ABC123', banker: false, suspended: true, ended: false);
    expect(GameGuard.gameRoute, isNull);

    GameGuard.enter(
        gameId: 'ABC123', banker: false, suspended: false, ended: true);
    expect(GameGuard.gameRoute, isNull);
  });

  test('leaving turns the redirect off', () {
    GameGuard.enter(
        gameId: 'ABC123', banker: false, suspended: false, ended: false);
    GameGuard.leave();

    expect(GameGuard.active, isFalse);
    expect(GameGuard.gameRoute, isNull);
  });

  test('a game without an id is never a reason to redirect', () {
    GameGuard.enter(gameId: '', banker: false, suspended: false, ended: false);

    expect(GameGuard.active, isFalse);
    expect(GameGuard.gameRoute, isNull);
  });
}
