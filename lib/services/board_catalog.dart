import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/game_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// A board as the pickers list it: the name, its flag and who owns it.
///
/// The spaces are not loaded until a board is actually chosen, so the picker
/// costs one small query instead of one large row per board.
class BoardListing {
  const BoardListing({
    required this.boardId,
    required this.name,
    this.flag = '',
    this.ownerId,
    this.isCustom = false,
  });

  /// Stored on the game session, so it is what the whole table reads back.
  final String boardId;
  final String name;
  final String flag;

  /// The player who created this board, or null on a built-in country.
  final String? ownerId;
  final bool isCustom;

  /// A player's own board, as opposed to the countries everyone gets.
  bool get isMine => ownerId != null && ownerId!.isNotEmpty;

  factory BoardListing.fromRow(Map<String, dynamic> row) {
    return BoardListing(
      boardId: row['board_id']?.toString() ?? '',
      name: row['name']?.toString() ?? 'Board',
      flag: row['flag']?.toString() ?? '',
      ownerId: row['owner_id']?.toString(),
      isCustom: row['is_custom'] == true,
    );
  }
}

/// What came of trying to save a player's board.
class BoardCreateResult {
  const BoardCreateResult.ok(this.boardId)
      : duplicateName = false,
        failed = false;

  const BoardCreateResult.duplicateName()
      : boardId = null,
        duplicateName = true,
        failed = false;

  const BoardCreateResult.failed()
      : boardId = null,
        duplicateName = false,
        failed = true;

  final String? boardId;
  final bool duplicateName;
  final bool failed;

  bool get ok => boardId != null;
}

/// The naming rules a player's board has to obey, in one place so the editor
/// and its checks cannot drift apart.
class BoardNames {
  const BoardNames._();

  /// Spaces whose names are the game's, not the player's: the utility tiles
  /// draw their own "Electric" and "City Water" artwork.
  static const Set<String> fixed = <String>{'Electric', 'City Water'};

  static const String stationSuffix = 'Station';

  /// The longest a board name or a card name may be. The editor, the shared
  /// JSON and the tiles all read it from here, so a name that fits in one place
  /// fits in all of them.
  static const int maxLength = 40;

  /// The longest name a colour property may have. Its name is printed inside
  /// the tile's colour block in at most two lines, and a longer one would have
  /// to shrink below the size every other card is set in.
  static const int colourNameMaxLength = 20;

  /// A station always ends in "Station". Whatever the player typed is kept and
  /// the word is completed after it, so the rule is enforced without turning
  /// into an error they have to guess their way out of.
  static String finishStation(String typed) {
    final String value = typed.trim();
    if (value.isEmpty) return '';
    if (value.toLowerCase().endsWith(stationSuffix.toLowerCase())) return value;
    return '$value $stationSuffix';
  }
}

/// The boards in the database, and which one the current game plays on.
///
/// Boards live in `game_boards` (see supabase/boards.sql): the built-in
/// countries, which everybody can pick, and the boards a signed-in player has
/// made for themselves. A board is only the *names* of the spaces - prices,
/// rents, colour groups and the order of the tiles are identical everywhere -
/// so choosing one cannot change a rule.
///
/// The choice belongs to the game, so it is written to `game_sessions.board_id`
/// and every device at the table reads it from there; this class is the one
/// place that turns an id into a loaded board.
class BoardCatalog {
  const BoardCatalog._();

  static const String _table = 'game_boards';

  /// The board a game plays on when nothing else is known: a game started
  /// before boards existed, or a row written by an older build.
  static const String fallbackId = 'usa';

  /// The board the current game plays on.
  static String _activeId = fallbackId;

  static String get activeId => _activeId;

  /// The symbol the current game's prices are written in. The board's own, so
  /// a screen that only knows a game id (the ledger, a scanner) still reads the
  /// country's money rather than a hard-coded £.
  static String _activeCurrency = BoardCurrencies.fallback;

  static String get activeCurrency => _activeCurrency;

  /// Game screens call this when they load the session: a wrong board would
  /// rename every property in the game, so an id this build does not know is
  /// ignored rather than silently swapped for another board.
  static void use(String? boardId) {
    if (boardId == null || boardId.isEmpty) return;
    _activeId = boardId;
  }

