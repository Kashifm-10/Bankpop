import 'package:flutter/widgets.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One payment that landed in this device's wallet.
class _Incoming {
  const _Incoming({required this.amount, required this.from});

  final double amount;

  /// The name the ledger recorded as paying, e.g. "Bank" or "Ameen".
  final String from;
}

/// Tells a device when money arrived in its wallet.
///
/// A payment is made from the payer's phone, so that phone already shows its
/// own receipt the moment it pays - the amount keypad, the scanner and the
/// bank's reward box all end with one. The player on the other side has nothing
/// to look at: their QR was scanned, or the banker picked them in a row, and
/// their balance simply changed. This reads the same ledger the Transactions
/// screen reads and says so.
///
/// `payer_id` and `receiver_id` are filled in by the database from the `code`
/// column (see section 4.2 of `supabase/hardening.sql`); where a project has
/// not run that part yet, the code is split here instead, so a payment is never
/// missed just because the trigger is missing.
///
/// The first read of a game only records where the ledger already is: opening a
/// table must not replay every payment of the last round as a notification.
abstract final class PaymentAlerts {
  /// Which game [_lastSeen] belongs to. A different game starts over.
  static String? _gameId;

  /// The newest ledger row this device has already accounted for.
  static int _lastSeen = -1;

  /// One read at a time: the game screens poll, and a slow round trip must not
  /// stack a second query on top of the first.
  static bool _reading = false;

  /// Reads the ledger for [gameId] and, for each payment that is both new to
  /// this device and addressed to [playerId], shows a message.
  ///
  /// [currency] is the board's symbol; the game's own is used when it is not
  /// given.
  static Future<void> check({
    required BuildContext context,
    required String gameId,
    required String playerId,
    String? currency,
  }) async {
    if (gameId.isEmpty || playerId.isEmpty || _reading) return;
    _reading = true;
    try {
      // Every column: `from` and `to` are reserved words in a select list, and
      // a project without the id columns still has to answer.
      final List<dynamic> response = await Supabase.instance.client
          .from('transactions')
          .select()
          .eq('game_id', gameId)
          .order('id', ascending: false)
          .limit(20);
      final List<Map<String, dynamic>> ledger =
          response.cast<Map<String, dynamic>>();

      if (ledger.isEmpty) {
        if (_gameId != gameId) {
          _gameId = gameId;
          _lastSeen = 0;
        }
        return;
      }

      final int newest = _idOf(ledger.first);
      if (_gameId != gameId || _lastSeen < 0) {
        _gameId = gameId;
        _lastSeen = newest; // where the ledger already is, not news
        return;
      }

      // Oldest first, so several payments read in the order they happened.
      final List<Map<String, dynamic>> fresh = <Map<String, dynamic>>[
        for (final Map<String, dynamic> row in ledger.reversed)
          if (_idOf(row) > _lastSeen) row,
      ];
      _lastSeen = newest;

      final List<_Incoming> incoming = <_Incoming>[];
      for (final Map<String, dynamic> row in fresh) {
        final String payer =
            row['payer_id']?.toString() ?? _codeParty(row, 0);
        final String receiver =
            row['receiver_id']?.toString() ?? _codeParty(row, 1);
        // Only money coming in. A row this device paid is its own receipt,
        // already shown by whatever screen paid it.
        if (receiver != playerId || payer == playerId) continue;
        final num? value = row['value'] as num?;
        if (value == null || value <= 0) continue;
        incoming.add(_Incoming(
          amount: value.toDouble(),
          from: row['from']?.toString() ?? 'The bank',
        ));
      }
      if (incoming.isEmpty || !context.mounted) return;

      final String symbol = currency ?? BoardCatalog.activeCurrency;
      final String message;
      if (incoming.length == 1) {
        message = '${incoming.first.from} paid you '
            '${BoardCurrencies.format(symbol, incoming.first.amount)}. It is in '
            'your balance now.';
      } else {
        final double total = incoming.fold<double>(
            0, (double sum, _Incoming one) => sum + one.amount);
        message = 'You were paid ${BoardCurrencies.format(symbol, total)} in '
            '${incoming.length} payments. They are in your balance now.';
      }
      await showMessage(context, message, title: 'Payment received');
    } catch (error) {
      debugPrint('Could not read the payments received: $error');
    } finally {
      _reading = false;
    }
  }

  /// The ledger row's id, or 0 for a project whose select came back without it.
  static int _idOf(Map<String, dynamic> row) {
    final num? id = row['id'] as num?;
    return id?.toInt() ?? 0;
  }

  /// One half of `code` ("payerId_payeeId"), for a project where the database
  /// trigger that fills the two columns is not deployed yet.
  static String _codeParty(Map<String, dynamic> row, int part) {
    final String code = row['code']?.toString() ?? '';
    final List<String> halves = code.split('_');
    return part < halves.length ? halves[part] : '';
  }

  /// Test hook: forget where the ledger was left.
  @visibleForTesting
  static void reset() {
    _gameId = null;
    _lastSeen = -1;
    _reading = false;
  }
}
