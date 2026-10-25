import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every kind of deal the game lets a player ask for.
enum DealKind {
  /// The bank pays the player half the price and takes the rent away.
  mortgage,

  /// The player pays the mortgage value plus 10% and gets the rent back.
  unmortgage,

  /// One house back to the bank for half what it cost.
  sellHouse,

  /// One hotel back to the bank for half what it cost.
  sellHotel,

  /// Cards and money between two players, settled by the other side.
  trade,
}

/// One row of `deal_requests`: a mortgage, a sale of buildings, or a trade.
///
/// Nothing moves when it is written. The other side settles it, and only then do
/// the money and the cards move together. [toId] is the bank's player_id for a
/// bank deal and the other player's for a trade, so exactly one device sees the
/// request and one answer settles it.
class DealRequest {
  const DealRequest({
    required this.id,
    required this.gameId,
    required this.kind,
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.toName,
    required this.cards,
    required this.wants,
    required this.offerCash,
    required this.wantsCash,
    required this.status,
    this.date = '',
    this.time = '',
  });

  final int id;
  final String gameId;
  final DealKind kind;
  final String fromId;
  final String fromName;
  final String toId;
  final String toName;

  /// Board indexes this side puts on the table.
  final List<int> cards;

  /// Board indexes this side asks for.
  final List<int> wants;

  final double offerCash;
  final double wantsCash;
  final String status;

  /// When the deal was written (`yyyy-MM-dd`), so the history tabs can sort.
  final String date;

  /// When the deal was written (`HH:mm:ss`).
  final String time;

  bool get isTrade => kind == DealKind.trade;

  String get label => switch (kind) {
        DealKind.mortgage => 'mortgage',
        DealKind.unmortgage => 'unmortgage',
        DealKind.sellHouse => 'a house',
        DealKind.sellHotel => 'a hotel',
        DealKind.trade => 'a trade',
      };

  factory DealRequest.fromMap(Map<String, dynamic> map) {
    return DealRequest(
      id: (map['id'] as num?)?.toInt() ?? -1,
      gameId: map['game_id']?.toString() ?? '',
      kind: _kindOf(map['kind']?.toString()),
      fromId: map['from_id']?.toString() ?? '',
      fromName: map['from_name']?.toString() ?? 'Player',
      toId: map['to_id']?.toString() ?? '',
      toName: map['to_name']?.toString() ?? 'Bank',
      cards: _indexes(map['cards']?.toString()),
      wants: _indexes(map['wants']?.toString()),
      offerCash: (map['cash'] as num?)?.toDouble() ?? 0,
      wantsCash: (map['wants_cash'] as num?)?.toDouble() ?? 0,
      status: map['status']?.toString() ?? 'pending',
      date: map['date']?.toString() ?? '',
      time: map['time']?.toString() ?? '',
    );
  }

  static DealKind _kindOf(String? value) {
    switch (value) {
      case 'mortgage':
        return DealKind.mortgage;
      case 'unmortgage':
        return DealKind.unmortgage;
      case 'sell_house':
        return DealKind.sellHouse;
      case 'sell_hotel':
        return DealKind.sellHotel;
      default:
        return DealKind.trade;
    }
  }

  static List<int> _indexes(String? value) {
    if (value == null || value.isEmpty) return const <int>[];
    return value
        .split(',')
        .map((String part) => int.tryParse(part.trim()))
        .whereType<int>()
        .toList();
  }
}

/// What happened when the other side acted on a deal.
class DealOutcome {
  const DealOutcome.ok() : error = null;

  const DealOutcome.rejected(this.error);

  final String? error;

  bool get ok => error == null;
}

/// Reads and settles `deal_requests` (created by supabase/mortgage_trades.sql).
/// One money movement inside a settlement: what it was, and who it was for, so
/// a failure further on can hand it back in the same shape.
class _Move {
  const _Move(this.from, this.fromName, this.to, this.toName, this.value);

  final String from;
  final String fromName;
  final String to;
  final String toName;
  final double value;
}

class Deals {
  const Deals._();

  static const String _table = 'deal_requests';
  static const String _cardsTable = 'player_cards';

