/// What a drawn Chance or Community Chest card asks the table to do.
///
/// The cards are text written when the board was made (some boards rename the
/// streets in them), so the action is read from the words rather than stored
/// separately. A card about moving, or one this build cannot read, is
/// [CardActionKind.none]: it is shown and the banker settles it at the table.
enum CardActionKind {
  none,

  /// The bank pays a player: "Collect £50", "Bank pays you dividend of £50".
  reward,

  /// A player pays the bank: "Pay school fees of £150", "Fine £20".
  pay,

  /// Every other player pays one player: "Collect £10 from each player".
  collectFromEach,

  /// "£40 per house, £115 per hotel", billed on what a player has built.
  repairs,

  /// A card kept in the player's hand until it is used.
  jailFree,
}

/// The two Get out of Jail Free cards.
///
/// A drawn one is held by a player rather than by the pack, so it is stored as a
/// `player_cards` row under an index no board space uses: the card is then in
/// the player's own hand, visible in My Cards, and out of the pack until it is
/// used. Nothing about the board changes - no space is at either index.
abstract final class JailFreeCards {
  static const int chanceIndex = 900;
  static const int chestIndex = 901;

  static bool isJailFree(int index) =>
      index == chanceIndex || index == chestIndex;

  /// What the card is called in the player's hand.
  static String nameFor(int index) => index == chestIndex
      ? 'Get out of Jail Free - Community Chest'
      : 'Get out of Jail Free - Chance';

  /// The pack the card belongs to, so it can be dropped back into it.
  static String packFor(int index) =>
      index == chestIndex ? 'Community Chest' : 'Chance';
}

class CardAction {
  const CardAction(
    this.kind, {
    this.amount = 0,
    this.perHouse = 0,
    this.perHotel = 0,
  });

  final CardActionKind kind;

  /// The money on a [reward], [pay] or [collectFromEach] card.
  final int amount;

  /// The rates on a [repairs] card.
  final int perHouse;
  final int perHotel;

  /// True for a card the banker can settle with money.
  bool get movesMoney =>
      kind == CardActionKind.reward ||
      kind == CardActionKind.pay ||
      kind == CardActionKind.collectFromEach ||
      kind == CardActionKind.repairs;

  /// What a player with [houses] houses and [hotels] hotels owes on a repairs
  /// card.
  int repairsFor(int houses, int hotels) =>
      houses * perHouse + hotels * perHotel;

  static final RegExp _firstNumber = RegExp(r'(\d+)');
  static final RegExp _perHouse = RegExp(r'(\d+)\s*per\s*house', caseSensitive: false);
  static final RegExp _perHotel = RegExp(r'(\d+)\s*per\s*hotel', caseSensitive: false);
  static final RegExp _fromEach =
      RegExp(r'from\s+(?:each|every)\s+player', caseSensitive: false);

  /// Reads the action out of the card's text.
  static CardAction parse(String text) {
    final String card = text.toLowerCase();

    if (card.contains('jail free')) {
      return const CardAction(CardActionKind.jailFree);
    }

    // A card that moves the piece is the table's business: the advance on it is
    // the square's own payment, not a reward the banker hands out from here.
    if (card.contains('advance to') ||
        card.contains('take a trip') ||
        card.contains('go back') ||
        card.contains('go to jail')) {
      return const CardAction(CardActionKind.none);
    }

    final int? first = _numberOf(card);

    if (_fromEach.hasMatch(card)) {
      return CardAction(CardActionKind.collectFromEach, amount: first ?? 0);
    }

    if (card.contains('repair')) {
      final int? house = _numberOf(card, _perHouse);
      final int? hotel = _numberOf(card, _perHotel);
      // A card that does not print its rates ("general repairs on all your
      // properties") cannot be billed from the text alone.
      if (house != null && hotel != null) {
        return CardAction(
          CardActionKind.repairs,
          perHouse: house,
          perHotel: hotel,
        );
      }
      return const CardAction(CardActionKind.none);
    }

    final bool rewarding = card.contains('collect') ||
        card.contains('receive') ||
        card.contains('refund') ||
        card.contains('dividend') ||
        card.contains('bank pays') ||
        card.contains('won') ||
        card.contains('matures');
    if (rewarding && first != null) {
      return CardAction(CardActionKind.reward, amount: first);
    }

    final bool paying = card.contains('pay') ||
        card.contains('fine') ||
        card.contains('fee') ||
        card.contains('tax') ||
        card.contains('hospital') ||
        card.contains('doctor') ||
        card.contains('assessed');
    if (paying && first != null) {
      return CardAction(CardActionKind.pay, amount: first);
    }

    return const CardAction(CardActionKind.none);
  }

  static int? _numberOf(String text, [RegExp? pattern]) {
    final RegExpMatch? match =
        (pattern ?? _firstNumber).firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
