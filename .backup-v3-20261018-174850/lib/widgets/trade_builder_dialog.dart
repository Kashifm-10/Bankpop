import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/deals.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

class TradeBuilderDialog extends StatefulWidget {
  final String gameId;
  final String myId;
  final String myName;
  final List<PlayerCard> myCards;
  final Map<int, BankpopSpace> spaces;
  final List<Map<String, dynamic>> players;
  final DealRequest? counterTo;

  const TradeBuilderDialog({
    super.key,
    required this.gameId,
    required this.myId,
    required this.myName,
    required this.myCards,
    required this.spaces,
    required this.players,
    this.counterTo,
  });

  @override
  State<TradeBuilderDialog> createState() => _TradeBuilderDialogState();
}

class _TradeBuilderDialogState extends State<TradeBuilderDialog> {
  String? _selectedPlayerId;
  String? _selectedPlayerName;
  List<PlayerCard> _theirCards = [];
  final Set<int> _mySelectedCards = {};
  final Set<int> _theirSelectedCards = {};
  final _myCash = TextEditingController();
  final _theirCash = TextEditingController();
  bool _loadingTheirCards = false;

  @override
  void initState() {
    super.initState();
    if (widget.counterTo != null) {
      _selectedPlayerId = widget.counterTo!.fromId;
      _selectedPlayerName = widget.counterTo!.fromName;
      _mySelectedCards.addAll(widget.counterTo!.wants);
      _theirSelectedCards.addAll(widget.counterTo!.cards);
      _myCash.text = widget.counterTo!.wantsCash.toStringAsFixed(0);
      _theirCash.text = widget.counterTo!.offerCash.toStringAsFixed(0);
      _fetchTheirCards();
    }
  }

  Future<void> _fetchTheirCards() async {
    if (_selectedPlayerId == null) return;
    setState(() => _loadingTheirCards = true);
    final cards = await PlayerCards.forPlayer(
      gameId: widget.gameId,
      playerId: _selectedPlayerId!,
    );
    if (mounted) {
      setState(() {
        _theirCards = cards;
        _loadingTheirCards = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedPlayerId == null) return;
    final myCash = double.tryParse(_myCash.text) ?? 0;
    final theirCash = double.tryParse(_theirCash.text) ?? 0;

    final id = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.trade,
      fromId: widget.myId,
      fromName: widget.myName,
      toId: _selectedPlayerId!,
      toName: _selectedPlayerName!,
      cards: _mySelectedCards.toList(),
      wants: _theirSelectedCards.toList(),
      offerCash: myCash,
      wantsCash: theirCash,
    );
    if (id != null) {
      if (mounted) Navigator.pop(context, true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send trade offer')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherPlayers = widget.players
        .where((p) => p['player_id'] != widget.myId)
        .toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 90.w,
        height: 85.h,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.yellow.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Trade Builder',
                    style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            DropdownButton<String>(
              hint: const Text('Select Player'),
              value: _selectedPlayerId,
              isExpanded: true,
              items: otherPlayers.map((p) {
                return DropdownMenuItem(
                  value: p['player_id'].toString(),
                  child: Text(p['name'].toString()),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  final p = otherPlayers.firstWhere((p) => p['player_id'] == val);
                  setState(() {
                    _selectedPlayerId = val;
                    _selectedPlayerName = p['name'].toString();
                    _theirSelectedCards.clear();
                  });
                  _fetchTheirCards();
                }
              },
            ),
            const Divider(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('You Give',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: ListView(
                            children: widget.myCards.map((c) {
                              final space = widget.spaces[c.cardIndex];
                              final hasBuildings = c.houses > 0 || c.hotels > 0;
                              return CheckboxListTile(
                                title: Text(space?.name ?? 'Card #${c.cardIndex}'),
                                subtitle: hasBuildings
                                    ? const Text('Sell buildings first',
                                        style: TextStyle(color: Colors.red, fontSize: 10))
                                    : null,
                                value: _mySelectedCards.contains(c.cardIndex),
                                onChanged: hasBuildings
                                    ? null
                                    : (v) {
                                        setState(() {
                                          if (v == true) {
                                            _mySelectedCards.add(c.cardIndex);
                                          } else {
                                            _mySelectedCards.remove(c.cardIndex);
                                          }
                                        });
                                      },
                              );
                            }).toList(),
                          ),
                        ),
                        TextField(
                          controller: _myCash,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Cash to give'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('You Get',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: _loadingTheirCards
                              ? const Center(child: CircularProgressIndicator())
                              : ListView(
                                  children: _theirCards.map((c) {
                                    final space = widget.spaces[c.cardIndex];
                                    final hasBuildings = c.houses > 0 || c.hotels > 0;
                                    return CheckboxListTile(
                                      title: Text(space?.name ?? 'Card #${c.cardIndex}'),
                                      subtitle: hasBuildings
                                          ? const Text('Sell buildings first',
                                              style: TextStyle(color: Colors.red, fontSize: 10))
                                          : null,
                                      value: _theirSelectedCards.contains(c.cardIndex),
                                      onChanged: hasBuildings
                                          ? null
                                          : (v) {
                                              setState(() {
                                                if (v == true) {
                                                  _theirSelectedCards.add(c.cardIndex);
                                                } else {
                                                  _theirSelectedCards.remove(c.cardIndex);
                                                }
                                              });
                                            },
                                    );
                                  }).toList(),
                                ),
                        ),
                        TextField(
                          controller: _theirCash,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Cash to get'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF689F38),
                foregroundColor: Colors.white,
                minimumSize: Size(50.w, 6.h),
              ),
              child: const Text('Send Offer'),
            ),
          ],
        ),
      ),
    );
  }
}