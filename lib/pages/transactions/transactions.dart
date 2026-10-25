import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/card_requests.dart';
import 'package:mon/services/deals.dart';
import 'package:mon/services/player_cards.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class Transaction {
  final String from;
  final String to;
  final double value;
  final String dateTime;
  final String payer;
  final String receiver;

  Transaction({
    required this.from,
    required this.to,
    required this.value,
    required this.dateTime,
    required this.payer,
    required this.receiver,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      from: map['from']?.toString() ?? '',
      to: map['to']?.toString() ?? '',
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      dateTime: "${map['date'] ?? ''} ${map['time'] ?? ''}",
      payer: map['payerId']?.toString() ?? '',
      receiver: map['receiverId']?.toString() ?? '',
    );
  }
}

class TransactionHistoryPage extends StatefulWidget {
  final String gameId;
  final String playerId;

  /// True on the bank's device: a banker did not buy the buildings it approved,
  /// so the Houses tab shows the whole game rather than one player's share.
  final bool showAllPlayers;

  const TransactionHistoryPage({
    super.key,
    required this.gameId,
    required this.playerId,
    this.showAllPlayers = false,
  });

  @override
  _TransactionHistoryPageState createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  late Future<List<Transaction>> _transactionsFuture;

  /// The property cards half of the ledger, and the board needed to turn a
  /// stored card index back into a property name.
  late Future<List<PlayerCard>> _cardsFuture;
  late Future<Map<int, BankpopSpace>> _spacesFuture;

  /// The houses and hotels half: every building that was approved, newest first.
  late Future<List<CardRequest>> _buildingsFuture;

  /// Mortgage / unmortgage events, so the Cards tab can show them too.
  late Future<List<DealRequest>> _mortgagesFuture;

  /// House / hotel sales back to the bank, so the Houses tab can show them.
  late Future<List<DealRequest>> _houseSalesFuture;

  /// Every trade this player sent or received, settled or otherwise.
  late Future<List<DealRequest>> _tradesFuture;

  String? playerName;
  String? playerID;

  /// Whether `transactions` has the payer_id/receiver_id columns (section 4.2 of
  /// supabase/hardening.sql). Probed once per app run, so the walkthrough only
  /// costs an extra request the first time the history is opened.
  ///
  /// In memory only: deploying the SQL mid-session is not picked up until the
  /// app restarts, which is fine - schemas are not expected to change under a
  /// running app.
  static bool? _hasIndexedColumns;

  @override
  void initState() {
    super.initState();
    _transactionsFuture = fetchTransactions();
    _cardsFuture = PlayerCards.forPlayer(
      gameId: widget.gameId,
      playerId: widget.playerId,
    );
    _spacesFuture = PlayerCards.spaces(widget.gameId);
    _buildingsFuture = _fetchBuildings();
    _mortgagesFuture = _fetchMortgages();
    _houseSalesFuture = _fetchHouseSales();
    _tradesFuture = _fetchTrades();
  }