  /// Every request waiting on [playerId] in this game, oldest first.
  static Future<List<DealRequest>> pendingFor(
    String gameId,
    String playerId,
  ) async {
    if (playerId.isEmpty) return const <DealRequest>[];
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('game_id', gameId)
          .eq('to_id', playerId)
          .eq('status', 'pending')
          .order('id');
      return rows
          .map(
              (dynamic row) => DealRequest.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      // The table is optional until supabase/mortgage_trades.sql is run.
      debugPrint('Could not read deals: $error');
      return const <DealRequest>[];
    }
  }

  /// Writes the ask and returns its id, or null when it could not be written.
  static Future<int?> ask({
    required String gameId,
    required DealKind kind,
    required String fromId,
    required String fromName,
    required String toId,
    required String toName,
    List<int> cards = const <int>[],
    List<int> wants = const <int>[],
    double offerCash = 0,
    double wantsCash = 0,
  }) async {
    try {
      final DateTime now = DateTime.now();
      final Map<String, dynamic> row = await Supabase.instance.client
          .from(_table)
          .insert(<String, dynamic>{
            'game_id': gameId,
            'kind': switch (kind) {
              DealKind.mortgage => 'mortgage',
              DealKind.unmortgage => 'unmortgage',
              DealKind.sellHouse => 'sell_house',
              DealKind.sellHotel => 'sell_hotel',
              DealKind.trade => 'trade',
            },
            'from_id': fromId,
            'from_name': fromName,
            'to_id': toId,
            'to_name': toName,
            'cards': cards.join(','),
            'wants': wants.join(','),
            'cash': offerCash,
            'wants_cash': wantsCash,
            'status': 'pending',
            'date': DateFormat('yyyy-MM-dd').format(now),
            'time': DateFormat('HH:mm:ss').format(now),
          })
          .select('id')
          .single();
      return (row['id'] as num?)?.toInt();
    } catch (error) {
      debugPrint('Could not ask for a deal: $error');
      return null;
    }
  }

  /// `pending`, `approved`, `rejected` or `cancelled`; null when unreadable.
  static Future<String?> statusOf(int id) async {
    try {
      final Map<String, dynamic> row = await Supabase.instance.client
          .from(_table)
          .select('status')
          .eq('id', id)
          .single();
      return row['status']?.toString();
    } catch (error) {
      debugPrint('Could not read deal $id: $error');
      return null;
    }
  }

  static Future<void> _setStatus(int id, String status) async {
    try {
      await Supabase.instance.client
          .from(_table)
          .update(<String, dynamic>{'status': status})
          .eq('id', id)
          .eq('status', 'pending');
    } catch (error) {
      debugPrint('Could not set deal $id to $status: $error');
    }
  }

  /// Takes the ask back before anyone has settled it. Nothing has moved yet.
  static Future<void> cancel(int id) => _setStatus(id, 'cancelled');

  /// Turns the ask down. Nothing has moved yet, so there is nothing to undo.
  static Future<void> decline(int id) => _setStatus(id, 'rejected');

  /// Settles [deal]: money first, cards second, with the whole thing backed out
  /// if any step fails.
  static Future<DealOutcome> approve(DealRequest deal) async {
    final SupabaseClient supabase = Supabase.instance.client;
    try {
      final List<dynamic> claimed = await supabase
          .from(_table)
          .update(<String, dynamic>{'status': 'approved'})
          .eq('id', deal.id)
          .eq('status', 'pending')
          .select('id');
      if (claimed.isEmpty) {
        return const DealOutcome.rejected('that request was already settled');
      }

      final Map<int, BankpopSpace> spaces =
          await PlayerCards.spaces(deal.gameId);

      return deal.isTrade
          ? _settleTrade(supabase, deal, spaces)
          : _settleBankDeal(supabase, deal, spaces);
    } catch (error) {
      debugPrint('Could not settle deal ${deal.id}: $error');
      return const DealOutcome.rejected('please try again');
    }
  }

