import 'package:mon/models/bankpop_board.dart';

/// What the next building on a card would be.
enum BuildingKind { house, hotel }

/// Either the next building (with its price) or the reason it cannot be built.
class BuildingDecision {
  const BuildingDecision.build(this.kind, this.price) : reason = null;

  const BuildingDecision.blocked(this.reason)
      : kind = null,
        price = 0;

  final BuildingKind? kind;
  final int price;

  /// Why nothing can be built, in words the player can act on. Null when
  /// [kind] is set.
  final String? reason;

  bool get allowed => reason == null;
}

/// The house and hotel rules, kept out of the screen so they can be reasoned
/// about - and tested - on their own.
///
/// A player may build on a card only when:
///  * it is a colour property (Stations and Utilities never take buildings),
///  * they own every property in that colour set,
///  * the set is built evenly, so a card can only take its next house while no
///    other card in the set is behind it,
///  * and a hotel comes only after all four houses are up on every card.
class BuildingRules {
  const BuildingRules._();

  static BuildingDecision next({
    required BankpopSpace space,

    /// Every space in the card's colour group, including [space].
    required List<BankpopSpace> set,

    /// Board indexes of the cards this player owns.
    required Set<int> ownedCards,

    /// Houses already on [space].
    required int houses,

    /// Hotels already on [space], 0 or 1.
    required int hotels,

    /// Houses on each owned card, by board index.
    required Map<int, int> housesByCard,
  }) {
    final String? colour = space.color;
    if (colour == null || colour == 'Station' || colour == 'Utility') {
      return const BuildingDecision.blocked(
          'Houses can only be built on colour properties');
    }
    if (hotels > 0) {
      return const BuildingDecision.blocked('This card already has a hotel');
    }

    final List<BankpopSpace> missing =
        set.where((BankpopSpace s) => !ownedCards.contains(s.index)).toList();
    if (missing.isNotEmpty) {
      return BuildingDecision.blocked(
        'You need the whole $colour set first - missing '
        '${missing.map((BankpopSpace s) => s.name).join(', ')}',
      );
    }

    int fewest = houses;
    for (final BankpopSpace s in set) {
      final int onCard = housesByCard[s.index] ?? 0;
      if (onCard < fewest) fewest = onCard;
    }

    if (houses >= 4) {
      if (fewest < 4) {
        return BuildingDecision.blocked(
          'Build evenly: every card in the $colour set needs 4 houses '
          'before a hotel',
        );
      }
      final int price = space.hotelCost ?? 0;
      if (price <= 0) {
        return const BuildingDecision.blocked('This property has no hotel price');
      }
      return BuildingDecision.build(BuildingKind.hotel, price);
    }

    if (fewest < houses) {
      return const BuildingDecision.blocked(
          'Build evenly: put a house on the rest of the set first');
    }

    final int price = space.houseCost ?? 0;
    if (price <= 0) {
      return const BuildingDecision.blocked('This property has no house price');
    }
    return BuildingDecision.build(BuildingKind.house, price);
  }
}
