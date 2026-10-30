import 'dart:convert';

import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_catalog.dart';

/// A board on its way from one player to another: its name, the country it was
/// copied from, and the new name of every space that was renamed.
///
/// Only names travel. Prices, rents, colour groups and building costs are the
/// game's, so a shared file cannot hand anybody cheaper rent - importing it is
/// the same as typing the names into the editor by hand.
class BoardDraft {
  const BoardDraft({
    required this.name,
    required this.baseId,
    required this.renames,
    this.renamesByIndex = const <int, String>{},
    this.flag = '',
  });

  final String name;

  /// The emoji the board's maker picked for it, if any.
  final String flag;

  /// The built-in board the names are relative to (`usa`, `india`, ...).
  final String baseId;

  /// Built-in space name -> the name this board gives it. Files written
  /// before the index format carry their names this way.
  final Map<String, String> renames;

  /// Board index -> the name written at that index: what a shared file
  /// carries now. The index is what ties a name to its card, so the file
  /// never has to guess from a name that may itself have been changed.
  final Map<int, String> renamesByIndex;
}

/// A board that could not be read, with the sentence to show the player.
class BoardImportFailure implements Exception {
  const BoardImportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads and writes the JSON a player sends to a friend.
///
/// The document is deliberately small and dumb:
///
/// ```json
/// {
///   "format": "bankpop-board",
///   "version": 2,
///   "name": "My Home Town",
///   "basedOn": "usa",
///   "spaces": [
///     { "index": 1, "name": "Marine Drive" },
///     { "index": 3, "name": "Harbour Street" }
///   ]
/// }
/// ```
///
/// Each entry is a card's index and nothing but the editable name: prices,
/// rents, colours and building costs are the game's, so a shared file cannot
/// hand anybody cheaper rent - importing it is the same as typing the names
/// into the editor by hand.
class BoardShare {
  const BoardShare._();

  static const String format = 'bankpop-board';

  /// Bumped when the document grows a field. Older files keep working; a file
  /// from a newer build is refused rather than half-read.
  static const int version = 2;

  /// The document in the shape a friend can copy, shown above the paste field
  /// so nobody has to guess what to write.
  ///
  /// Only the index and the editable name travel: the built-in country already
  /// carries the rest (prices, rents, colour groups, building costs), so a
  /// shared file cannot hand anybody cheaper rent.
  static const String sample = '{\n'
      '  "format": "$format",\n'
      '  "version": $version,\n'
      '  "name": "My Home Town",\n'
      '  "basedOn": "usa",\n'
      '  "spaces": [\n'
      '    { "index": 1, "name": "Marine Drive" },\n'
      '    { "index": 3, "name": "Harbour Street" }\n'
      '  ]\n'
      '}';

  static const int maxNameLength = BoardNames.maxLength;

  /// A board has ~28 renameable spaces; anything far past that is not a board.
  static const int maxSpaces = 48;

  /// The highest card number a board has. The board is the usual 40 spaces,
  /// and the index is what ties a shared name to its card.
  static const int maxBoardIndex = 39;

  /// Nothing a board needs comes close to this, and a paste of something else
  /// entirely is rejected before it is decoded.
  static const int maxLength = 64 * 1024;