  /// A mortgage or a sale of buildings: the bank pays the player, or the player
  /// pays the bank, and the card changes.
  static Future<DealOutcome> _settleBankDeal(
    SupabaseClient supabase,
    DealRequest deal,
    Map<int, BankpopSpace> spaces,
  ) async {
    if (deal.cards.length != 1) {
      return const DealOutcome.rejected('one property at a time');
    }
    final int cardIndex = deal.cards.first;
    final BankpopSpace? space = spaces[cardIndex];

    final Map<String, dynamic>? card =
        await _cardRow(supabase, deal.gameId, cardIndex);
    if (card == null) {
      return const DealOutcome.rejected('that property is not in this game');
    }
    if (card['to']?.toString() != deal.fromName) {
      return DealOutcome.rejected('${deal.fromName} does not own it');
    }

    final double amount = switch (deal.kind) {
      DealKind.mortgage => _halfPrice(space),
      DealKind.unmortgage => _unmortgageCost(space),
      DealKind.sellHouse => _halfOf(space?.houseCost),
      DealKind.sellHotel => _halfOf(space?.hotelCost),
      DealKind.trade => 0,
    };
    if (amount <= 0) {
      return const DealOutcome.rejected('that property has no price for this');
    }

    // The buildings go before the mortgage: the group has to be empty of them.
    if (deal.kind == DealKind.mortgage) {
      final List<Map<String, dynamic>> group = await _groupCards(
          supabase, deal.gameId, spaces, space?.color, deal.fromId);
      final bool built = group.any((Map<String, dynamic> row) =>
          ((row['houses'] as num?) ?? 0) > 0 ||
          ((row['hotels'] as num?) ?? 0) > 0);
      if (built) {
        return const DealOutcome.rejected(
            'sell the buildings in that group first');
      }
    }
    if (deal.kind == DealKind.unmortgage && card['mortgaged'] != true) {
      return const DealOutcome.rejected('that property is not mortgaged');
    }
    if (deal.kind == DealKind.sellHouse &&
        ((card['houses'] as num?) ?? 0) < 1) {
      return const DealOutcome.rejected('that property has no house to sell');
    }
    if (deal.kind == DealKind.sellHotel &&
        ((card['hotels'] as num?) ?? 0) < 1) {
      return const DealOutcome.rejected('that property has no hotel to sell');
    }

    // The bank pays for a mortgage and for buildings coming back; it is paid for
    // an unmortgage. One direction only, so one transfer.
    final bool bankPays = deal.kind == DealKind.mortgage ||
        deal.kind == DealKind.sellHouse ||
        deal.kind == DealKind.sellHotel;
    final TransferOutcome transfer = await WalletTransfer.pay(
      gameId: deal.gameId,
      fromId: bankPays ? deal.toId : deal.fromId,
      fromRole:
          bankPays ? WalletTransfer.bankerRole : WalletTransfer.playerRole,
      toId: bankPays ? deal.fromId : deal.toId,
      toRole: bankPays ? WalletTransfer.playerRole : WalletTransfer.bankerRole,
      amount: amount,
    );
    if (!transfer.ok) {
      return DealOutcome.rejected(
        transfer.failure == TransferFailure.insufficientFunds
            ? '${bankPays ? 'The bank' : deal.fromName} does not have enough money'
            : 'the payment failed',
      );
    }

    try {
      await supabase.from(_cardsTable).update(<String, dynamic>{
        if (deal.kind == DealKind.mortgage) 'mortgaged': true,
        if (deal.kind == DealKind.unmortgage) 'mortgaged': false,
        if (deal.kind == DealKind.sellHouse)
          'houses': ((card['houses'] as num?) ?? 0).toInt() - 1,
        if (deal.kind == DealKind.sellHotel)
          'hotels': ((card['hotels'] as num?) ?? 0).toInt() - 1,
      }).eq('id', card['id']);
    } catch (error) {
      // Charged for a change that did not happen: give the money back.
      await WalletTransfer.pay(
        gameId: deal.gameId,
        fromId: bankPays ? deal.fromId : deal.toId,
        fromRole:
            bankPays ? WalletTransfer.playerRole : WalletTransfer.bankerRole,
        toId: bankPays ? deal.toId : deal.fromId,
        toRole:
            bankPays ? WalletTransfer.bankerRole : WalletTransfer.playerRole,
        amount: amount,
      );
      await _setStatus(deal.id, 'rejected');
      return const DealOutcome.rejected(
          'it did not go through, so nothing moved');
    }

    await _record(supabase, deal.gameId,
        from: bankPays ? 'Bank' : deal.fromName,
        to: bankPays ? deal.fromName : 'Bank',
        payer: bankPays ? deal.toId : deal.fromId,
        payee: bankPays ? deal.fromId : deal.toId,
        value: amount);

    return const DealOutcome.ok();
  }

