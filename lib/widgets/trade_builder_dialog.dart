import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/deals.dart';
import 'package:mon/widgets/app_metrics.dart';

/// What the builder hands back once an offer has been written: the row id the
/// caller polls, and who has to answer it.
class SentTradeOffer {
  const SentTradeOffer({required this.id, required this.toName});

  final int id;
  final String toName;
}

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

/// One colour group of a hand, for the card picker.
class _TradeGroup {
  const _TradeGroup(this.colour, this.cards);

  final String colour;
  final List<PlayerCard> cards;
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

    final String giveDesc = _describe(
      _mySelectedCards.length,
      myCash,
    );
    final String getDesc = _describe(
      _theirSelectedCards.length,
      theirCash,
    );
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Send this trade?'),
        content: Text(
          'You give: $giveDesc\n'
          'You get: $getDesc\n\n'
          '$_selectedPlayerName will be asked to accept or counter.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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
      // The caller waits on this id and offers a cancel button, so the sender
      // is not left wondering whether the offer went out.
      if (mounted) {
        Navigator.pop(
          context,
          SentTradeOffer(id: id, toName: _selectedPlayerName ?? 'the player'),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send trade offer')),
        );
      }
    }
  }

  /// The player's cards, laid out the way My Cards lays them out: grouped by
  /// colour in board order, one tile per card. A tile carries the group colour
  /// so a set is recognisable before it is read, and a card with buildings on
  /// it says why it cannot be traded instead of silently refusing the tap.
  Widget _cardPicker({
    required List<PlayerCard> cards,
    required Set<int> selected,
  }) {
    if (cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No cards here yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.sp, color: Colors.black45),
          ),
        ),
      );
    }

    final List<_TradeGroup> groups = _groups(cards);
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: <Widget>[
        for (final _TradeGroup group in groups) ...<Widget>[
          _groupHeader(group),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final PlayerCard card in group.cards)
                _pickTile(card, selected),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// Cards grouped by colour, the groups themselves in board order.
  List<_TradeGroup> _groups(List<PlayerCard> cards) {
    final Map<String, List<PlayerCard>> byColour = <String, List<PlayerCard>>{};
    for (final PlayerCard card in cards) {
      final String colour = widget.spaces[card.cardIndex]?.color ?? 'Other';
      (byColour[colour] ??= <PlayerCard>[]).add(card);
    }
    byColour.forEach((String _, List<PlayerCard> group) {
      group.sort(
          (PlayerCard a, PlayerCard b) => a.cardIndex.compareTo(b.cardIndex));
    });
    final List<String> colours = byColour.keys.toList()
      ..sort((String a, String b) => _groupStart(a).compareTo(_groupStart(b)));
    return <_TradeGroup>[
      for (final String colour in colours)
        _TradeGroup(colour, byColour[colour]!),
    ];
  }

  /// The lowest board index in a colour group, so groups sort as they sit on
  /// the board rather than alphabetically.
  int _groupStart(String colour) {
    int best = 1 << 30;
    for (final BankpopSpace space in widget.spaces.values) {
      if ((space.color ?? 'Other') == colour && space.index < best) {
        best = space.index;
      }
    }
    return best;
  }

  Widget _groupHeader(_TradeGroup group) {
    final Color colour = Color(BankpopBoard.colorForGroup(group.colour));
    final String label = group.colour.isEmpty
        ? 'Other'
        : group.colour[0].toUpperCase() + group.colour.substring(1);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
          ),
          const SizedBox(width: 6),
          // The header shares its row with the cards below it on a narrow
          // phone, so a long colour name shortens rather than overflows.
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF33691E),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${group.cards.length}',
            style: TextStyle(fontSize: 10.sp, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  /// One selectable card. The tick is always visible, so a set that is half
  /// picked reads at a glance.
  Widget _pickTile(PlayerCard card, Set<int> selected) {
    final BankpopSpace? space = widget.spaces[card.cardIndex];
    final Color colour = Color(BankpopBoard.colorForGroup(space?.color));
    final bool hasBuildings = card.houses > 0 || card.hotels > 0;
    final bool picked = selected.contains(card.cardIndex);

    return Opacity(
      opacity: hasBuildings ? 0.45 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: hasBuildings
            ? null
            : () {
                setState(() {
                  if (picked) {
                    selected.remove(card.cardIndex);
                  } else {
                    selected.add(card.cardIndex);
                  }
                });
              },
        child: Container(
          width: 116,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: picked ? colour.withValues(alpha: 0.14) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: picked ? colour : colour.withValues(alpha: 0.45),
              width: picked ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 5,
                    height: 24,
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      space?.name ?? 'Card #${card.cardIndex}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                  Icon(
                    picked ? Icons.check_circle : Icons.circle_outlined,
                    size: 13,
                    color: picked ? colour : Colors.black26,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hasBuildings
                    ? 'Sell buildings first'
                    : card.mortgaged
                        ? 'Mortgaged'
                        : '\u00a3${space?.price ?? 0}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.sp,
                  color: hasBuildings ? Colors.red : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "2 cards and \u00a3150" - the summary line in the confirm dialog.
  static String _describe(int cardCount, double cash) {
    final List<String> bits = <String>[];
    if (cardCount > 0) {
      bits.add('$cardCount card${cardCount == 1 ? '' : 's'}');
    }
    if (cash > 0) {
      bits.add('\u00a3${cash.toStringAsFixed(0)}');
    }
    if (bits.isEmpty) return 'nothing';
    return bits.join(' and ');
  }

  @override
  Widget build(BuildContext context) {
    final otherPlayers =
        widget.players.where((p) => p['player_id'] != widget.myId).toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 90.w,
        // The frame caps the design height used by `.h`, but a dialog still has
        // to fit the window it is drawn in: on a 400 px landscape phone 85.h
        // would be taller than the screen.
        height: MediaQuery.sizeOf(context).height * 0.85,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.yellow.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Flexible so a long font, a large text scale or a narrow
                // phone wraps the title instead of overflowing the row.
                Expanded(
                  child: Text(
                    'Trade Builder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
                  ),
                ),
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
                  final p =
                      otherPlayers.firstWhere((p) => p['player_id'] == val);
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
                          child: _cardPicker(
                            cards: widget.myCards,
                            selected: _mySelectedCards,
                          ),
                        ),
                        TextField(
                          controller: _myCash,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Cash to give'),
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
                              : _cardPicker(
                                  cards: _theirCards,
                                  selected: _theirSelectedCards,
                                ),
                        ),
                        TextField(
                          controller: _theirCash,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Cash to get'),
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