  /// The board as JSON, to be copied or sent as a file.
  ///
  /// A player's own board is written against the built-in board it was copied
  /// from, so the names are the only thing in the document. A built-in country
  /// is written against itself, which makes its document just its name.
  static Future<String> encode(BankpopBoard board) async {
    final bool isCustom =
        board.boardId.startsWith('custom_') || board.boardId.isEmpty;
    final String baseId = isCustom ? BoardCatalog.fallbackId : board.boardId;

    // Every card the editor can rename, as its index and its name. Nothing
    // else about a space travels: the numbers are the game's, not the maker's.
    final List<Map<String, Object>> spaces = <Map<String, Object>>[
      for (final BankpopSpace space in board.spaces)
        if (space.isProperty &&
            !BoardNames.fixed.contains(space.name))
          <String, Object>{'index': space.index, 'name': space.name},
    ];

    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format': format,
      'version': version,
      'name': board.boardName,
      'basedOn': baseId,
      if (board.flag.isNotEmpty) 'flag': board.flag,
      'spaces': spaces,
    });
  }

  /// The draft in a pasted or imported document.
  ///
  /// Throws [BoardImportFailure] with a sentence the player can act on; nothing
  /// here trusts the text it was handed.
  static BoardDraft decode(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const BoardImportFailure('Paste the board text first');
    }
    if (trimmed.length > maxLength) {
      throw const BoardImportFailure(
          'That is too long to be a board. Copy just the board JSON.');
    }

    Object? raw;
    try {
      raw = jsonDecode(trimmed);
    } catch (_) {
      throw const BoardImportFailure(
          'That is not a board file. Ask your friend to copy the JSON again.');
    }
    if (raw is! Map) {
      throw const BoardImportFailure('That is not a board file.');
    }
    final Map<dynamic, dynamic> map = raw;

    if (map['format'] != format) {
      throw const BoardImportFailure('That is not a Bankpop board file.');
    }
    final int fileVersion = (map['version'] as num?)?.toInt() ?? 0;
    if (fileVersion > version) {
      throw const BoardImportFailure(
          'That board was made with a newer version of the app. Update and try '
          'again.');
    }

    final String name = (map['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      throw const BoardImportFailure('That board has no name.');
    }
    if (name.length > maxNameLength) {
      throw const BoardImportFailure('That board name is too long.');
    }

    final String basedOn = (map['basedOn'] as String?)?.trim() ?? '';
    final Object? rawSpaces = map['spaces'];
    final Map<String, String> renames = <String, String>{};
    final Map<int, String> renamesByIndex = <int, String>{};

    void checkName(String renamed) {
      if (renamed.isEmpty) {
        throw const BoardImportFailure(
            'A space in that board has no name. Ask for a fresh copy.');
      }
      if (renamed.length > maxNameLength) {
        throw BoardImportFailure('"$renamed" is too long for a space.');
      }
      if (BoardNames.fixed
          .any((String fixed) => fixed.toLowerCase() == renamed.toLowerCase())) {
        throw BoardImportFailure(
            '"$renamed" is a fixed space and cannot be renamed.');
      }
    }

    if (rawSpaces is List) {
      // The format now: a card's index and its name, nothing else. The index
      // is what ties the name to its card, so a renamed space is never
      // matched against a name that has since changed.
      if (rawSpaces.length > maxSpaces) {
        throw const BoardImportFailure('That board has too many spaces.');
      }
      for (final dynamic rawSpace in rawSpaces) {
        if (rawSpace is! Map) {
          throw const BoardImportFailure(
              'A card in that board is not written as { "index", "name" }. '
              'Ask for a fresh copy.');
        }
        final Object? rawIndex = rawSpace['index'];
        final int? index = rawIndex is num
            ? (rawIndex == rawIndex.roundToDouble()
                ? rawIndex.toInt()
                : null)
            : int.tryParse(rawIndex?.toString().trim() ?? '');
        if (index == null || index < 0 || index > maxBoardIndex) {
          throw const BoardImportFailure(
              'A card in that board has no valid "index", the number that '
              'ties its name to it. Ask for a fresh copy.');
        }
        final String renamed = (rawSpace['name'] ?? '').toString().trim();
        checkName(renamed);
        renamesByIndex[index] = renamed;
      }
    } else if (rawSpaces is Map) {
      // Files written before the index format named spaces by their built-in
      // name; they keep working.
      if (rawSpaces.length > maxSpaces) {
        throw const BoardImportFailure('That board has too many spaces.');
      }
      for (final MapEntry<dynamic, dynamic> entry in rawSpaces.entries) {
        final String base = entry.key.toString().trim();
        final String renamed = entry.value?.toString().trim() ?? '';
        if (base.isEmpty) {
          throw const BoardImportFailure(
              'A space in that board has no name. Ask for a fresh copy.');
        }
        checkName(renamed);
        renames[base] = renamed;
      }
    } else if (rawSpaces != null) {
      throw const BoardImportFailure(
          'The "spaces" of that board is neither a list nor a map. Ask for a '
          'fresh copy.');
    }

    // An older file has no flag; a flag is short by nature, so anything long
    // enough to be an attempt at something else is ignored rather than stored.
    final String flag = (map['flag'] as String?)?.trim() ?? '';

    return BoardDraft(
      name: name,
      baseId: basedOn.isEmpty ? BoardCatalog.fallbackId : basedOn,
      renames: renames,
      renamesByIndex: renamesByIndex,
      flag: flag.length <= 16 ? flag : '',
    );
  }

  /// `bankpop-my-home-town.json`, for the file a friend receives.
  static String fileName(String boardName) {
    final String slug = boardName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'bankpop-${slug.isEmpty ? 'board' : slug}.json';
  }
}
