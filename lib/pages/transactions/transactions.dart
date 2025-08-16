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
  String? playerID;
  @override
  void initState() {
    super.initState();
    _transactionsFuture = fetchTransactions();
  }

  Future<List<Transaction>> fetchTransactions() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    playerName = prefs.getString('profile_name');
    playerID = prefs.getString('playerID');

    final response = await Supabase.instance.client
        .from('transactions')
        .select()
        .eq('game_id', widget.gameId)
        .like('code', '%${widget.playerId}%')
        .order('date', ascending: false)
        .order('time', ascending: false);

    final data = response as List;

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
                "${txn.from[0].toUpperCase()}${txn.from.substring(1)}",
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
                "${txn.to[0].toUpperCase()}${txn.to.substring(1)}",
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
              FontAwesomeIcons.close,
              size: 20.sp,
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
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
      ),
    );
  }
}
