import 'dart:convert';

/// The money sign the whole app is quoted in.
///
/// BankPop has one mark of its own - a heavy-bar B, drawn as the glyph at
/// U+E000 in `assets/fonts/BankpopMark.ttf` (see
/// `tool/make_currency_font.py` for how it is built). It is a character rather
/// than a picture so it sits inline in every price, ledger column, deed and
/// board print without any widget wrapping, and it follows the colour and size
/// of the text around it.
///
/// Boards used to be quoted in their country's currency (₹, $, €, ...). Every
/// price is now written in the same sign, so a stored symbol from an older
/// board row is ignored rather than printed.
abstract final class BoardCurrencies {
  /// BankPop's own money sign: the heavy-bar B, for anything that has to hold
  /// its own against a number - balances, prices, totals, the coin.
  static const String mark = '\uE000';

  /// The same sign in a lighter cut, for small print.
  ///
  /// At 10-13 px the heavy sign's bars fill in and the letter reads as a blot,
  /// so rent tables, ledger rows and the tiny prices printed on the board's
  /// tiles take this one instead. Both are single characters, so an amount is
  /// still just a string and every `Text` in the app can show it.
  static const String markLight = '\uE001';

  /// The sign used when nothing else is given - which is always [mark] now.
  static const String fallback = mark;

  /// Every board is quoted in the same sign, whichever country it is set in.
  static String forBoard(String boardId) => mark;

  /// The signs a board's maker can choose from: the one BankPop sign.
  static const List<String> choices = <String>[mark];

  /// Any money sign a stored row was written with: a board's own currency, or
  /// the rupee and pound that older copies of the cards and spaces still carry.
  static final RegExp _anySign = RegExp('[\u20B9\u20AC\u00A3\u00A5\$]');

  /// Board copy with one money sign.
  ///
  /// Cards and space names are text written when the board was made, so a card
  /// still reads "Collect £50". This swaps that sign for BankPop's mark, so the
  /// words on the card and the amount beside them use the same money.
  static String write(String text) => text.replaceAll(_anySign, mark);

  /// A price in small print, in the light cut of the sign.
  ///
  /// Same number, same order - only the weight of the sign changes, so a rent
  /// table set in this still lines up with a price set in [mark].
  static String formatLight(num value) => format(markLight, value);

  /// A price with its sign: `B 200` (the mark, then the number).
  static String format(String symbol, num value) {
    // A wallet stores 200 as 200.0; print it the way the board does.
    final num shown = value is double && value == value.roundToDouble()
        ? value.toInt()
        : value;
    return symbol.length > 1 ? '$symbol $shown' : '$symbol$shown';
  }
}

/// One space on the board.
///
/// The app draws and charges from these numbers, so they travel with the board
/// rather than being recomputed per screen: a custom board carries the same
/// prices, rents and building costs as the built-in board it was copied from.
class BankpopSpace {
  final int index;
  final String name;
  final String type; // 'Property' | 'Special'
  final int? price;
  final List<int>? rent;
  final String? color;
  final int? houseCost;
  final int? hotelCost;
  final int? houses;
  final int? hotels;

  const BankpopSpace({
    required this.index,
    required this.name,
    required this.type,
    this.price,
    this.rent,
    this.color,
    this.houseCost,
    this.hotelCost,
    this.houses,
    this.hotels,
  });

  bool get isProperty => type == 'Property';