  /// Approved buildings for this game, newest first: a player's own, or the
  /// whole game when this is the bank's screen.
  ///
  /// The payments themselves also land in `transactions` when the banker
  /// approves, so the money shows up on the first tab as well; this tab is the
  /// buildings it bought.
  Future<List<CardRequest>> _fetchBuildings() async {
    try {
      final builder = Supabase.instance.client
          .from('card_requests')
          .select()
          .eq('game_id', widget.gameId)
          .eq('status', 'approved');
      final filtered = widget.showAllPlayers
          ? builder
          : builder.eq('player_id', widget.playerId);

      final List<dynamic> rows = await filtered
          .order('date', ascending: false)
          .order('time', ascending: false)
          .limit(200);
      return rows
          .map(
              (dynamic row) => CardRequest.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      // The table is created by supabase/buildings.sql; until it exists the tab
      // simply reads as empty rather than erroring.
      return const <CardRequest>[];
    }
  }

  /// Approved mortgage / unmortgage deals involving this player, newest first.
  Future<List<DealRequest>> _fetchMortgages() async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('deal_requests')
          .select()
          .eq('game_id', widget.gameId)
          .inFilter('kind', <String>['mortgage', 'unmortgage'])
          .eq('status', 'approved')
          .or('from_id.eq.${widget.playerId},to_id.eq.${widget.playerId}')
          .order('date', ascending: false)
          .order('time', ascending: false)
          .limit(200);
      return rows
          .cast<Map<String, dynamic>>()
          .map(DealRequest.fromMap)
          .toList();
    } catch (error) {
      debugPrint('Could not read mortgages: $error');
      return const <DealRequest>[];
    }
  }

  /// House / hotel sales back to the bank for this game, or for one player when
  /// showAllPlayers is false.
  Future<List<DealRequest>> _fetchHouseSales() async {
    try {
      final builder = Supabase.instance.client
          .from('deal_requests')
          .select()
          .eq('game_id', widget.gameId)
          .inFilter('kind', <String>['sell_house', 'sell_hotel']).eq(
              'status', 'approved');
      final filtered = widget.showAllPlayers
          ? builder
          : builder.eq('from_id', widget.playerId);
      final List<dynamic> rows = await filtered
          .order('date', ascending: false)
          .order('time', ascending: false)
          .limit(200);
      return rows
          .cast<Map<String, dynamic>>()
          .map(DealRequest.fromMap)
          .toList();
    } catch (error) {
      debugPrint('Could not read house sales: $error');
      return const <DealRequest>[];
    }
  }

  /// Every trade this player sent or received, in any final state.
  Future<List<DealRequest>> _fetchTrades() async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('deal_requests')
          .select()
          .eq('game_id', widget.gameId)
          .eq('kind', 'trade')
          .inFilter('status', <String>['approved', 'rejected', 'cancelled'])
          .or('from_id.eq.${widget.playerId},to_id.eq.${widget.playerId}')
          .order('date', ascending: false)
          .order('time', ascending: false)
          .limit(200);
      return rows
          .cast<Map<String, dynamic>>()
          .map(DealRequest.fromMap)
          .toList();
    } catch (error) {
      debugPrint('Could not read trades: $error');
      return const <DealRequest>[];
    }
  }

  /// This player's newest rows in this game, capped at 200. The indexed filter
  /// matches the two id columns; the fallback matches them inside `code`, which
  /// cannot use an index (a leading wildcard never can).
  Future<List<dynamic>> _fetchRows({required bool indexed}) {
    final builder = Supabase.instance.client
        .from('transactions')
        .select()
        .eq('game_id', widget.gameId);

    final filtered = indexed
        ? builder.or('payer_id.eq.${widget.playerId},'
            'receiver_id.eq.${widget.playerId}')
        : builder.like('code', '%${widget.playerId}%');

    return filtered
        .order('date', ascending: false)
        .order('time', ascending: false)
        .limit(200);
  }

  static bool _columnsMissing(PostgrestException error) {
    // 42703 is "undefined column"; PGRST204 is the same fact reported from a
    // stale PostgREST schema cache, so both have to fall back.
    if (error.code == '42703' || error.code == 'PGRST204') return true;
    return error.message.contains('payer_id') ||
        error.message.contains('receiver_id');
  }

  Future<List<Transaction>> fetchTransactions() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    playerName = prefs.getString('profile_name');
    playerID = prefs.getString('playerID');

    List<dynamic> data;
    if (_hasIndexedColumns ?? true) {
      try {
        data = await _fetchRows(indexed: true);
        _hasIndexedColumns = true;
      } on PostgrestException catch (error) {
        if (!_columnsMissing(error)) rethrow;
        debugPrint('transactions.payer_id/receiver_id do not exist yet - run '
            'supabase/hardening.sql section 4.2. Using the code filter until '
            'then.');
        _hasIndexedColumns = false;
        data = await _fetchRows(indexed: false);
      }
    } else {
      data = await _fetchRows(indexed: false);
    }

    return data.map((e) {
      // Safely extract payer and receiver from the code
      final code = e['code'] as String;
      final parts = code.split('_');
      final payerId = parts.length > 1 ? parts[0] : '';
      final receiverId = parts.length > 1 ? parts[1] : '';

      // Pass to the Transaction model (you'll need to update it to accept these)
      return Transaction.fromMap({
        ...e,
        'payerId': payerId,
        'receiverId': receiverId,
      });
    }).toList();
  }

  /// "ameen" -> "Ameen". Tolerates the empty strings a malformed history row
  /// can produce; the old code indexed `[0]` and threw.
  String _displayName(String value) {
    if (value.isEmpty) return '';
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  /// `timeago` throws on an unparseable date, which used to take the whole
  /// history screen down with it. Fall back to the raw string instead.
  String _relativeTime(String raw) {
    final DateTime? parsed = DateTime.tryParse(raw.trim());
    return parsed == null ? raw.trim() : timeago.format(parsed);
  }

  Widget _buildTransactionRow(Transaction txn) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border:
              Border.all(color: Colors.white, width: 1), // Border on all sides
          borderRadius: const BorderRadius.all(
              Radius.circular(12)), // Rounded corners on all sides
        ),
        child: Row(
          children: [
            // From
            Expanded(
              flex: 4,
              child: Text(
                _displayName(txn.from),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Arrow Icon
            /*   Expanded(
              flex: 1,
              child: Center(
                child: Icon(
                  CupertinoIcons.chevron_right_2,
                  size: 16.sp,
                  color: Colors.grey[600],
                ),
              ),
            ), */

            // To
            Expanded(
              flex: 3,
              child: Text(
                _displayName(txn.to),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Value
            Expanded(
              flex: 2,
              child: Text(
                txn.value.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: playerID == txn.payer ? Colors.red : Colors.green,
                ),
                textAlign: TextAlign.right,
              ),
            ),

            // Time
            Expanded(
              flex: 3,
              child: Text(
                _relativeTime(txn.dateTime),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.yellow.shade50,
        appBar: AppBar(
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: const Text(
            "Transaction History",
            style: TextStyle(
                color: Color(0xFF689F38), fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.yellow.shade50,
          actions: [
            IconButton(
              onPressed: () {
                Navigator.of(context).pop(); // Exit logic
              },
              icon: Icon(
                FontAwesomeIcons.xmark,
                size: 20.sp,
              ),
            ),
            const SizedBox(width: 10),
          ],
          // Cards are the second half of the same ledger: the money, and the
          // properties it bought.
          bottom: const TabBar(
            labelColor: Color(0xFF689F38),
            indicatorColor: Color(0xFF689F38),
            unselectedLabelColor: Colors.black54,
            tabs: [
              Tab(text: 'Transactions'),
              Tab(text: 'Cards'),
              Tab(text: 'Houses'),
              Tab(text: 'Trades'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTransactionsTab(),
            _buildCardsTab(),
            _buildHousesTab(),
            _buildTradesTab(),
          ],
        ),
      ),
    );
  }

  /// The money history, unchanged, now the first tab.
  Widget _buildTransactionsTab() {
    return Column(
      children: [
        SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 0.0, horizontal: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.yellow.shade50,
              //   border: Border.all(color: Colors.grey, width: 1),
              borderRadius: const BorderRadius.all(Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    "From",
                    style:
                        TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    "To",
                    style:
                        TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    "Value",
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    "Time",
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.sp,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(color: Color(0xFF689F38)),
        // Transactions list
        Expanded(
          child: FutureBuilder<List<Transaction>>(
            future: _transactionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF689F38)),
                );
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text("No transactions yet."));
              }

              final transactions = snapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  return _buildTransactionRow(transactions[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Cards this player bought or sold, newest first, interleaved with the
  /// mortgage / unmortgage events on them.
  Widget _buildCardsTab() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([_cardsFuture, _mortgagesFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF689F38)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load cards: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final cards = (snapshot.data![0] as List).cast<PlayerCard>();
        final mortgages = (snapshot.data![1] as List).cast<DealRequest>();
        if (cards.isEmpty && mortgages.isEmpty) {
          return const Center(child: Text("No cards yet."));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            final entries = <MapEntry<String, Widget>>[];
            for (final PlayerCard card in cards) {
              entries.add(MapEntry(
                '${card.date} ${card.time}',
                _buildCardRow(card, spaces),
              ));
            }
            for (final DealRequest m in mortgages) {
              entries.add(MapEntry(
                '${m.date} ${m.time}',
                _buildMortgageRow(m, spaces),
              ));
            }
            entries.sort((a, b) => b.key.compareTo(a.key));
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: entries.length,
              itemBuilder: (context, index) => entries[index].value,
            );
          },
        );
      },
    );
  }

  /// Houses and hotels bought and sold in this game, newest first.
  Widget _buildHousesTab() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([_buildingsFuture, _houseSalesFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF689F38)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load houses: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final builds = (snapshot.data![0] as List).cast<CardRequest>();
        final sales = (snapshot.data![1] as List).cast<DealRequest>();
        if (builds.isEmpty && sales.isEmpty) {
          return const Center(child: Text('No houses or hotels yet.'));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            final entries = <MapEntry<String, Widget>>[];
            for (final CardRequest b in builds) {
              entries.add(MapEntry(
                '${b.date} ${b.time}',
                _buildBuildingRow(b, spaces),
              ));
            }
            for (final DealRequest s in sales) {
              entries.add(MapEntry(
                '${s.date} ${s.time}',
                _buildHouseSaleRow(s, spaces),
              ));
            }
            entries.sort((a, b) => b.key.compareTo(a.key));
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: entries.length,
              itemBuilder: (context, index) => entries[index].value,
            );
          },
        );
      },
    );
  }

  Widget _buildBuildingRow(CardRequest request, Map<int, BankpopSpace> spaces) {
    final BankpopSpace? space = spaces[request.cardIndex];
    final String name = space?.name ?? 'Card #${request.cardIndex}';
    final Color groupColor = space == null
        ? Colors.grey
        : Color(BankpopBoard.colorForGroup(space.color));
    final String who = widget.showAllPlayers ? request.playerName : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 38,
              decoration: BoxDecoration(
                color: groupColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Icon(
                    request.isHotel ? Icons.business : Icons.home,
                    size: 15,
                    color: const Color(0xFF689F38),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      request.isHotel ? 'Hotel' : 'House',
                      style:
                          TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '£${request.amount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF33691E),
                    ),
                  ),
                  if (who.isNotEmpty)
                    Text(
                      who,
                      style:
                          TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A mortgage / unmortgage event in the Cards tab.
  Widget _buildMortgageRow(DealRequest d, Map<int, BankpopSpace> spaces) {
    final int cardIndex = d.cards.isNotEmpty ? d.cards.first : -1;
    final BankpopSpace? space = spaces[cardIndex];
    final String name = space?.name ?? 'Card #$cardIndex';
    final Color groupColor = space == null
        ? Colors.grey
        : Color(BankpopBoard.colorForGroup(space.color));
    final bool isMortgage = d.kind == DealKind.mortgage;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 38,
              decoration: BoxDecoration(
                color: groupColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                name,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: <Widget>[
                  Icon(
                    isMortgage ? Icons.lock : Icons.lock_open,
                    size: 14,
                    color: const Color(0xFF689F38),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isMortgage ? 'Mortgaged' : 'Unmortgaged',
                      style:
                          TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                _relativeTime('${d.date} ${d.time}'),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A house / hotel sold back to the bank in the Houses tab.
  Widget _buildHouseSaleRow(DealRequest d, Map<int, BankpopSpace> spaces) {
    final int cardIndex = d.cards.isNotEmpty ? d.cards.first : -1;
    final BankpopSpace? space = spaces[cardIndex];
    final String name = space?.name ?? 'Card #$cardIndex';
    final Color groupColor = space == null
        ? Colors.grey
        : Color(BankpopBoard.colorForGroup(space.color));
    final bool isHotel = d.kind == DealKind.sellHotel;
    final double refund =
        ((isHotel ? space?.hotelCost : space?.houseCost) ?? 0) / 2;
    final String who = widget.showAllPlayers ? d.fromName : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 38,
              decoration: BoxDecoration(
                color: groupColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                name,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: <Widget>[
                  Icon(
                    isHotel ? Icons.business : Icons.home,
                    size: 15,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isHotel ? 'Hotel sold' : 'House sold',
                      style:
                          TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '+\u00a3${refund.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                  if (who.isNotEmpty)
                    Text(
                      who,
                      style:
                          TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Every trade this player was party to, in any final state.
  Widget _buildTradesTab() {
    return FutureBuilder<List<DealRequest>>(
      future: _tradesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF689F38)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load trades: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final trades = snapshot.data ?? const <DealRequest>[];
        if (trades.isEmpty) {
          return const Center(child: Text('No trades yet.'));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: trades.length,
              itemBuilder: (context, index) =>
                  _buildTradeRow(trades[index], spaces),
            );
          },
        );
      },
    );
  }

  Widget _buildTradeRow(DealRequest trade, Map<int, BankpopSpace> spaces) {
    final Color statusColor;
    switch (trade.status) {
      case 'approved':
        statusColor = Colors.green.shade700;
        break;
      case 'rejected':
        statusColor = Colors.red.shade700;
        break;
      case 'cancelled':
        statusColor = Colors.grey.shade600;
        break;
      default:
        statusColor = Colors.orange.shade700;
    }
    final List<String> givenBits = <String>[
      if (trade.cards.isNotEmpty)
        trade.cards.map((int i) => spaces[i]?.name ?? 'Card #$i').join(', '),
      if (trade.offerCash > 0) '\u00a3${trade.offerCash.toStringAsFixed(0)}',
    ];
    final List<String> gotBits = <String>[
      if (trade.wants.isNotEmpty)
        trade.wants.map((int i) => spaces[i]?.name ?? 'Card #$i').join(', '),
      if (trade.wantsCash > 0) '\u00a3${trade.wantsCash.toStringAsFixed(0)}',
    ];
    final String given = givenBits.isEmpty ? '' : givenBits.join(' + ');
    final String got = gotBits.isEmpty ? '' : gotBits.join(' + ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${_displayName(trade.fromName)} \u2192 ${_displayName(trade.toName)}',
                    style:
                        TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    trade.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (given.isNotEmpty)
              Text(
                'Gave: $given',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            if (got.isNotEmpty)
              Text(
                'Got: $got',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            if (trade.date.isNotEmpty)
              Text(
                _relativeTime('${trade.date} ${trade.time}'),
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardRow(PlayerCard card, Map<int, BankpopSpace> spaces) {
    final BankpopSpace? space = spaces[card.cardIndex];
    final String name = space?.name ?? 'Card #${card.cardIndex}';
    final Color groupColor = space == null
        ? Colors.grey
        : Color(BankpopBoard.colorForGroup(space.color));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 38,
              decoration: BoxDecoration(
                color: groupColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                '${_displayName(card.from)} \u2192 ${_displayName(card.to)}',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                _relativeTime('${card.date} ${card.time}'),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
