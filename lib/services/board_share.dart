import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  });

  final String name;

  /// The built-in board the names are relative to (`usa`, `india`, ...).
  final String baseId;

  /// Built-in space name -> the name this board gives it.
  final Map<String, String> renames;
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
///   "version": 1,
///   "name": "My Home Town",
///   "basedOn": "usa",
///   "spaces": { "Boardwalk": "Marine Drive" }
/// }
/// ```
///
/// There is nothing in it that could change a rule, so it is safe to paste in
/// from anywhere: [decode] refuses anything it does not recognise, and whatever
/// it accepts still goes through the editor's own checks before it is saved.
class BoardShare {
  const BoardShare._();

  static const String format = 'bankpop-board';

  /// Bumped when the document grows a field. Older files keep working; a file
  /// from a newer build is refused rather than half-read.
  static const int version = 1;

  static const int maxNameLength = BoardNames.maxLength;

  /// A board has ~28 renameable spaces; anything far past that is not a board.
  static const int maxSpaces = 48;

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
    final Map<String, String> renames = <String, String>{};

    try {
      final BankpopBoard base = await BoardCatalog.board(baseId);
      final Map<int, BankpopSpace> byIndex = <int, BankpopSpace>{
        for (final BankpopSpace space in base.spaces) space.index: space,
      };
      for (final BankpopSpace space in board.spaces) {
        final BankpopSpace? original = byIndex[space.index];
        if (original == null || original.name == space.name) continue;
        renames[original.name] = space.name;
      }
    } catch (error) {
      // The base could not be read; the names still travel, just unanchored,
      // and the editor will find them where it can.
      debugPrint('Could not read the base board to share: $error');
    }

    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format': format,
      'version': version,
      'name': board.boardName,
      'basedOn': baseId,
      'spaces': renames,
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
    if (rawSpaces is Map) {
      if (rawSpaces.length > maxSpaces) {
        throw const BoardImportFailure('That board has too many spaces.');
      }
      for (final MapEntry<dynamic, dynamic> entry in rawSpaces.entries) {
        final String base = entry.key.toString().trim();
        final String renamed = entry.value?.toString().trim() ?? '';
        if (base.isEmpty || renamed.isEmpty) {
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
        renames[base] = renamed;
      }
    }

    return BoardDraft(
      name: name,
      baseId: basedOn.isEmpty ? BoardCatalog.fallbackId : basedOn,
      renames: renames,
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