  factory BankpopSpace.fromMap(Map<String, dynamic> map) {
    return BankpopSpace(
      index: (map['index'] as num).toInt(),
      name: (map['name'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'Special',
      price: (map['price'] as num?)?.toInt(),
      rent: (map['rent'] as List?)?.map((e) => (e as num).toInt()).toList(),
      color: map['color'] as String?,
      houseCost: (map['houseCost'] as num?)?.toInt(),
      hotelCost: (map['hotelCost'] as num?)?.toInt(),
      houses: (map['houses'] as num?)?.toInt(),
      hotels: (map['hotels'] as num?)?.toInt(),
    );
  }

  /// The same space with a different name, for a player's own board. Nothing
  /// else can differ: the creation screen only edits names.
  BankpopSpace renamed(String newName) => BankpopSpace(
        index: index,
        name: newName,
        type: type,
        price: price,
        rent: rent,
        color: color,
        houseCost: houseCost,
        hotelCost: hotelCost,
        houses: houses,
        hotels: hotels,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'index': index,
        'name': name,
        'type': type,
        if (price != null) 'price': price,
        if (rent != null) 'rent': rent,
        if (color != null) 'color': color,
        if (houseCost != null) 'houseCost': houseCost,
        if (hotelCost != null) 'hotelCost': hotelCost,
        if (houses != null) 'houses': houses,
        if (hotels != null) 'hotels': hotels,
      };
}

class BankpopBoard {
  final List<BankpopSpace> spaces;
  final List<String> chanceOptions;
  final List<String> communityChest;

  /// Which board this is (`india`, `custom_<uuid>`, ...), the name shown above
  /// it and its flag. Read from the database row.
  final String boardId;
  final String boardName;
  final String flag;

  /// The money sign its prices are written in - always [BoardCurrencies.mark].
  final String currency;

  const BankpopBoard({
    required this.spaces,
    required this.chanceOptions,
    required this.communityChest,
    this.boardId = '',
    this.boardName = '',
    this.flag = '',
    this.currency = BoardCurrencies.fallback,
  });

  /// A row of `game_boards` (see supabase/boards.sql). The `spaces` and `cards`
  /// columns arrive as JSON, which PostgREST hands back already decoded.
  factory BankpopBoard.fromMap(Map<String, dynamic> map) {
    final String boardId =
        map['board_id']?.toString() ?? map['id']?.toString() ?? '';
    final Object? rawSpaces = map['spaces'];
    final List<dynamic> spaceList = rawSpaces is String
        ? (jsonDecode(rawSpaces) as List<dynamic>)
        : (rawSpaces as List<dynamic>? ?? const <dynamic>[]);
    final Object? rawCards = map['cards'];
    final Map<String, dynamic> cards = rawCards is String
        ? (jsonDecode(rawCards) as Map<String, dynamic>)
        : (rawCards as Map<String, dynamic>? ?? const <String, dynamic>{});
    return BankpopBoard(
      spaces: <BankpopSpace>[
        for (final dynamic space in spaceList)
          BankpopSpace.fromMap(space as Map<String, dynamic>),
      ],
      chanceOptions:
          (cards['chanceOptions'] as List?)?.cast<String>() ?? const <String>[],
      communityChest: (cards['communityChest'] as List?)?.cast<String>() ??
          const <String>[],
      boardId: boardId,
      boardName: map['country']?.toString() ?? map['name']?.toString() ?? '',
      flag: map['flag']?.toString() ?? '',
      // One sign for every board, new or stored: an old row may still carry
      // its country's symbol, and printing that is what this replaces.
      currency: BoardCurrencies.forBoard(boardId),
    );
  }

  /// The row this board came from, so a device can keep its own copy of it
  /// (see [BoardCatalog.boardForGame]) without going back to the database.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'board_id': boardId,
        'name': boardName,
        'flag': flag,
        'currency': currency,
        'spaces': <Map<String, dynamic>>[
          for (final BankpopSpace space in spaces) space.toMap(),
        ],
        'cards': <String, dynamic>{
          'chanceOptions': chanceOptions,
          'communityChest': communityChest,
        },
      };

  /// The same board under another name, for a player's own board.
  ///
  /// Every space named in [renames] takes its new name, and the two decks are
  /// rewritten with the same map so "Advance to ..." and "Take a trip to ..."
  /// still point at real spaces. Nothing else is touched - the numbers are the
  /// game's, not the player's.
  BankpopBoard renamed({
    required Map<String, String> renames,
    required String name,
    String? boardId,
  }) {
    final List<String> keys = renames.keys.toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));

    String rewrite(String text) {
      for (final String old in keys) {
        text = text.replaceAll(old, '\u0000${renames[old]}\u0000');
      }
      return text.replaceAll('\u0000', '');
    }

    return BankpopBoard(
      spaces: <BankpopSpace>[
        for (final BankpopSpace space in spaces)
          renames.containsKey(space.name)
              ? space.renamed(renames[space.name]!)
              : space,
      ],
      chanceOptions: <String>[
        for (final String card in chanceOptions) rewrite(card),
      ],
      communityChest: <String>[
        for (final String card in communityChest) rewrite(card),
      ],
      boardId: boardId ?? this.boardId,
      boardName: name,
      flag: flag,
      currency: BoardCurrencies.mark,
    );
  }

  /// Standard Bankpop visual color per group.
  static int colorForGroup(String? group) {
    switch (group) {
      case 'Brown':
        return 0xFF8D5524;
      case 'Light Blue':
        return 0xFF90CAF9;
      case 'Pink':
        return 0xFFF48FB1;
      case 'Orange':
        return 0xFFFFB74D;
      case 'Red':
        return 0xFFE57373;
      case 'Yellow':
        return 0xFFFFEB3B;
      case 'Green':
        return 0xFF4CAF50;
      case 'Dark Blue':
        return 0xFF1565C0;
      case 'Station':
        return 0xFF5D4037;
      case 'Utility':
        return 0xFF90A4AE;
      default:
        return 0xFFBDBDBD;
    }
  }
}