  /// A trade: both sides' cards change hands, both cash sides move, and the
  /// bank collects its 10% interest on every mortgaged card that moved.
  static Future<DealOutcome> _settleTrade(
    SupabaseClient supabase,
    DealRequest deal,
    Map<int, BankpopSpace> spaces,
  ) async {
    final List<int> theirs = deal.cards; // from -> to
    final List<int> mine = deal.wants; // to -> from
    final Set<int> mortgaged = <int>{}; // collected for the interest below

    for (final int index in <int>[...theirs, ...mine]) {
      final Map<String, dynamic>? row =
          await _cardRow(supabase, deal.gameId, index);
      if (row == null) {
        return const DealOutcome.rejected('a property in this trade has gone');
      }
      final String owner = row['to']?.toString() ?? '';
      // A card going out has to be the asker's; one coming in has to be the
      // other side's. Whoever settles cannot hand over somebody else's card.
      final String needed =
          theirs.contains(index) ? deal.fromName : deal.toName;
      if (owner != needed) {
        return DealOutcome.rejected(
            '$needed no longer owns ${_nameOf(spaces, index)}');
      }
      // Buildings cannot be traded; they go back to the bank first.
      if (((row['houses'] as num?) ?? 0) > 0 ||
          ((row['hotels'] as num?) ?? 0) > 0) {
        return DealOutcome.rejected(
            'Sell the buildings on ${_nameOf(spaces, index)} first');
      }
      if (row['mortgaged'] == true) mortgaged.add(index);
    }

    // Money first: what this side offers, what they ask for, and the bank's 10%
    // on every mortgaged card that is about to change hands.
    final double toInterest = _interest(theirs, spaces, mortgaged);
    final double fromInterest = _interest(mine, spaces, mortgaged);
    if ((toInterest > 0 || fromInterest > 0) && _bankId.isEmpty) {
      return const DealOutcome.rejected(
          'the bank id is unknown, so the mortgage interest cannot be taken');
    }

    final List<_Move> moves = <_Move>[
      if (deal.offerCash > 0)
        _Move(
            deal.fromId, deal.fromName, deal.toId, deal.toName, deal.offerCash),
      if (deal.wantsCash > 0)
        _Move(
            deal.toId, deal.toName, deal.fromId, deal.fromName, deal.wantsCash),
      if (toInterest > 0)
        _Move(deal.toId, deal.toName, _bankId, 'Bank', toInterest),
      if (fromInterest > 0)
        _Move(deal.fromId, deal.fromName, _bankId, 'Bank', fromInterest),
    ];

    final List<_Move> landed = <_Move>[];
    for (final _Move move in moves) {
      final TransferOutcome outcome = await WalletTransfer.pay(
        gameId: deal.gameId,
        fromId: move.from,
        fromRole: WalletTransfer.playerRole,
        toId: move.to,
        toRole: move.to == _bankId
            ? WalletTransfer.bankerRole
            : WalletTransfer.playerRole,
        amount: move.value,
      );
      if (!outcome.ok) {
        await _reverse(deal, landed);
        return DealOutcome.rejected(
          outcome.failure == TransferFailure.insufficientFunds
              ? '${move.fromName} does not have that much money'
              : 'the payment failed',
        );
      }
      landed.add(move);
      await _record(
        supabase,
        deal.gameId,
        from: move.fromName,
        to: move.toName,
        payer: move.from,
        payee: move.to,
        value: move.value,
      );
    }

    // Then the properties move, and only then is the deal done.
    //
    // A `player_cards` row is also that card's history, and `from`/`to` are the
    // two hands it last passed between. A trade therefore has to overwrite
    // `from` as well as `to`: leaving it alone made a card that was traded from
    // another player still claim it came from the bank.
    try {
      final DateTime now = DateTime.now();
      final String date = DateFormat('yyyy-MM-dd').format(now);
      final String time = DateFormat('HH:mm:ss').format(now);
      if (theirs.isNotEmpty) {
        await supabase
            .from(_cardsTable)
            .update(<String, dynamic>{
              'from': deal.fromName,
              'to': deal.toName,
              'code': '${deal.fromId}_${deal.toId}',
              'receiver_id': deal.toId,
              'date': date,
              'time': time,
            })
            .eq('game_id', deal.gameId)
            .inFilter('card_index', theirs);
      }
      if (mine.isNotEmpty) {
        await supabase
            .from(_cardsTable)
            .update(<String, dynamic>{
              'from': deal.toName,
              'to': deal.fromName,
              'code': '${deal.toId}_${deal.fromId}',
              'receiver_id': deal.fromId,
              'date': date,
              'time': time,
            })
            .eq('game_id', deal.gameId)
            .inFilter('card_index', mine);
      }
    } catch (error) {
      debugPrint('Could not move the cards in deal ${deal.id}: $error');
      await _reverse(deal, landed);
      await _setStatus(deal.id, 'rejected');
      return const DealOutcome.rejected(
          'the properties did not move, so the money was handed back');
    }

    return const DealOutcome.ok();
  }

