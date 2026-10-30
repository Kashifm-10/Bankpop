import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/card_actions.dart';
import 'package:mon/services/card_charges.dart';
import 'package:mon/services/card_deck.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One player at the table, as a card effect needs them.
class _Seat {
  const _Seat({required this.id, required this.name, required this.wallet});

  final String id;
  final String name;
  final double wallet;
}

/// Shows a drawn card and lets the banker settle what it says.
///
/// The card's text is read by [CardAction.parse]; a card about moving, or one
/// the parser cannot read, is simply shown - the banker settles those at the
/// table. Every action that moves money goes through [WalletTransfer], so a
/// reward or a fine is written to the same ledger as an ordinary payment and
/// reaches the player's screen the same way.
Future<void> showCardEffectFlow(
  BuildContext context, {
  required String gameId,
  required String bankerId,
  required String cardText,
  required CardDeckKind kind,
  required String currency,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _CardEffectDialog(
      gameId: gameId,
      bankerId: bankerId,
      cardText: cardText,
      kind: kind,
      currency: currency,
    ),
  );
}

class _CardEffectDialog extends StatefulWidget {
  const _CardEffectDialog({
    required this.gameId,
    required this.bankerId,
    required this.cardText,
    required this.kind,
    required this.currency,
  });

  final String gameId;
  final String bankerId;
  final String cardText;
  final CardDeckKind kind;
  final String currency;

  @override
  State<_CardEffectDialog> createState() => _CardEffectDialogState();
}

class _CardEffectDialogState extends State<_CardEffectDialog> {
  late final CardAction _action = CardAction.parse(widget.cardText);

  /// Set once the card has been settled, so the button cannot be pressed twice.
  bool _settled = false;
  bool _busy = false;

