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

    /// Which of those cards are mortgaged: nothing can be built while the group
    /// has a mortgage on it.
    Map<int, bool> mortgagedByCard = const <int, bool>{},
  }) {
    final String? colour = space.color;
    if (colour == null || colour == 'Station' || colour == 'Utility') {
      return const BuildingDecision.blocked(
          'Houses can only be built on colour properties');
    }
    if (hotels > 0) {
      return const BuildingDecision.blocked('This card already has a hotel');
    }

    // A mortgaged card anywhere in the set stops building on all of it.
    final List<BankpopSpace> mortgaged = set
        .where((BankpopSpace s) => mortgagedByCard[s.index] == true)
        .toList();
    if (mortgaged.isNotEmpty) {
      return BuildingDecision.blocked(
        'Unmortgage first: ${mortgaged.map((BankpopSpace s) => s.name).join(', ')} '
        'is mortgaged.',
      );
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

  /// What the bank will pay for taking one building off [space] back: half the
  /// price it was bought for, and only when the set is sold evenly.
  ///
  /// Selling runs the same way building does, in reverse: a card may only lose
  /// its next building while it is level with the rest of the set, so nobody can
  /// strip one property and leave the others standing.
  static BuildingDecision sell({
    required BankpopSpace space,
    required List<BankpopSpace> set,
    required int houses,
    required int hotels,
    required Map<int, int> housesByCard,
  }) {
    final String? colour = space.color;
    if (colour == null || colour == 'Station' || colour == 'Utility') {
      return const BuildingDecision.blocked(
          'Buildings only come off colour properties');
    }
    if (houses <= 0 && hotels <= 0) {
      return const BuildingDecision.blocked('There is nothing to sell here');
    }

    // Selling a hotel first turns it back into the four houses it came from.
    if (hotels > 0) {
      final int price = (space.hotelCost ?? 0) ~/ 2;
      if (price <= 0) {
        return const BuildingDecision.blocked(
            'This property has no hotel price to halve');
      }
      return BuildingDecision.build(BuildingKind.hotel, price);
    }

    int most = 0;
    for (final BankpopSpace s in set) {
      final int onCard = housesByCard[s.index] ?? 0;
      if (onCard > most) most = onCard;
    }
    if (houses < most) {
      return const BuildingDecision.blocked(
          'Sell evenly: the rest of the set has to come down first');
    }

    final int price = (space.houseCost ?? 0) ~/ 2;
    if (price <= 0) {
      return const BuildingDecision.blocked(
          'This property has no house price to halve');
    }
    return BuildingDecision.build(BuildingKind.house, price);
  }
}
