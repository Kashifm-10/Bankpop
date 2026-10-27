import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/player_exit.dart';

/// `players_test.status` is the only standing a seat has: seated, or removed by
/// the banker. The column is optional - a project that has not run
/// supabase/players_cleanup.sql has none - so the parsing has to give the old
/// behaviour for a row that carries it not at all.
void main() {
  group('PlayerStanding.fromRow', () {
    test('reads both states', () {
      expect(PlayerStanding.fromRow(<String, dynamic>{'status': 'active'}),
          PlayerStanding.active);
      expect(PlayerStanding.fromRow(<String, dynamic>{'status': 'kicked'}),
          PlayerStanding.kicked);
    });

    test('a leftover left row is an ordinary seated player', () {
      // The old schema allowed it; joining the table is not a standing, so the
      // app treats it as active until the cleanup SQL has run.
      expect(PlayerStanding.fromRow(<String, dynamic>{'status': 'left'}),
          PlayerStanding.active);
    });

    test('a row without the column is an ordinary player', () {
      expect(PlayerStanding.fromRow(<String, dynamic>{'role': 'player'}),
          PlayerStanding.active);
      expect(
          PlayerStanding.fromRow(<String, dynamic>{}), PlayerStanding.active);
    });

    test('the role fallback still marks a removed player', () {
      // What the kick path writes on a project without player_status.sql.
      expect(PlayerStanding.fromRow(<String, dynamic>{'role': 'kicked'}),
          PlayerStanding.kicked);
    });

    test('a banker row is never a gone player', () {
      expect(PlayerStanding.fromRow(<String, dynamic>{'role': 'banker'}),
          PlayerStanding.active);
    });

    test('an unknown status reads as active rather than a new badge', () {
      expect(PlayerStanding.fromRow(<String, dynamic>{'status': 'paused'}),
          PlayerStanding.active);
    });

    test('isGone is true only for a removed player', () {
      expect(PlayerStanding.active.isGone, isFalse);
      expect(PlayerStanding.kicked.isGone, isTrue);
    });
  });

  group('KickPreview', () {
    test('reports what is about to move', () {
      const KickPreview preview =
          KickPreview(cash: 420, cards: 3, houses: 2, hotels: 1);

      expect(preview.cards, 3);
      expect(preview.buildings, 3);
      expect(preview.hasBuildings, isTrue);
      expect(preview.buildingSummary, '2 houses and 1 hotel');
    });

    test('names a single building without a conjunction', () {
      expect(
        const KickPreview(cash: 0, cards: 1, houses: 1, hotels: 0)
            .buildingSummary,
        '1 house',
      );
      expect(
        const KickPreview(cash: 0, cards: 1, houses: 0, hotels: 1)
            .buildingSummary,
        '1 hotel',
      );
    });

    test('a player with bare land has nothing to sell back', () {
      const KickPreview preview =
          KickPreview(cash: 0, cards: 2, houses: 0, hotels: 0);

      expect(preview.hasBuildings, isFalse);
      expect(preview.buildingSummary, 'none');
    });
  });

  group('RestoreOutcome', () {
    test('ok reports a seat handed back', () {
      const RestoreOutcome outcome = RestoreOutcome.ok();
      expect(outcome.ok, isTrue);
      expect(outcome.failure, isNull);
      expect(outcome.legacy, isFalse);
    });

    test('the legacy path is reported, not hidden', () {
      const RestoreOutcome outcome = RestoreOutcome.ok(legacy: true);
      expect(outcome.ok, isTrue);
      expect(outcome.legacy, isTrue);
    });

    test('rejected keeps the reason', () {
      const RestoreOutcome outcome =
          RestoreOutcome.rejected('That player is not in this game');
      expect(outcome.ok, isFalse);
      expect(outcome.failure, 'That player is not in this game');
    });
  });

  group('KickOutcome', () {
    test('ok carries what moved', () {
      const KickOutcome outcome =
          KickOutcome.ok(cash: 1500, cards: 3, buildings: 2, legacy: false);
      expect(outcome.ok, isTrue);
      expect(outcome.failure, isNull);
      expect(outcome.cash, 1500);
      expect(outcome.cards, 3);
      expect(outcome.buildings, 2);
    });

    test('rejected keeps the reason and reports nothing moved', () {
      const KickOutcome outcome =
          KickOutcome.rejected('the cash could not be moved');
      expect(outcome.ok, isFalse);
      expect(outcome.failure, 'the cash could not be moved');
      expect(outcome.cash, 0);
      expect(outcome.cards, 0);
    });
  });
}
