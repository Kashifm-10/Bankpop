import 'dart:async';
import 'dart:math' as math;

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
    // A drawn card is not a popup to wave away: it carries the money the table
    // has to settle, so a tap on the paper beside it must not throw it away.
    // The card's own Close button is the way out.
    barrierDismissible: false,
    builder: (_) => _CardEffectDialog(
      gameId: gameId,
      bankerId: bankerId,
      cardText: cardText,
      kind: kind,
      currency: currency,
    ),
  );
}

/// Shows one pack's card face as a picture: no reading area, no buttons.
///
/// This is what tapping the Chance or Community Chest square on the board
/// opens - a look at the pack that square is dealt from. Nothing is drawn and
/// nothing is settled, so unlike a drawn card it closes on an outside tap.
Future<void> showCardFacePreview(
  BuildContext context,
  CardDeckKind kind,
) async {
  final _CardFace face = _CardFace.of(kind);
  final Size screen = MediaQuery.sizeOf(context);
  // The same card, at the same ratio, a little smaller than a drawn one: there
  // is nothing on it to read, so it only has to show the picture.
  final double width = math.min(
    math.min(screen.width - 40, 420),
    (screen.height - 90) * face.aspect,
  );
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: SizedBox(
        width: width,
        height: width / face.aspect,
        child: Image.asset(
          face.art,
          fit: BoxFit.fill,
          semanticLabel: '${kind.label} card',
        ),
      ),
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
    // The card is the dialog: the picture is shown whole, with the reading
    // area and the two buttons laid on the bands the artwork leaves for them.
    final _CardFace face = _CardFace.of(widget.kind);
    final Size screen = MediaQuery.sizeOf(context);
    // Wide enough to read the card, never wider than the window, and never
    // taller than it either - a landscape phone has little height to give.
    final double width = math.min(
      math.min(screen.width - 24, 560),
      (screen.height - 48) * face.aspect,
    );
    final double height = width / face.aspect;
    // The type follows the card, so it keeps the same proportion to the
    // drawing on a phone as on a desktop - but never shrinks to a speck.
    final double scale = width / 560;
    final double cardFont = (15 * scale).clamp(10.5, 15.0);
    final double noteFont = (11.5 * scale).clamp(8.5, 11.5);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: Image.asset(face.art, fit: BoxFit.fill)),
            // The middle of the card: what it says, and what settling it will
            // do with the money.
            // The words keep a margin of their own inside the band, so a long
            // card never runs up against the painted edge.
            _band(
              _CardFace.textArea,
              width,
              height,
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.035),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        // The card was written with its board's own sign; the
                        // table reads one money, so it is swapped here.
                        BoardCurrencies.write(widget.cardText),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: cardFont,
                          height: 1.22,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFFF3D6),
                        ),
                      ),
                      if (_action.kind != CardActionKind.none) ...<Widget>[
                        SizedBox(height: 6 * scale),
                        Text(
                          _summary,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: noteFont,
                            height: 1.2,
                            color: const Color(0xFFFFD08A),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Bottom left: the way out, without touching the cards.
            _band(
              _CardFace.closeArea,
              width,
              height,
              _FaceButton(
                label: 'Close',
                background: const Color(0xFFFFF3D6),
                foreground: const Color(0xFF6D3B12),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // Bottom right: the money. Green only when there is an effect to
            // settle, so a card that is only read keeps a single button.
            if (_action.kind != CardActionKind.none)
              _band(
                _CardFace.actionArea,
                width,
                height,
                _settled
                    ? const _FaceButton(
                        label: 'Settled',
                        background: Color(0xFF1B5E20),
                        foreground: Color(0xFFFFF3D6),
                      )
                    : _FaceButton(
                        label: _busy ? 'Working...' : _actionLabel,
                        background: const Color(0xFF2E7D32),
                        foreground: const Color(0xFFFFF3D6),
                        onPressed: _busy ? null : _settle,
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// Puts [child] on one band of the card, measured as a fraction of the
  /// picture so it stays on its spot at every size.
  Widget _band(Rect area, double width, double height, Widget child) {
    return Positioned(
      left: area.left * width,
      top: area.top * height,
      width: area.width * width,
      height: area.height * height,
      child: child,
    );
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

  /// The green button: what pressing it does, in one word. The sentence it
  /// would need is already written above it, on the card.
  String get _actionLabel {
    switch (_action.kind) {
      case CardActionKind.reward:
        return 'Reward';
      case CardActionKind.pay:
      case CardActionKind.repairs:
      case CardActionKind.collectFromEach:
        return 'Collect';
      case CardActionKind.jailFree:
        return 'Give';
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

/// A drawn card's face, and where its words go on it.
///
/// Both packs are the same card drawn twice - a title across the top and an
/// empty middle - so one set of bands serves both: the reading area in the
/// middle, and two buttons along the bottom, Close on the left and the money
/// on the right. The bands are fractions of the picture, so the card can be
/// drawn at any size and everything stays in its place; they sit a little
/// inside the areas the artwork leaves, which is the padding that keeps the
/// words and buttons off the card's painted edge.
class _CardFace {
  const _CardFace({required this.art, required this.aspect});

  /// The drawing, already cropped to the card itself - its own transparent
  /// margin and the drop shadow under it are gone, so the picture is the card.
  final String art;

  /// Width over height of [art], so the picture is never stretched.
  final double aspect;

  /// The empty middle: what the card says, and what settling it will do.
  static const Rect textArea = Rect.fromLTRB(0.10, 0.470, 0.90, 0.760);

  /// The bottom left and bottom right, level with each other and the same
  /// distance in from the card's edge.
  static const Rect closeArea = Rect.fromLTRB(0.105, 0.795, 0.282, 0.872);
  static const Rect actionArea = Rect.fromLTRB(0.718, 0.795, 0.895, 0.872);

  static const _CardFace chance = _CardFace(
    art: 'assets/Icons/chance_inside_trimmed.png',
    aspect: 849 / 589,
  );

  static const _CardFace chest = _CardFace(
    art: 'assets/Icons/chest_inside_trimmed.png',
    aspect: 847 / 590,
  );

  static _CardFace of(CardDeckKind kind) =>
      kind == CardDeckKind.chance ? chance : chest;
}

/// One of the two buttons on the card's face.
///
/// The band it is given is small, so the label is shrunk to fit rather than
/// allowed to spill over the drawing: a long word still reads whole.
class _FaceButton extends StatelessWidget {
  const _FaceButton({
    required this.label,
    required this.background,
    required this.foreground,
    this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      elevation: onPressed == null ? 0 : 2,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "ameen" -> "Ameen", the same way every other list in the game writes a name.
String _displayName(String? value) {
  if (value == null || value.isEmpty) return 'Player';
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