  /// The bank's player_id for this game. A trade can owe the bank its mortgage
  /// interest, so whoever settles one has to know it; both screens set it from
  /// the roster before a deal is approved.
  static String _bankId = '';

  static void rememberBankId(String id) {
    if (id.isNotEmpty) _bankId = id;
  }

  /// 10% of the mortgage value of each mortgaged card in [indexes].
  static double _interest(
    List<int> indexes,
    Map<int, BankpopSpace> spaces,
    Set<int> mortgaged,
  ) {
    double total = 0;
    for (final int index in indexes) {
      if (!mortgaged.contains(index)) continue;
      total += _halfPrice(spaces[index]) / 10;
    }
    return total;
  }

  /// Hands back anything that had already moved when a later step failed, so a
  /// half-settled trade does not leave one player poorer than they agreed to be.
  static Future<void> _reverse(DealRequest deal, List<_Move> landed) async {
    for (final _Move move in landed.reversed) {
      await WalletTransfer.pay(
        gameId: deal.gameId,
        fromId: move.to,
        fromRole: move.to == _bankId
            ? WalletTransfer.bankerRole
            : WalletTransfer.playerRole,
        toId: move.from,
        toRole: move.from == _bankId
            ? WalletTransfer.bankerRole
            : WalletTransfer.playerRole,
        amount: move.value,
      );
    }
  }

  static double _halfPrice(BankpopSpace? space) => _halfOf(space?.price);

  static double _halfOf(int? value) => value == null ? 0 : value / 2;

  static double _unmortgageCost(BankpopSpace? space) {
    final double value = _halfPrice(space);
    return value + (value / 10).ceilToDouble();
  }

  static String _nameOf(Map<int, BankpopSpace> spaces, int index) =>
      spaces[index]?.name ?? 'Card #$index';

  static Future<Map<String, dynamic>?> _cardRow(
    SupabaseClient supabase,
    String gameId,
    int cardIndex,
  ) async {
    final List<dynamic> rows = await supabase
        .from(_cardsTable)
        .select('id, to, houses, hotels, mortgaged')
        .eq('game_id', gameId)
        .eq('card_index', cardIndex)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first as Map<String, dynamic>;
  }

  /// The cards this player holds in one colour group, for the "sell the
  /// buildings first" check.
  static Future<List<Map<String, dynamic>>> _groupCards(
    SupabaseClient supabase,
    String gameId,
    Map<int, BankpopSpace> spaces,
    String? colour,
    String ownerName,
  ) async {
    final List<dynamic> rows = await supabase
        .from(_cardsTable)
        .select('card_index, houses, hotels, to')
        .eq('game_id', gameId);
    return rows.cast<Map<String, dynamic>>().where((Map<String, dynamic> row) {
      final int? index = (row['card_index'] as num?)?.toInt();
      final BankpopSpace? space = index == null ? null : spaces[index];
      return space?.color == colour && row['to']?.toString() == ownerName;
    }).toList();
  }

  static Future<void> _record(
    SupabaseClient supabase,
    String gameId, {
    required String from,
    required String to,
    required String payer,
    required String payee,
    required double value,
  }) async {
    try {
      await supabase.from('transactions').insert(<String, dynamic>{
        'game_id': gameId,
        'value': value,
        'from': from,
        'to': to,
        'code': '${payer}_$payee',
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': DateFormat('HH:mm:ss').format(DateTime.now()),
      });
    } catch (error) {
      debugPrint('Could not record a deal payment: $error');
    }
  }
}
