import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/card_requests.dart';
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
    _spacesFuture = PlayerCards.spaces();
    _buildingsFuture = _fetchBuildings();
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
          .map((dynamic row) =>
              CardRequest.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      // The table is created by supabase/buildings.sql; until it exists the tab
      // simply reads as empty rather than erroring.
      return const <CardRequest>[];
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
      length: 3,
      child: Scaffold(
      backgroundColor: Colors.yellow.shade50,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: const Text(
          "Transaction History",
          style:
              TextStyle(color: Color(0xFF689F38), fontWeight: FontWeight.bold),
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
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _buildTransactionsTab(),
          _buildCardsTab(),
          _buildHousesTab(),
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
                      style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      "To",
                      style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.bold),
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

  /// The cards this player bought or sold, newest first.
  Widget _buildCardsTab() {
    return FutureBuilder<List<PlayerCard>>(
      future: _cardsFuture,
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

        final cards = snapshot.data ?? const <PlayerCard>[];
        if (cards.isEmpty) {
          return const Center(child: Text("No cards yet."));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: cards.length,
              itemBuilder: (context, index) {
                return _buildCardRow(cards[index], spaces);
              },
            );
          },
        );
      },
    );
  }

  /// Houses and hotels that have been bought in this game, newest first.
  Widget _buildHousesTab() {
    return FutureBuilder<List<CardRequest>>(
      future: _buildingsFuture,
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

        final requests = snapshot.data ?? const <CardRequest>[];
        if (requests.isEmpty) {
          return const Center(child: Text('No houses or hotels yet.'));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: requests.length,
              itemBuilder: (context, index) =>
                  _buildBuildingRow(requests[index], spaces),
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
                      style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
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
                      style: TextStyle(
                          fontSize: 11.sp, color: Colors.grey[600]),
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