  String _money(num value) => BoardCurrencies.format(widget.currency, value);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFFFF8E1),
      title: Text(widget.kind.label),
      content: SizedBox(
        width: 80.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.cardText,
              style: TextStyle(fontSize: 17.sp, height: 1.35),
            ),
            if (_action.kind != CardActionKind.none) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBCAAA4)),
                ),
                child: Row(
                  children: <Widget>[
                    // A reward is the one effect with an illustrated icon;
                    // the rest keep their glyph.
                    _action.kind == CardActionKind.reward
                        ? Image.asset(
                            'assets/Icons/reward.png',
                            width: 22,
                            height: 22,
                            fit: BoxFit.contain,
                          )
                        : Icon(_icon, size: 18, color: const Color(0xFF6A1B9A)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _summary,
                        style:
                            TextStyle(fontSize: 13.sp, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_action.kind != CardActionKind.none && !_settled)
          FilledButton(
            onPressed: _busy ? null : _settle,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF689F38),
            ),
            child: Text(_buttonLabel),
          ),
        if (_settled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.check_circle,
                    color: Color(0xFF689F38), size: 18),
                const SizedBox(width: 6),
                Text('Settled', style: TextStyle(fontSize: 13.sp)),
              ],
            ),
          ),
      ],
    );
  }

  IconData get _icon {
    switch (_action.kind) {
      case CardActionKind.reward:
        return Icons.card_giftcard;
      case CardActionKind.pay:
        return Icons.payments_outlined;
      case CardActionKind.repairs:
        return Icons.home_repair_service_outlined;
      case CardActionKind.collectFromEach:
        return Icons.groups_outlined;
      case CardActionKind.jailFree:
        return Icons.key_outlined;
      case CardActionKind.none:
        return Icons.info_outline;
    }
  }

  String get _summary {
    switch (_action.kind) {
      case CardActionKind.reward:
        return 'The bank pays ${_money(_action.amount)} to the player you pick.';
      case CardActionKind.pay:
        return 'The player you pick pays ${_money(_action.amount)} to the bank.';
      case CardActionKind.repairs:
        return 'Charged on what the player has built: '
            '${_money(_action.perHouse)} per house, '
            '${_money(_action.perHotel)} per hotel.';
      case CardActionKind.collectFromEach:
        return 'Every other player pays ${_money(_action.amount)} to the '
            'player you pick.';
      case CardActionKind.jailFree:
        return 'The card goes into the hand of the player you pick, and comes '
            'back to the deck once it has been used.';
      case CardActionKind.none:
        return '';
    }
  }

  String get _buttonLabel {
    switch (_action.kind) {
      case CardActionKind.reward:
        return 'Reward a player';
      case CardActionKind.pay:
        return 'Take payment';
      case CardActionKind.repairs:
        return 'Bill repairs';
      case CardActionKind.collectFromEach:
        return 'Collect from each';
      case CardActionKind.jailFree:
        return 'Give the card';
      case CardActionKind.none:
        return '';
    }
  }

  Future<void> _settle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bool ok = await _run();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _settled = ok;
    });
  }

  Future<bool> _run() async {
    if (widget.bankerId.isEmpty) {
      await showMessage(context, 'This device has no banker id in this game');
      return false;
    }

    final List<_Seat> seats = await _seats();
    if (!mounted) return false;
    if (seats.isEmpty) {
      await showMessage(context, 'No players have joined yet');
      return false;
    }

    switch (_action.kind) {
      case CardActionKind.reward:
      case CardActionKind.pay:
        final _Seat? seat = await _pick(seats, verb: 'the money');
        if (seat == null || !mounted) return false;
        final bool reward = _action.kind == CardActionKind.reward;
        final bool paid = reward
            ? await _pay(
                fromId: widget.bankerId,
                fromRole: WalletTransfer.bankerRole,
                fromName: 'Bank',
                toId: seat.id,
                toRole: WalletTransfer.playerRole,
                toName: seat.name,
                amount: _action.amount.toDouble(),
                note: widget.cardText,
              )
            : await _pay(
                fromId: seat.id,
                fromRole: WalletTransfer.playerRole,
                fromName: seat.name,
                toId: widget.bankerId,
                toRole: WalletTransfer.bankerRole,
                toName: 'Bank',
                amount: _action.amount.toDouble(),
                note: widget.cardText,
              );
        if (!paid || !mounted) return false;
        await showMessage(
          context,
          reward
              ? '${seat.name} received ${_money(_action.amount)}.'
              : '${seat.name} paid ${_money(_action.amount)} to the bank.',
          title: reward ? 'Reward paid' : 'Payment taken',
        );
        return true;

      case CardActionKind.repairs:
        final _Seat? seat = await _pick(seats, verb: 'the repairs');
        if (seat == null || !mounted) return false;
        final int houses;
        final int hotels;
        try {
          final List<PlayerCard> cards = await PlayerCards.forPlayer(
            gameId: widget.gameId,
            playerId: seat.id,
          );
          houses =
              cards.fold<int>(0, (int sum, PlayerCard c) => sum + c.houses);
          hotels =
              cards.fold<int>(0, (int sum, PlayerCard c) => sum + c.hotels);
        } catch (error) {
          debugPrint('Could not read what ${seat.name} has built: $error');
          if (!mounted) return false;
          await showMessage(context, 'Could not read that player\'s cards.');
          return false;
        }
        if (!mounted) return false;
        final int total = _action.repairsFor(houses, hotels);
        if (total <= 0) {
          await showMessage(
            context,
            '${seat.name} has nothing built, so the repairs come to nothing.',
            title: 'No repairs',
          );
          return false;
        }
        final bool proceed = await showDialog<bool>(
              context: context,
              builder: (BuildContext dialogContext) => AlertDialog(
                backgroundColor: const Color(0xFFFFF8E1),
                title: Text('Repairs for ${seat.name}'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _repairRow('Houses', houses, _action.perHouse),
                    const SizedBox(height: 6),
                    _repairRow('Hotels', hotels, _action.perHotel),
                    const Divider(height: 22),
                    Text(
                      'Total ${_money(total)}',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF689F38),
                    ),
                    child: const Text('Take payment'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!proceed || !mounted) return false;
        final bool paid = await _pay(
          fromId: seat.id,
          fromRole: WalletTransfer.playerRole,
          fromName: seat.name,
          toId: widget.bankerId,
          toRole: WalletTransfer.bankerRole,
          toName: 'Bank',
          amount: total.toDouble(),
          note: widget.cardText,
        );
        if (!paid || !mounted) return false;
        await showMessage(
          context,
          '${seat.name} paid ${_money(total)} for the repairs.',
          title: 'Payment taken',
        );
        return true;

      case CardActionKind.collectFromEach:
        final _Seat? seat = await _pick(seats, verb: 'the card');
        if (seat == null || !mounted) return false;
        final Map<String, String> payers = <String, String>{
          for (final _Seat other in seats)
            if (other.id != seat.id) other.id: other.name,
        };
        if (payers.isEmpty) {
          await showMessage(
            context,
            '${seat.name} is the only player, so there is nobody to collect '
            'from.',
          );
          return false;
        }
        final List<int>? created = await CardCharges.create(
          gameId: widget.gameId,
          description: widget.cardText,
          receiverId: seat.id,
          receiverName: seat.name,
          payers: payers,
          amount: _action.amount.toDouble(),
        );
        if (!mounted) return false;
        if (created == null) {
          await showMessage(
            context,
            'The charges could not be written. Run supabase/card_charges.sql '
            'so each player can confirm their share.',
            title: 'Could not collect',
          );
          return false;
        }
        await _watchShares(seat, created);
        return true;

      case CardActionKind.jailFree:
        final _Seat? seat = await _pick(seats, verb: 'the card');
        if (seat == null || !mounted) return false;
        final bool given = await _giveJailFree(seat, widget.kind);
        if (!given || !mounted) return false;
        await showMessage(
          context,
          '${seat.name} now holds the ${widget.kind.label} jail-free card. It '
          'goes back to the pack once it has been used.',
          title: 'Card given',
        );
        return true;

      case CardActionKind.none:
        return false;
    }
  }

  /// Waits until every payer has confirmed, counting the shares over again
  /// while the dialog is open.
  Future<void> _watchShares(_Seat receiver, List<int> ids) async {
    final int expected = ids.length;
    Timer? poll;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        int paid = 0;
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) set) {
            poll ??=
                Timer.periodic(const Duration(seconds: 2), (Timer t) async {
              final int nowPaid = await CardCharges.paidCount(ids);
              if (!dialogContext.mounted) {
                t.cancel();
                return;
              }
              if (nowPaid != paid) set(() => paid = nowPaid);
              if (expected > 0 && nowPaid >= expected) {
                t.cancel();
                Navigator.of(dialogContext).pop();
              }
            });
            return AlertDialog(
              backgroundColor: const Color(0xFFFFF8E1),
              title: Text('${receiver.name} collects'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Each player pays ${_money(_action.amount)}. Their screen '
                    'asks them to confirm it.',
                    style: TextStyle(fontSize: 14.sp, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: expected == 0 ? 0 : paid / expected,
                    color: const Color(0xFF689F38),
                    backgroundColor: const Color(0xFFE6EE9C),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$paid of $expected paid',
                    style: TextStyle(fontSize: 13.sp, color: Colors.black54),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    poll?.cancel();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
    poll?.cancel();
  }

  Widget _repairRow(String label, int count, int rate) {
    return Row(
      children: <Widget>[
        Expanded(child: Text('$label: $count × ${_money(rate)}')),
        Text(_money(count * rate)),
      ],
    );
  }

  Future<bool> _pay({
    required String fromId,
    required String fromRole,
    required String fromName,
    required String toId,
    required String toRole,
    required String toName,
    required double amount,
    required String note,
  }) async {
    final TransferOutcome outcome = await WalletTransfer.pay(
      gameId: widget.gameId,
      fromId: fromId,
      fromRole: fromRole,
      toId: toId,
      toRole: toRole,
      amount: amount,
    );
    if (!outcome.ok) {
      if (!mounted) return false;
      await showMessage(
        context,
        outcome.failure == TransferFailure.insufficientFunds
            ? '$fromName does not have ${_money(amount)}.'
            : 'The payment could not be made. Please try again.',
        title: 'Payment failed',
      );
      return false;
    }
    await _record(
      fromName: fromName,
      toName: toName,
      payerId: fromId,
      receiverId: toId,
      amount: amount,
      note: note,
    );
    return true;
  }

  /// Writes the movement into the money history, where every other payment in
  /// the game shows up.
  Future<void> _record({
    required String fromName,
    required String toName,
    required String payerId,
    required String receiverId,
    required double amount,
    required String note,
  }) async {
    final DateTime now = DateTime.now();
    try {
      await Supabase.instance.client
          .from('transactions')
          .insert(<String, dynamic>{
        'game_id': widget.gameId,
        'value': amount,
        'from': fromName,
        'to': toName,
        'code': '${payerId}_$receiverId',
        'date': DateFormat('yyyy-MM-dd').format(now),
        'time': DateFormat('HH:mm:ss').format(now),
      });
    } catch (error) {
      debugPrint('Could not write the card to transactions: $error');
    }
  }

  /// The card goes into [seat]'s hand and out of the pack, so it cannot be
  /// drawn again while it is held.
  Future<bool> _giveJailFree(_Seat seat, CardDeckKind kind) async {
    final int index = kind == CardDeckKind.chance
        ? JailFreeCards.chanceIndex
        : JailFreeCards.chestIndex;
    final ClaimResult claim = await PlayerCards.claim(
      gameId: widget.gameId,
      cardIndex: index,
      fromName: 'Bank',
      toName: seat.name,
      payerId: widget.bankerId,
      receiverId: seat.id,
    );
    if (!claim.ok) {
      if (claim.alreadySold && mounted) {
        await showMessage(
          context,
          'A jail-free card from this pack is already in a player\'s hand.',
          title: 'Already held',
        );
      }
      return false;
    }
    await CardDeck.takeOut(
      gameId: widget.gameId,
      kind: kind,
      card: widget.cardText,
    );
    return true;
  }

  Future<List<_Seat>> _seats() async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('players_test')
          .select()
          .eq('game_id', widget.gameId)
          .eq('role', 'player');
      final List<_Seat> seats = <_Seat>[];
      for (final dynamic raw in rows) {
        final Map<String, dynamic> row = raw as Map<String, dynamic>;
        if (PlayerStanding.fromRow(row) != PlayerStanding.active) continue;
        final String id = row['player_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        seats.add(_Seat(
          id: id,
          name: _displayName(row['name']?.toString()),
          wallet: (row['wallet'] as num?)?.toDouble() ?? 0,
        ));
      }
      seats.sort((a, b) => b.wallet.compareTo(a.wallet));
      return seats;
    } catch (error) {
      debugPrint('Could not load the players for a card: $error');
      return const <_Seat>[];
    }
  }

  Future<_Seat?> _pick(List<_Seat> seats, {required String verb}) {
    return showDialog<_Seat>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: Text('Who gets $verb?'),
        content: SizedBox(
          width: 70.w,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: seats.length,
            itemBuilder: (BuildContext context, int index) {
              final _Seat seat = seats[index];
              return ListTile(
                title: Text(seat.name),
                subtitle: Text(_money(seat.wallet)),
                onTap: () => Navigator.of(dialogContext).pop(seat),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// "ameen" -> "Ameen", the same way every other list in the game writes a name.
String _displayName(String? value) {
  if (value == null || value.isEmpty) return 'Player';
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
