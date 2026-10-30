import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/bankruptcy.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/game_controls.dart';

/// A player the bankrupt can owe money to.
class BankruptcyCreditor {
  const BankruptcyCreditor({required this.playerId, required this.name});

  final String playerId;
  final String name;
}

/// The "declare bankrupt" conversation.
///
/// Two steps, because the rules need one answer before anything moves:
///  1. what the bankruptcy will raise (cash, buildings, mortgages) and whether
///     the player owes anybody at all,
///  2. who they owe, and how much - the banker is not the one who knows.
///
/// Returns null when the player backed out, an empty list for "no dues", and
/// one entry per player they owe otherwise. Nothing is written here: the player
/// screen takes the answer and does the liquidation.
Future<List<BankruptcyDue>?> showBankruptcyDialog(
  BuildContext context, {
  required List<BankruptcyCreditor> creditors,
  required BankruptcyPreview preview,
}) {
  return showDialog<List<BankruptcyDue>>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _BankruptcyDialog(
      creditors: creditors,
      preview: preview,
    ),
  );
}

class _BankruptcyDialog extends StatefulWidget {
  const _BankruptcyDialog({required this.creditors, required this.preview});

  final List<BankruptcyCreditor> creditors;
  final BankruptcyPreview preview;

  @override
  State<_BankruptcyDialog> createState() => _BankruptcyDialogState();
}

class _BankruptcyDialogState extends State<_BankruptcyDialog> {
  bool _listing = false;
  final Set<String> _selected = <String>{};
  final Map<String, TextEditingController> _amounts =
      <String, TextEditingController>{};
  String? _hint;

  @override
  void initState() {
    super.initState();
    for (final BankruptcyCreditor creditor in widget.creditors) {
      _amounts[creditor.playerId] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _amounts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _dueTotal {
    double total = 0;
    for (final String id in _selected) {
      total += double.tryParse(_amounts[id]?.text.trim() ?? '') ?? 0;
    }
    return total;
  }

  List<BankruptcyDue> _dues() {
    return <BankruptcyDue>[
      for (final BankruptcyCreditor creditor in widget.creditors)
        if (_selected.contains(creditor.playerId))
          BankruptcyDue(
            playerId: creditor.playerId,
            name: creditor.name,
            amount: double.tryParse(
                    _amounts[creditor.playerId]?.text.trim() ?? '') ??
                0,
          ),
    ];
  }

  void _declare() {
    if (_selected.isEmpty) {
      setState(() => _hint = 'Pick at least one player, or choose "No dues".');
      return;
    }
    for (final String id in _selected) {
      final double? amount = double.tryParse(_amounts[id]?.text.trim() ?? '');
      if (amount == null || amount <= 0) {
        setState(() => _hint = 'Every player you owe needs an amount above 0.');
        return;
      }
    }
    Navigator.of(context).pop(_dues());
  }

  @override
  Widget build(BuildContext context) {
    final AppDialogPalette palette = AppDialogPalette.of(context);
    final double width = math.min(MediaQuery.sizeOf(context).width, 420);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828).withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              // The declare button's own drawing: the dialog is what that
              // button opened, so it wears the same gavel.
              child: Image.asset(
                GameControls.bankrupt.art!,
                width: 20,
                height: 20,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _listing ? 'Who do you owe?' : 'Declare bankrupt?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: palette.title,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: _listing ? _duesStep(palette) : _questionStep(palette),
          ),
        ),
        actions: _listing
            ? <Widget>[
                AppDialogButton(
                  label: 'Back',
                  onPressed: () => setState(() => _listing = false),
                ),
                AppDialogButton(
                  label: 'Declare bankrupt',
                  primary: true,
                  destructive: true,
                  onPressed: _declare,
                ),
              ]
            : <Widget>[
                AppDialogButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                AppDialogButton(
                  label: 'No dues',
                  onPressed: () => Navigator.of(context).pop(<BankruptcyDue>[]),
                ),
                AppDialogButton(
                  label: 'I owe players',
                  primary: true,
                  destructive: true,
                  onPressed: widget.creditors.isEmpty
                      ? null
                      : () => setState(() {
                            _listing = true;
                            _hint = null;
                          }),
                ),
              ],
      ),
    );
  }

  Widget _questionStep(AppDialogPalette palette) {
    final BankruptcyPreview preview = widget.preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Going bankrupt is final. The bank buys your houses and hotels back '
          'at half price, mortgages your cards, and pays the players you owe '
          'from that money. Every card you hold then goes back to the bank, so '
          'anyone can buy it again.',
          style: TextStyle(fontSize: 14, height: 1.4, color: palette.body),
        ),
        const SizedBox(height: 12),
        AppDialogPoint(
          label: 'Cash in hand',
          value: _money(preview.cash),
          icon: Icons.account_balance_wallet_outlined,
        ),
        AppDialogPoint(
          label: 'Houses & hotels (${preview.buildings})',
          value: _money(preview.buildingsValue),
          icon: Icons.home_work_outlined,
        ),
        AppDialogPoint(
          label: 'Mortgages on ${preview.cards} card(s)',
          value: _money(preview.mortgageValue),
          icon: Icons.credit_card,
        ),
        const Divider(height: 18),
        AppDialogPoint(
          label: 'Can pay up to',
          value: _money(preview.total),
          icon: Icons.savings_outlined,
        ),
        const SizedBox(height: 12),
        Text(
          'Do you owe any of the players at this table?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: palette.title,
          ),
        ),
      ],
    );
  }

  Widget _duesStep(AppDialogPalette palette) {
    final double available = widget.preview.total;
    final double due = _dueTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Tick each player you owe and enter the amount. If the money runs '
          'out, everyone is paid a share of what they are owed.',
          style: TextStyle(fontSize: 13.5, height: 1.35, color: palette.body),
        ),
        const SizedBox(height: 8),
        for (final BankruptcyCreditor creditor in widget.creditors)
          _creditorRow(creditor, palette),
        if (_hint != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _hint!,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC62828),
            ),
          ),
        ],
        const Divider(height: 18),
        AppDialogPoint(
          label: 'You owe',
          value: _money(due),
          icon: Icons.receipt_long_outlined,
        ),
        AppDialogPoint(
          label: 'You can pay',
          value: _money(available),
          icon: Icons.savings_outlined,
        ),
        if (due > available + 0.001)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'That is more than the bankruptcy raises, so the players will '
              'be paid ${_money(available)} between them and the rest is '
              'written off.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: palette.body,
              ),
            ),
          ),
      ],
    );
  }

  Widget _creditorRow(BankruptcyCreditor creditor, AppDialogPalette palette) {
    final bool checked = _selected.contains(creditor.playerId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: checked,
            activeColor: const Color(0xFFC62828),
            onChanged: (bool? value) {
              setState(() {
                if (value == true) {
                  _selected.add(creditor.playerId);
                } else {
                  _selected.remove(creditor.playerId);
                }
                _hint = null;
              });
            },
          ),
          Expanded(
            child: Text(
              creditor.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.title,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: TextField(
              controller: _amounts[creditor.playerId],
              enabled: checked,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                isDense: true,
                hintText: '0.00',
                prefixText: BoardCurrencies.mark,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (_) => setState(() => _hint = null),
            ),
          ),
        ],
      ),
    );
  }

  static String _money(double value) =>
      '${BoardCurrencies.mark}${value.toStringAsFixed(2)}';
}
