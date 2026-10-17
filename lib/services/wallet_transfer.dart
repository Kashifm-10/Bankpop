import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a transfer did not happen.
enum TransferFailure {
  /// The payer does not have that much money.
  insufficientFunds,

  /// One of the two rows is not in this game (deleted, or wrong game id).
  notFound,

  /// Anything else: network, permissions, an unexpected backend error.
  failed,
}

/// What happened to the banker's wallet when a join was accepted.
class StakeOutcome {
  const StakeOutcome.ok({
    required this.bankerWallet,
    required this.bankerPlayerId,
    required this.atomic,
  }) : failure = null;

  const StakeOutcome.rejected(this.failure)
      : bankerWallet = null,
        bankerPlayerId = null,
        atomic = false;

  /// Banker balance after the stake, when the join was accepted.
  final double? bankerWallet;

  /// The banker's player_id, so the screen can keep showing its own badge.
  final String? bankerPlayerId;

  /// False when the atomic path was unavailable and the sequential fallback ran.
  final bool atomic;

  final TransferFailure? failure;

  bool get ok => failure == null;
}

/// What happened to the two wallets.
class TransferOutcome {
  const TransferOutcome.ok({
    required this.payerWallet,
    required this.payeeWallet,
    required this.atomic,
  }) : failure = null;

  const TransferOutcome.rejected(this.failure)
      : payerWallet = null,
        payeeWallet = null,
        atomic = false;

  /// Balance of the payer after the transfer, when it succeeded.
  final double? payerWallet;

  /// Balance of the payee after the transfer, when it succeeded.
  final double? payeeWallet;

  /// False when the atomic path was unavailable and the sequential fallback ran.
  final bool atomic;

  final TransferFailure? failure;

  bool get ok => failure == null;
}

/// Moves money between two `players_test` rows in one atomic step.
///
/// A payment used to be read-payer / read-payee / write-payer / write-payee from
/// the client. Two devices paying at the same instant both read the same balance
/// and the second write won, so the first payment was silently lost and money was
/// created. The `transfer_money` Postgres function (section 3.3 of
/// supabase/hardening.sql) locks both rows, re-checks the balance and moves the
/// money server-side in a single round trip.
///
/// The function has to exist before it can be called, so until it is deployed
/// this falls back to the old client-side sequence and reports
/// [TransferOutcome.atomic] as false — the app keeps working, without the
/// guarantee. Deploy the function to close the race.
class WalletTransfer {
  const WalletTransfer._();

  /// A device can hold both a banker and a player row in the same game, so the
  /// role is part of the row's identity: only the named role may move.
  static const String playerRole = 'player';
  static const String bankerRole = 'banker';

  static Future<TransferOutcome> pay({
    required String gameId,
    required String fromId,
    required String fromRole,
    required String toId,
    required String toRole,
    required double amount,
  }) async {
    final SupabaseClient supabase = Supabase.instance.client;

    try {
      final dynamic response = await supabase.rpc(
        'transfer_money',
        params: <String, dynamic>{
          'p_game_id': gameId,
          'p_from': fromId,
          'p_from_role': fromRole,
          'p_to': toId,
          'p_to_role': toRole,
          'p_amount': amount,
        },
      );

      final Map<String, dynamic> row = Map<String, dynamic>.from(response as Map);
      return TransferOutcome.ok(
        payerWallet: (row['payer_wallet'] as num).toDouble(),
        payeeWallet: (row['payee_wallet'] as num).toDouble(),
        atomic: true,
      );
    } on PostgrestException catch (error) {
      if (_functionMissing(error)) {
        if (!_transferMissingWarned) {
          _transferMissingWarned = true;
          debugPrint('transfer_money is not deployed yet - run '
              'supabase/hardening.sql section 3.3. Falling back to the '
              'non-atomic client sequence.');
        }
        return _sequential(
          gameId: gameId,
          fromId: fromId,
          fromRole: fromRole,
          toId: toId,
          toRole: toRole,
          amount: amount,
        );
      }
      debugPrint('Transfer rejected: ${error.code} ${error.message}');
      return TransferOutcome.rejected(_failureFor(error));
    } catch (error) {
      debugPrint('Transfer failed: $error');
      return const TransferOutcome.rejected(TransferFailure.failed);
    }
  }

  /// Moves the stake from the bank to a newly seated player and clears the join
  /// request in one step.
  ///
  /// The bank is the issuer, so its wallet is allowed to go negative here - that
  /// is why this cannot reuse [pay], which rejects insufficient funds. Backed by
  /// `stake_player` (section 3.4 of supabase/hardening.sql); until that is
  /// deployed it falls back to the old insert / read / update sequence.
  static Future<StakeOutcome> stake({
    required String gameId,
    required String playerId,
    required String playerName,
    required double amount,
    required String paymentOption,
    required String requestId,
  }) async {
    final SupabaseClient supabase = Supabase.instance.client;

    try {
      final dynamic response = await supabase.rpc(
        'stake_player',
        params: <String, dynamic>{
          'p_game_id': gameId,
          'p_player_id': playerId,
          'p_player_name': playerName,
          'p_stake': amount,
          'p_payment_option': paymentOption,
          'p_request_id': requestId,
        },
      );

      final Map<String, dynamic> row = Map<String, dynamic>.from(response as Map);
      return StakeOutcome.ok(
        bankerWallet: (row['banker_wallet'] as num).toDouble(),
        bankerPlayerId: row['banker_player_id']?.toString(),
        atomic: true,
      );
    } on PostgrestException catch (error) {
      if (_functionMissing(error)) {
        if (!_stakeMissingWarned) {
          _stakeMissingWarned = true;
          debugPrint('stake_player is not deployed yet - run '
              'supabase/hardening.sql section 3.4. Falling back to the '
              'non-atomic client sequence.');
        }
        return _stakeSequential(
          gameId: gameId,
          playerId: playerId,
          playerName: playerName,
          amount: amount,
          paymentOption: paymentOption,
          requestId: requestId,
        );
      }
      debugPrint('Stake rejected: ${error.code} ${error.message}');
      return StakeOutcome.rejected(_failureFor(error));
    } catch (error) {
      debugPrint('Stake failed: $error');
      return const StakeOutcome.rejected(TransferFailure.failed);
    }
  }

