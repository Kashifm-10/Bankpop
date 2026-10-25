import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';

/// What one card collects when another player lands on it.
class RentDue {
  const RentDue({
    required this.amount,
    this.diceMultiplier = 0,
    this.rentFree = false,
  });

  /// The money due, in the board's own currency units. Zero when the rent is
  /// on the dice and no throw has been given yet.
  final int amount;

  /// The number the throw is multiplied by, for a utility: 4 with one utility,
  /// 10 with both. Zero for every other card.
  final int diceMultiplier;

  /// True for a mortgaged card: it collects nothing.
  final bool rentFree;

  /// Whether the amount can only be worked out from a dice throw.
  bool get needsDice => diceMultiplier > 0;
}

/// The rent rules, in one place.
///
/// The payer used to type any amount, so a mortgaged card still collected, a
/// second station paid single rent, and a utility paid a fixed number instead
/// of the dice. Every screen that takes rent now asks this class for the figure
/// instead of reading the card itself.
abstract final class Rent {
  static bool isStation(BankpopSpace space) => space.color == 'Station';

  static bool isUtility(BankpopSpace space) => space.color == 'Utility';

  /// How many cards of [colour] this player holds in the game. A station's rent
  /// grows with the stations its owner holds, and a utility's multiplier
  /// depends on whether both utilities are held.
  static int ownedInGroup(
    String colour,
    List<PlayerCard> ownerCards,
    Map<int, BankpopSpace> spaces,
  ) {
    return ownerCards
        .where((PlayerCard card) => spaces[card.cardIndex]?.color == colour)
        .length;
  }

  /// The rent [card] collects right now.
  ///
  /// [ownerCards] is the whole hand of the card's owner - it is what decides a
  /// station's rate and a utility's multiplier. [dice] is the throw when the
  /// payer has entered one; a utility with no throw reports
  /// [RentDue.needsDice] and an amount of zero.
  static RentDue forCard({
    required BankpopSpace space,
    required PlayerCard card,
    required List<PlayerCard> ownerCards,
    required Map<int, BankpopSpace> spaces,
    int? dice,
  }) {
    // The rules book: a mortgaged property collects no rent.
    if (card.mortgaged) {
      return const RentDue(amount: 0, rentFree: true);
    }

    final List<int>? rent = space.rent;
    if (rent == null || rent.isEmpty) return const RentDue(amount: 0);

    if (isStation(space)) {
      final int owned = ownedInGroup('Station', ownerCards, spaces)
          .clamp(1, rent.length);
      return RentDue(amount: rent[owned - 1]);
    }

    if (isUtility(space)) {
      final int owned = ownedInGroup('Utility', ownerCards, spaces);
      // 4x the throw with one utility, 10x with both, read from the card's own
      // two rent figures so a board can never disagree with the deed.
      final int multiplier = owned >= 2 && rent.length > 1 ? rent[1] : rent[0];
      return RentDue(
        amount: dice == null ? 0 : dice * multiplier,
        diceMultiplier: multiplier,
      );
    }

    if (card.hasHotel) {
      return RentDue(amount: rent[rent.length > 5 ? 5 : rent.length - 1]);
    }
    if (card.houses > 0) {
      return RentDue(amount: rent[card.houses.clamp(0, rent.length - 1)]);
    }
    return RentDue(amount: rent[0]);
  }
}
