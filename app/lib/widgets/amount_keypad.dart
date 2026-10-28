import 'package:flutter/material.dart';

/// The one amount keypad in the app.
///
/// Paying a player and paying the bank are the same act with a different
/// destination, and the two screens had grown a full copy each - a thousand
/// lines of duplicated keypad that had already drifted apart (one validated the
/// amount before charging, the other leaned on the transfer to refuse it).
///
/// This dialog only collects the amount and reports the outcome. The caller
/// hands in [onPay], which does the transfer and returns null on success or a
/// sentence to show when it did not happen; nothing else here knows about
/// wallets. Returns true when the money actually moved.
Future<bool> showAmountKeypad(
  BuildContext context, {
  required String title,

  /// Who is being paid, in words: a player's name, or "the bank".
  required String payee,

  /// The card strip at the top, so the payer can see whose money is going out.
  required String holderName,
  required String cardDigits,
  required Future<String?> Function(double amount) onPay,
}) async {
  final bool? paid = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _AmountKeypad(
      title: title,
      payee: payee,
      holderName: holderName,
      cardDigits: cardDigits,
      onPay: onPay,
    ),
  );
  return paid ?? false;
}

class _AmountKeypad extends StatefulWidget {
  const _AmountKeypad({
    required this.title,
    required this.payee,
    required this.holderName,
    required this.cardDigits,
    required this.onPay,
  });

  final String title;
  final String payee;
  final String holderName;
  final String cardDigits;
  final Future<String?> Function(double amount) onPay;

  @override
  State<_AmountKeypad> createState() => _AmountKeypadState();
}

class _AmountKeypadState extends State<_AmountKeypad> {
  static const Color _green = Color(0xFF689F38);

  final TextEditingController _amount = TextEditingController();
  bool _processing = false;
  String _status = 'Enter an amount';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _append(String digit) {
    if (_processing) return;
    // Two decimals is all the game deals in, and the amount is never negative.
    final String next = _amount.text + digit;
    if (next.contains('.')) {
      final List<String> parts = next.split('.');
      if (parts.length > 1 && parts[1].length > 2) return;
    }
    if (next.replaceAll('.', '').length > 9) return;
    setState(() {
      _amount.text = next;
      _status = 'Enter an amount';
    });
  }

  void _dot() {
    if (_processing || _amount.text.contains('.')) return;
    setState(() {
      _amount.text = _amount.text.isEmpty ? '0.' : '${_amount.text}.';
    });
  }

  void _backspace() {
    if (_processing || _amount.text.isEmpty) return;
    setState(() {
      _amount.text = _amount.text.substring(0, _amount.text.length - 1);
    });
  }

  void _clear() {
    if (_processing) return;
    setState(() {
      _amount.text = '';
      _status = 'Enter an amount';
    });
  }

  Future<void> _submit() async {
    if (_processing) return;
    final double? amount = double.tryParse(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _status = 'Enter an amount above 0');
      return;
    }

    setState(() {
      _processing = true;
      _status = 'Paying...';
    });

    final String? failure = await widget.onPay(amount);
    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _processing = false;
        _status = failure;
      });
      return;
    }

    setState(() => _status = 'Paid');
    // Let the confirmation be read before the dialog goes.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color surface =
        dark ? const Color(0xFF26291F) : const Color(0xFFFFF8E1);
    final Color ink = dark ? const Color(0xFFE0E0E0) : const Color(0xFF33691E);
    // The key faces stay a shade above the dialog, so the grid reads as keys
    // rather than as holes punched in the card.
    final Color keyFace = dark ? const Color(0xFF3B3F33) : Colors.white;
    final Color keyInk = dark ? Colors.white : const Color(0xFF2C2C2C);

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _processing
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel',
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                _CardStrip(
                  holderName: widget.holderName,
                  cardDigits: widget.cardDigits,
                  dark: dark,
                ),
                const SizedBox(height: 12),
                Text(
                  'Paying ${widget.payee}',
                  style: TextStyle(
                    fontSize: 13,
                    color: ink.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _amount.text.isEmpty ? '0' : _amount.text,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color:
                        _status == 'Paid' ? _green : ink.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 10),
                // The keys the amount is typed on: 1-9, then the three that
                // finish it - the decimal point, zero, and backspace. Backspace
                // held down clears the whole amount, which is what the old red
                // "C" key did before it made way for the point.
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  childAspectRatio: 2.1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: <Widget>[
                    for (final String digit in <String>[
                      '1',
                      '2',
                      '3',
                      '4',
                      '5',
                      '6',
                      '7',
                      '8',
                      '9',
                    ])
                      _key(
                        _label(digit, keyInk),
                        () => _append(digit),
                        background: keyFace,
                      ),
                    _key(
                      _label('.', keyInk),
                      _dot,
                      background: keyFace,
                    ),
                    _key(
                      _label('0', keyInk),
                      () => _append('0'),
                      background: keyFace,
                    ),
                    _key(
                      Icon(
                        Icons.backspace_outlined,
                        size: 20,
                        color: keyInk,
                      ),
                      _backspace,
                      background: keyFace,
                      onLongPress: _clear,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // The one wide button under the keys: nothing is charged until
                // this is pressed.
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _processing ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _green.withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _processing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'PAY',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A digit as it is drawn on a key.
  Widget _label(String text, Color colour) => Text(
        text,
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: colour,
        ),
      );

  Widget _key(
    Widget child,
    VoidCallback onTap, {
    Color? background,
    VoidCallback? onLongPress,
  }) {
    final Widget button = ElevatedButton(
      onPressed: _processing ? null : onTap,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: background ?? Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: child,
    );
    if (onLongPress == null) return button;
    return GestureDetector(
      onLongPress: _processing ? null : onLongPress,
      child: button,
    );
  }
}

/// The card the money is coming from, as a strip rather than the rotated
/// showpiece: it carries the same two facts without half the dialog being
/// decoration.
class _CardStrip extends StatelessWidget {
  const _CardStrip({
    required this.holderName,
    required this.cardDigits,
    required this.dark,
  });

  final String holderName;
  final String cardDigits;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade500,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.credit_card, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              holderName.isEmpty ? 'Player' : holderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            '**** $cardDigits',
            style: TextStyle(
              color: Colors.blueGrey.shade100,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