  static List<BoardListing>? _listings;

  /// The built-in boards plus this player's own, alphabetically by name.
  ///
  /// [refresh] re-reads the table, which is what the banker's picker does after
  /// a board has just been created.
  static Future<List<BoardListing>> available({bool refresh = false}) async {
    final List<BoardListing>? cached = _listings;
    if (cached != null && !refresh) return cached;
    try {
      final String? owner = await _signedInPlayerId();
      final PostgrestFilterBuilder<dynamic> query = Supabase.instance.client
          .from(_table)
          .select('board_id, name, flag, owner_id, is_custom');
      // A guest sees the countries; a signed-in player also sees the boards
      // they made. Nobody else's custom board is ever listed.
      final List<dynamic> rows = owner == null
          ? await query.isFilter('owner_id', null)
          : await query.or('owner_id.is.null,owner_id.eq.$owner');
      final List<BoardListing> boards = <BoardListing>[
        for (final dynamic raw in rows)
          BoardListing.fromRow(raw as Map<String, dynamic>),
      ]..sort((BoardListing a, BoardListing b) {
          if (a.isMine != b.isMine) return a.isMine ? 1 : -1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      _listings = boards;
      return boards;
    } catch (error) {
      debugPrint('Could not read the boards (run supabase/boards.sql): $error');
      _listings = const <BoardListing>[];
      return _listings!;
    }
  }

  /// The listing for an id, or null when the table has no such board.
  static Future<BoardListing?> listing(String boardId) async {
    final List<BoardListing> boards = await available();
    for (final BoardListing board in boards) {
      if (board.boardId == boardId) return board;
    }
    return null;
  }

  static final Map<String, Future<BankpopBoard>> _boards =
      <String, Future<BankpopBoard>>{};
  static final Map<String, Map<int, BankpopSpace>> _spaces =
      <String, Map<int, BankpopSpace>>{};

  /// Loads a board, once per app run.
  static Future<BankpopBoard> board([String? boardId]) {
    final String id =
        (boardId == null || boardId.isEmpty) ? _activeId : boardId;
    return _boards.putIfAbsent(id, () => _fetch(id));
  }

  static Future<BankpopBoard> _fetch(String boardId) async {
    // Every column, so a project that has not added a newer one (the currency
    // symbol, say) still loads its boards instead of failing the select.
    final Map<String, dynamic>? row = await Supabase.instance.client
        .from(_table)
        .select()
        .eq('board_id', boardId)
        .maybeSingle();
    if (row == null) {
      throw StateError('Board "$boardId" is not in game_boards. Run '
          'supabase/boards.sql.');
    }
    return BankpopBoard.fromMap(row);
  }

  /// Board index -> space for the current game's board.
  ///
  /// Cards store a board index rather than a name (`player_cards.card_index`),
  /// so this map is what turns a stored index back into the name the players
  /// see. An unreadable board yields an empty map and callers fall back to
  /// "Card #n" rather than failing the screen.
  static Future<Map<int, BankpopSpace>> spaces([String? boardId]) async {
    final String id =
        (boardId == null || boardId.isEmpty) ? _activeId : boardId;
    final Map<int, BankpopSpace>? cached = _spaces[id];
    if (cached != null) return cached;
    try {
      final BankpopBoard loaded = await board(id);
      final Map<int, BankpopSpace> map = <int, BankpopSpace>{
        for (final BankpopSpace space in loaded.spaces) space.index: space,
      };
      _spaces[id] = map;
      return map;
    } catch (error) {
      debugPrint('Could not load the $id board: $error');
      _spaces[id] = const <int, BankpopSpace>{};
      return _spaces[id]!;
    }
  }

  /// Saves a player's own board, copied from the built-in one so its prices,
  /// rents and building costs are exactly the game's, and returns its id.
  ///
  /// Only the names differ: [renames] maps each built-in space name to the one
  /// this player typed. The two utilities are not in the map and keep their
  /// names, which is what the creation screen promises.
  static Future<BoardCreateResult> createCustom({
    required String name,
    required String ownerId,
    required Map<String, String> renames,
    /// A flag or any other emoji the player picked to stand for their board, so
    /// it sits in the picker beside the countries' flags.
    String flag = '',
    String baseId = fallbackId,
    /// The money symbol this board's prices are written in. Empty keeps the
    /// built-in country's own currency.
    String currency = '',
  }) async {
    if (ownerId.isEmpty) return const BoardCreateResult.failed();
    try {
      // An imported board is named relative to the country it was copied from,
      // so that is what its names are applied to. Every board has the same
      // prices and the same order, so the choice only ever changes names.
      final BankpopBoard base = await board(baseId);
      final String boardId = 'custom_${const Uuid().v4()}';
      final BankpopBoard custom = base.renamed(
        renames: renames,
        name: name,
        boardId: boardId,
        currency: currency.trim().isEmpty ? base.currency : currency.trim(),
      );
      final Map<String, dynamic> row = <String, dynamic>{
        'board_id': boardId,
        'name': name,
        'flag': flag.trim(),
        'owner_id': ownerId,
        'is_custom': true,
        'currency': custom.currency,
        'spaces': <Map<String, dynamic>>[
          for (final BankpopSpace space in custom.spaces) space.toMap(),
        ],
        'cards': <String, dynamic>{
          'chanceOptions': custom.chanceOptions,
          'communityChest': custom.communityChest,
        },
      };
      try {
        await Supabase.instance.client.from(_table).insert(row);
      } on PostgrestException catch (error) {
        // A project that has not run supabase/board_currency.sql has no column
        // for the symbol. The board still saves, on the country's currency.
        if (!_currencyColumnMissing(error)) rethrow;
        await Supabase.instance.client
            .from(_table)
            .insert(<String, dynamic>{...row}..remove('currency'));
      }
      _boards[boardId] = Future<BankpopBoard>.value(custom);
      _spaces[boardId] = <int, BankpopSpace>{
        for (final BankpopSpace space in custom.spaces) space.index: space,
      };
      _listings = null; // the next open of a picker re-reads the table
      return BoardCreateResult.ok(boardId);
    } on PostgrestException catch (error) {
      // 23505 is the unique index on (owner_id, lower(name)): this player
      // already has a board with that name.
      if (error.code == '23505') return const BoardCreateResult.duplicateName();
      debugPrint('Could not save the board: ${error.code} ${error.message}');
      return const BoardCreateResult.failed();
    } catch (error) {
      debugPrint('Could not save the board: $error');
      return const BoardCreateResult.failed();
    }
  }

  /// 42703 is "undefined column"; PGRST204 is the same fact reported from a
  /// stale PostgREST schema cache.
  static bool _currencyColumnMissing(PostgrestException error) =>
      error.code == '42703' ||
      error.code == 'PGRST204' ||
      error.message.contains('currency');

  /// The board this device last played on, before the session row arrives.
  ///
  /// The banker's device wrote the choice when the game was created, so a
  /// reopen on the same phone is right immediately; the session row then
  /// corrects it (and is the only source on a player's phone).
  static Future<void> useForGame(String gameId) async {
    if (gameId.isEmpty) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? local = prefs.getString('board_id');
      if (local != null && local.isNotEmpty) use(local);
    } catch (error) {
      debugPrint('Could not read the local board choice: $error');
    }
    final GameSession? session = await GameSession.fetch(gameId);
    if (session != null) use(session.boardId);
    // The board cannot change while the game lasts, so this device keeps its
    // own copy of it for the whole game: opening the board or a card sheet
    // then reads from the phone instead of the database. A player's phone
    // fetches it here once, the first time it learns which board the game uses.
    if (session != null && !_gameBoardFutures.containsKey(gameId)) {
      await boardForGame(gameId);
    }
  }

  // ---------------------------------------------------------------------
  // The board a game plays on, as this device keeps it.
  //
  // A game's board is fixed the moment the banker starts the game, so the
  // board and both card decks can be held on the device that is playing it: a
  // full board is a few kilobytes, and reading it back costs one decode instead
  // of a round trip that a phone at a table may not be able to make.
  // ---------------------------------------------------------------------

  /// One key holding the last few games' boards, newest first. Older games are
  /// dropped as new ones start, so the copy never grows without a limit.
  static const String _gameCacheKey = 'board_game_cache';

  static const int _gameCacheGames = 5;

  static final Map<String, Future<BankpopBoard>> _gameBoardFutures =
      <String, Future<BankpopBoard>>{};

  static final Map<String, Map<int, BankpopSpace>> _gameSpaces =
      <String, Map<int, BankpopSpace>>{};

  /// The board [gameId] plays on: this device's own copy when it has one,
  /// otherwise one read from the database, which is then kept for the game.
  static Future<BankpopBoard> boardForGame(String gameId) {
    if (gameId.isEmpty) return board();
    return _gameBoardFutures.putIfAbsent(gameId, () async {
      final BankpopBoard loaded = await _boardForGame(gameId);
      _activeCurrency = loaded.currency;
      return loaded;
    });
  }

  static Future<BankpopBoard> _boardForGame(String gameId) async {
    final BankpopBoard? kept = await _readGameCache(gameId);
    if (kept != null) {
      // Also the board this device is playing on, so every other lookup in
      // this app run is answered from memory.
      use(kept.boardId);
      _boards[kept.boardId] = Future<BankpopBoard>.value(kept);
      return kept;
    }
    final BankpopBoard loaded = await board();
    await _writeGameCache(gameId, loaded);
    return loaded;
  }

  /// Board index -> space for [gameId]'s board, from the copy this device keeps
  /// once the game has started. Cards store an index rather than a name, so
  /// this is what turns one back into the name the players see.
  static Future<Map<int, BankpopSpace>> spacesForGame(String gameId) async {
    if (gameId.isEmpty) return spaces();
    final Map<int, BankpopSpace>? kept = _gameSpaces[gameId];
    if (kept != null) return kept;
    try {
      final BankpopBoard loaded = await boardForGame(gameId);
      final Map<int, BankpopSpace> map = <int, BankpopSpace>{
        for (final BankpopSpace space in loaded.spaces) space.index: space,
      };
      _gameSpaces[gameId] = map;
      return map;
    } catch (error) {
      debugPrint('Could not load the $gameId board: $error');
      return const <int, BankpopSpace>{};
    }
  }

  /// Saves this device's copy of the board a game plays on.
  ///
  /// Called where the game starts - on the banker's phone when the game is
  /// created, and on a player's when it first reads the session - so nothing
  /// during the game has to go looking for the board again.
  static Future<void> cacheForGame(String gameId, [String? boardId]) async {
    if (gameId.isEmpty) return;
    try {
      final BankpopBoard loaded = await board(boardId);
      await _writeGameCache(gameId, loaded);
      _gameBoardFutures[gameId] = Future<BankpopBoard>.value(loaded);
    } catch (error) {
      // The game still plays; it just has to read the board from the server.
      debugPrint('Could not keep the $gameId board: $error');
    }
  }

  static Future<BankpopBoard?> _readGameCache(String gameId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_gameCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Object? entry = decoded[gameId];
      if (entry is! Map) return null;
      return BankpopBoard.fromMap(entry.cast<String, dynamic>());
    } catch (error) {
      debugPrint('Could not read the kept board for $gameId: $error');
      return null;
    }
  }

  static Future<void> _writeGameCache(String gameId, BankpopBoard board) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> cache = <String, dynamic>{
        gameId: board.toMap(),
      };
      final String? raw = prefs.getString(_gameCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final MapEntry<dynamic, dynamic> entry in decoded.entries) {
            if (cache.length >= _gameCacheGames) break;
            final String key = entry.key.toString();
            if (key == gameId || entry.value is! Map) continue;
            cache[key] = entry.value;
          }
        }
      }
      await prefs.setString(_gameCacheKey, jsonEncode(cache));
    } catch (error) {
      debugPrint('Could not keep the $gameId board: $error');
    }
  }

  /// The id of the signed-in player, or null for a guest. Custom boards hang
  /// off this id, so a board made on one phone is on that account everywhere.
  static Future<String?> _signedInPlayerId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? accountId = prefs.getString('account_id');
    if (accountId == null || accountId.isEmpty) return null;
    return accountId;
  }

  /// Test hook: forget the loaded boards and go back to the fallback board.
  @visibleForTesting
  static void reset() {
    _activeId = fallbackId;
    _boards.clear();
    _spaces.clear();
    _listings = null;
    _gameBoardFutures.clear();
    _gameSpaces.clear();
  }
}