  /// Set after the first missing-function rejection so a release build logs the
  /// deployment reminder once instead of on every payment.
  ///
  /// One flag per function: deploying `transfer_money` and not `stake_player`
  /// (or the reverse) must still get its own reminder.
  static bool _transferMissingWarned = false;
  static bool _stakeMissingWarned = false;

  /// True while the app is talking to a project where the function is not
  /// deployed. Kept for diagnostics.
  static bool _functionMissing(PostgrestException error) {
    if (error.code == 'PGRST202') return true;
    return error.message.contains('Could not find the function');
  }

  static TransferFailure _failureFor(PostgrestException error) {
    switch (error.code) {
      case 'P0001':
        return TransferFailure.insufficientFunds;
      case 'P0002':
        return TransferFailure.notFound;
    }
    if (error.message.contains('insufficient funds')) {
      return TransferFailure.insufficientFunds;
    }
    if (error.message.contains('not found')) return TransferFailure.notFound;
    return TransferFailure.failed;
  }

  /// The pre-RPC sequence: read both wallets, check, write both. It has the race
  /// the function exists to remove, and is only used when the function is absent.
  static Future<TransferOutcome> _sequential({
    required String gameId,
    required String fromId,
    required String fromRole,
    required String toId,
    required String toRole,
    required double amount,
  }) async {
    try {
      final double? payer = await _walletOf(gameId, fromId, fromRole);
      final double? payee = await _walletOf(gameId, toId, toRole);
      if (payer == null || payee == null) {
        return const TransferOutcome.rejected(TransferFailure.notFound);
      }
      if (payer < amount) {
        return const TransferOutcome.rejected(TransferFailure.insufficientFunds);
      }

      final SupabaseClient supabase = Supabase.instance.client;
      await supabase
          .from('players_test')
          .update({'wallet': payer - amount}).eq('game_id', gameId).eq(
              'player_id', fromId).eq('role', fromRole);
      await supabase
          .from('players_test')
          .update({'wallet': payee + amount}).eq('game_id', gameId).eq(
              'player_id', toId).eq('role', toRole);

      return TransferOutcome.ok(
        payerWallet: payer - amount,
        payeeWallet: payee + amount,
        atomic: false,
      );
    } catch (error) {
      debugPrint('Fallback transfer failed: $error');
      return const TransferOutcome.rejected(TransferFailure.failed);
    }
  }

  /// The pre-RPC accept path: seat the player, clear the request, then move the
  /// stake. Serialised by the banker screen, but still a read-modify-write, and
  /// four round trips instead of one.
  static Future<StakeOutcome> _stakeSequential({
    required String gameId,
    required String playerId,
    required String playerName,
    required double amount,
    required String paymentOption,
    required String requestId,
  }) async {
    final SupabaseClient supabase = Supabase.instance.client;
    try {
      // A retry after a timeout must not seat the player twice.
      final Map<String, dynamic>? existing = await supabase
          .from('players_test')
          .select('wallet')
          .eq('game_id', gameId)
          .eq('role', playerRole)
          .eq('player_id', playerId)
          .maybeSingle();

      final Map<String, dynamic>? banker = await supabase
          .from('players_test')
          .select('id, wallet, player_id')
          .eq('game_id', gameId)
          .eq('role', bankerRole)
          .maybeSingle();

      if (banker == null) {
        return const StakeOutcome.rejected(TransferFailure.notFound);
      }

      double bankerWallet = (banker['wallet'] as num).toDouble();

      if (existing == null) {
        await supabase.from('players_test').insert({
          'name': playerName,
          'wallet': amount,
          'game_id': gameId,
          'role': playerRole,
          'player_id': playerId,
          'SP/IP': paymentOption,
        });

        bankerWallet -= amount;
        await supabase
            .from('players_test')
            .update({'wallet': bankerWallet}).eq('id', banker['id']);
      }

      await supabase
          .from('request_test')
          .delete()
          .eq('game_id', gameId)
          .eq('id', requestId);

      return StakeOutcome.ok(
        bankerWallet: bankerWallet,
        bankerPlayerId: banker['player_id']?.toString(),
        atomic: false,
      );
    } catch (error) {
      debugPrint('Fallback stake failed: $error');
      return const StakeOutcome.rejected(TransferFailure.failed);
    }
  }

  static Future<double?> _walletOf(
      String gameId, String playerId, String role) async {
    final Map<String, dynamic>? row = await Supabase.instance.client
        .from('players_test')
        .select('wallet')
        .eq('game_id', gameId)
        .eq('player_id', playerId)
        .eq('role', role)
        .maybeSingle();

    final num? wallet = row?['wallet'] as num?;
    return wallet?.toDouble();
  }
}
