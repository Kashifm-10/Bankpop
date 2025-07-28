import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class Transaction {
  final String from;
  final String to;
  final double value;
  final String dateTime;

  Transaction({
    required this.from,
    required this.to,
    required this.value,
    required this.dateTime,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      from: map['from']?.toString() ?? '',
      to: map['to']?.toString() ?? '',
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      dateTime: "${map['date'] ?? ''} ${map['time'] ?? ''}",
    );
  }
}

class TransactionHistoryPage extends StatefulWidget {
  final String gameId;
  final String playerId;

  const TransactionHistoryPage({
    super.key,
    required this.gameId,
    required this.playerId,
  });

  @override
  _TransactionHistoryPageState createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  late Future<List<Transaction>> _transactionsFuture;
  String? playerName;
  @override
  void initState() {
    super.initState();
    _transactionsFuture = fetchTransactions();
  }

  Future<List<Transaction>> fetchTransactions() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    playerName = prefs.getString('name');

    final response = await Supabase.instance.client
        .from('transactions')
        .select()
        .eq('game_id', widget.gameId)
        .like('code', '%${widget.playerId}%')
        .order('date', ascending: false)
        .order('time', ascending: false);

    final data = response as List;
    return data.map((e) => Transaction.fromMap(e)).toList();
  }

  Widget _buildHeaderRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      color: Colors.blue.shade100,
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Icon(
                CupertinoIcons.arrow_down,
                size: 20.sp,
              )),
          Expanded(
              flex: 2,
              child: Icon(
                CupertinoIcons.arrow_up,
                size: 20.sp,
              )),
          Expanded(
              flex: 1,
              child: Icon(
                FontAwesomeIcons.moneyBillWave,
                size: 20.sp,
              )),
          Expanded(
              flex: 2,
              child: Icon(
                FontAwesomeIcons.clock,
                size: 20.sp,
              )),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(Transaction txn) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.yellow.shade50,
          border:
              Border.all(color: Colors.grey, width: 1), // Border on all sides
          borderRadius: const BorderRadius.all(
              Radius.circular(12)), // Rounded corners on all sides
        ),
        child: Row(
          children: [
            // From
            Expanded(
              flex: 4,
              child: Text(
                txn.from,
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
                txn.to,
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
                  color: playerName == txn.from ? Colors.red : Colors.green,
                ),
                textAlign: TextAlign.right,
              ),
            ),

            // Time
            Expanded(
              flex: 3,
              child: Text(
                timeago.format(DateTime.parse(txn.dateTime)),
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
    return Scaffold(
      backgroundColor: Colors.yellow.shade50,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Transaction History"),
        backgroundColor: Colors.yellow.shade50,
        actions: [
          IconButton(
              onPressed: () async {
                Navigator.of(context)
                    .pop(); // or your custom logic to leave the game
              },
              icon: Icon(
                FontAwesomeIcons.close,
                size: 20.sp,
              )),
          const SizedBox(width: 10),
        ],
      ),
      body: FutureBuilder<List<Transaction>>(
        future: _transactionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No transactions yet."));
          }

          final transactions = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: transactions.length, //+ 1,
            itemBuilder: (context, index) {
              //  if (index == 0) return _buildHeaderRow();
              return _buildTransactionRow(transactions[index /* - 1 */]);
            },
          );
        },
      ),
    );
  }
}
