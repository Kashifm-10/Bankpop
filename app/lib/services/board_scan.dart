import 'package:mon/models/bankpop_board.dart';

/// What a photograph of a board was read as.
///
/// A board is only ever *names* in this app - prices, rents, colour groups and
/// the order of the squares are the game's and cannot be edited - so reading a
/// picture of a board is reading its squares' names. [names] is one name per
/// square a player may rename, in board order, and [fromPhoto] says which of
/// them came out of the picture rather than being kept from the built-in board.
class BoardRead {
  const BoardRead({required this.names, required this.fromPhoto});

  final List<String> names;
  final List<bool> fromPhoto;

  /// How many names the picture actually gave: what the review screen reports
  /// back, so a player knows whether to look carefully before saving.
  int get captured => fromPhoto.where((bool found) => found).length;

  bool get isEmpty => captured == 0;
}

/// Turns the lines read off a board photograph into square names.
///
/// The work here is the noise: a photographed board gives the square names, but
/// also their prices, the corner words, the ring's numbers and whatever the
/// camera caught around the board. What is left is applied to the squares in
/// board order, which is how a board is printed - GO, then the first square,
/// round to the last - and anything the picture did not supply keeps the name
/// it has on the built-in board. Nothing is guessed at beyond that: the review
/// screen shows every name for a player to correct before the board is saved.
abstract final class BoardScan {
  /// The words a board prints for itself. A square named one of these is not a
  /// property name, and the app keeps its own wording for those squares.
  static const Set<String> _reserved = <String>{
    'GO',
    'JAIL',
    'CHANCE',
    'COMMUNITY CHEST',
    'FREE PARKING',
    'GO TO JAIL',
    'INCOME TAX',
    'SUPER TAX',
    'LUXURY TAX',
    'ELECTRIC',
    'CITY WATER',
    'ELECTRICITY',
    'WATER WORKS',
  };

  /// A letter: what makes a line a name rather than a number.
  static final RegExp _letter = RegExp('[A-Za-z]');

  /// A price stuck on the end of a name: "NORTH STAR STATION 200".
  static final RegExp _trailingPrice = RegExp(
    r'[\s\-\u2013\u2014]*[\u20B9\u20AC\u00A3\u00A5$\uE000\uE001]?\s*\d[\d,.]*\s*$',
  );

  /// The squares of [board] a player may rename, in board order: the two
  /// utilities keep their names because their tiles draw their own artwork.
  static List<BankpopSpace> renamable(BankpopBoard board) {
    final List<BankpopSpace> spaces = board.spaces
        .where((BankpopSpace space) =>
            space.isProperty && space.name != 'Electric' && space.name != 'City Water')
        .toList()
      ..sort((BankpopSpace a, BankpopSpace b) => a.index.compareTo(b.index));
    return spaces;
  }

  /// The lines that could be a square's name, cleaned and de-duplicated.
  static List<String> names(List<String> lines) {
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    for (final String raw in lines) {
      final String name = clean(raw);
      if (name.isEmpty) continue;
      if (_reserved.contains(name.toUpperCase())) continue;
      if (!seen.add(name.toLowerCase())) continue;
      out.add(name);
    }
    return out;
  }

  /// One line, as a name - or an empty string when it is not one.
  static String clean(String line) {
    String value = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    // The ring's numbers, bullets and stray punctuation at the ends.
    value = value.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
    if (value.length < 3) return '';
    // A price on its own line, and the ring's numbers, are not names.
    if (!_letter.hasMatch(value)) return '';
    value = value.replaceFirst(_trailingPrice, '').trim();
    if (value.length < 3) return '';
    // Three letters at least: a camera reads a lot of two-letter fragments.
    if (_letter.allMatches(value).length < 3) return '';
    // Boards print their names in capitals; the app's own names are not
    // shouted, so a name that is all capitals is set the way the tiles do.
    if (value == value.toUpperCase()) value = _titleCase(value);
    return value;
  }

  /// Applies the names read from a picture to [slots], in board order.
  static BoardRead apply(List<String> lines, List<BankpopSpace> slots) {
    final List<String> found = names(lines);
    final List<String> applied = <String>[];
    final List<bool> fromPhoto = <bool>[];
    for (int i = 0; i < slots.length; i++) {
      final bool captured = i < found.length;
      applied.add(captured ? found[i] : slots[i].name);
      fromPhoto.add(captured);
    }
    return BoardRead(names: applied, fromPhoto: fromPhoto);
  }

  static String _titleCase(String value) {
    const Set<String> small = <String>{
      'of',
      'the',
      'and',
      'on',
      'in',
      'at',
      'to',
      'for',
    };
    final List<String> words = value.split(' ');
    final List<String> out = <String>[];
    for (int i = 0; i < words.length; i++) {
      final String word = words[i];
      if (word.isEmpty) continue;
      final String lower = word.toLowerCase();
      if (i > 0 && small.contains(lower)) {
        out.add(lower);
      } else {
        out.add('${lower[0].toUpperCase()}${lower.substring(1)}');
      }
    }
    return out.join(' ');
  }
}
