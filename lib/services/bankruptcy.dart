import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/services/player_exit.dart';
import 'package:mon/services/wallet_transfer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One player the bankrupt owes money to.
class BankruptcyDue {
  const BankruptcyDue({
    required this.playerId,
    required this.name,
    required this.amount,
  });

  final String playerId;
  final String name;
  final double amount;
}

/// What this player would raise by going bankrupt, read before anything moves.
///
/// The rules liquidate in this order: the cash in hand is already there, the
/// bank buys every house and hotel back at half price, and every card that is
/// not already mortgaged is mortgaged for half its printed price. The cards
/// themselves then go back to the bank, so the land can be bought again.
class BankruptcyPreview {
  const BankruptcyPreview({
    required this.cash,
    required this.cards,
    required this.houses,
    required this.hotels,
    required this.buildingsValue,
    required this.mortgageValue,
  });

  static const BankruptcyPreview empty = BankruptcyPreview(
    cash: 0,
    cards: 0,
    houses: 0,
    hotels: 0,
    buildingsValue: 0,
    mortgageValue: 0,
  );

  final double cash;
  final int cards;
  final int houses;
  final int hotels;

  /// What the bank pays for the houses and hotels on those cards.
  final double buildingsValue;

  /// What the bank pays to mortgage the cards that are not mortgaged.
  final double mortgageValue;

  /// Everything the player can put towards their debts.
  double get total => cash + buildingsValue + mortgageValue;

  int get buildings => houses + hotels;
}

/// What one creditor was actually paid.
class BankruptcyPayment {
  const BankruptcyPayment({
    required this.playerId,
    required this.name,
    required this.due,
    required this.paid,
  });

  final String playerId;
  final String name;
  final double due;
  final double paid;

  bool get paidInFull => paid + 0.0001 >= due;
}

class BankruptcyOutcome {
  const BankruptcyOutcome.ok({
    required this.payments,
    required this.raised,
    required this.credited,
    required this.cashToBank,
    required this.cards,
    required this.buildings,
  })  : failure = null,
        removed = true;

  const BankruptcyOutcome.rejected(this.failure)
      : payments = const <BankruptcyPayment>[],
        raised = 0,
        credited = 0,
        cashToBank = 0,
        cards = 0,
        buildings = 0,
        removed = false;

  final List<BankruptcyPayment> payments;

  /// Cash in hand plus what the bank paid for the buildings and mortgages.
  final double raised;

  /// The part of [raised] that came from the bank (buildings + mortgages), and
  /// so was credited to the wallet before the debts were paid.
  final double credited;

  /// What was left over after the creditors and went to the bank.
  final double cashToBank;

  final int cards;
  final int buildings;

  /// False when the seat could not be taken off the table, so the player can
  /// still act. The money may already have moved; [failure] says so.
  final bool removed;

  final String? failure;

  bool get ok => failure == null;

  double get paid => payments.fold(0, (double sum, BankruptcyPayment p) => sum + p.paid);
}

/// Going bankrupt.
///
/// A player who cannot pay declares it: the bank buys their buildings back and
/// mortgages their cards, the money raised is split between the players they
/// owe in proportion to what each is owed - nobody can be paid more than the
/// bankruptcy raises - and the cards go back into the bank's unsold stock, so
/// every property they held is on the market again.
///
/// The card rows are removed by [PlayerExit.kick], which is the same path a
/// banker removing a player takes: it also clears houses and hotels, withdraws
/// pending asks and stamps the seat as gone, so there is exactly one way a
/// player leaves a table.
class Bankruptcy {
  const Bankruptcy._();

  static const String _playersTable = 'players_test';
  static const String _cardsTable = 'player_cards';

  /// What a bankruptcy would raise, without moving anything.
  static Future<BankruptcyPreview> preview({
    required String gameId,
    required String playerId,
  }) async {
    if (gameId.isEmpty || playerId.isEmpty) return BankruptcyPreview.empty;
    try {
      final Map<String, dynamic>? row = await _playerRow(gameId, playerId);
      if (row == null) return BankruptcyPreview.empty;
      final List<Map<String, dynamic>> cards = await _heldCards(gameId, playerId);
      final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(gameId);
      return _value(
        cash: (row['wallet'] as num?)?.toDouble() ?? 0,
        cards: cards,
        spaces: spaces,
      );
    } catch (error) {
      debugPrint('Could not read what a bankruptcy would raise: $error');
      return BankruptcyPreview.empty;
    }
  }

  /// The money on the table for [cards] at [spaces], split into what the
  /// buildings are worth and what mortgaging each card would pay.
  static BankruptcyPreview _value({
    required double cash,
    required List<Map<String, dynamic>> cards,
    required Map<int, BankpopSpace> spaces,
  }) {
    int houses = 0;
    int hotels = 0;
    double buildings = 0;
    double mortgages = 0;

    for (final Map<String, dynamic> card in cards) {
      final int index = (card['card_index'] as num?)?.toInt() ?? -1;
      final BankpopSpace? space = spaces[index];
      final int onCard = (card['houses'] as num?)?.toInt() ?? 0;
      final int hotelOnCard = (card['hotels'] as num?)?.toInt() ?? 0;
      houses += onCard;
      hotels += hotelOnCard;
      // The rules pay half the printed price back for a building, the same as
      // selling one during the game (BuildingRules.sell).
      buildings += onCard * ((space?.houseCost ?? 0) ~/ 2);
      buildings += hotelOnCard * ((space?.hotelCost ?? 0) ~/ 2);
      if (card['mortgaged'] != true) {
        mortgages += (space?.price ?? 0) ~/ 2;
      }
    }

    return BankruptcyPreview(
      cash: cash,
      cards: cards.length,
      houses: houses,
      hotels: hotels,
      buildingsValue: buildings,
      mortgageValue: mortgages,
    );
  }

  /// Splits [available] between [dues] in proportion to what each is owed, never
  /// paying more than is owed. The last cents are handed out by largest
  /// remainder, so the payments add up to the pot exactly and no cent is lost
  /// to rounding.
  static List<BankruptcyPayment> split(
    double available,
    List<BankruptcyDue> dues,
  ) {
    final List<BankruptcyDue> owed = <BankruptcyDue>[
      for (final BankruptcyDue due in dues)
        if (due.amount > 0) due,
    ];
    if (owed.isEmpty) return const <BankruptcyPayment>[];

    final int totalDueCents = owed.fold<int>(
      0,
      (int sum, BankruptcyDue due) => sum + (due.amount * 100).round(),
    );
    if (totalDueCents <= 0) return const <BankruptcyPayment>[];

    final int potCents = math.min(
      math.max(0, (available * 100).round()),
      totalDueCents,
    );

    final List<int> cents = List<int>.filled(owed.length, 0);
    if (potCents == totalDueCents) {
      for (int i = 0; i < owed.length; i++) {
        cents[i] = (owed[i].amount * 100).round();
      }
    } else if (potCents > 0) {
      int assigned = 0;
      final List<int> remainders = <int>[];
      for (int i = 0; i < owed.length; i++) {
        final int dueCents = (owed[i].amount * 100).round();
        final int exact = potCents * dueCents;
        cents[i] = exact ~/ totalDueCents;
        remainders.add(exact % totalDueCents);
        assigned += cents[i];
      }
      int left = potCents - assigned;
      final List<int> order = List<int>.generate(owed.length, (int i) => i)
        ..sort((int a, int b) => remainders[b].compareTo(remainders[a]));
      for (final int i in order) {
        if (left <= 0) break;
        cents[i]++;
        left--;
      }
    }

    return <BankruptcyPayment>[
      for (int i = 0; i < owed.length; i++)
        BankruptcyPayment(
          playerId: owed[i].playerId,
          name: owed[i].name,
          due: owed[i].amount,
          paid: cents[i] / 100,
        ),
    ];
  }

  /// Declares [playerId] bankrupt.
  ///
  /// In order, so a failure leaves the table in a state that can be retried:
  ///  1. the bank buys the buildings and mortgages the cards, which is credited
  ///     to the wallet in one movement,
  ///  2. the money raised is paid to [dues] in proportion to each debt,
  ///  3. [PlayerExit.kick] moves whatever is left to the bank, returns the cards
  ///     to the unsold stock and marks the seat gone.
  static Future<BankruptcyOutcome> declare({
    required String gameId,
    required String playerId,
    required String playerName,
    required String bankerId,
    required List<BankruptcyDue> dues,
  }) async {
    if (playerId.isEmpty) {
      return const BankruptcyOutcome.rejected('This device has no player id');
    }
    if (bankerId.isEmpty) {
      return const BankruptcyOutcome.rejected(
          'The bank of this game could not be found');
    }

    final Map<String, dynamic>? row = await _playerRow(gameId, playerId);
    if (row == null) {
      return const BankruptcyOutcome.rejected('You are not at this table');
    }
    if (PlayerStanding.fromRow(row) != PlayerStanding.active) {
      return const BankruptcyOutcome.rejected('You have already left this game');
    }

    final List<Map<String, dynamic>> cards = await _heldCards(gameId, playerId);
    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces(gameId);
    final BankruptcyPreview worth = _value(
      cash: (row['wallet'] as num?)?.toDouble() ?? 0,
      cards: cards,
      spaces: spaces,
    );

    // 1. The bank buys the buildings back and mortgages the cards. The mortgage
    //    money is not paid for good - the card leaves the game in step 3 - so it
    //    is simply the value the rules say a card can raise when it is sold.
    final double liquidation = worth.buildingsValue + worth.mortgageValue;
    double credited = 0;
    if (liquidation > 0) {
      final TransferOutcome raised = await WalletTransfer.pay(
        gameId: gameId,
        fromId: bankerId,
        fromRole: WalletTransfer.bankerRole,
        toId: playerId,
        toRole: WalletTransfer.playerRole,
        amount: liquidation,
      );
      if (!raised.ok) {
        // The bank cannot cover the full liquidation (an exhausted bank roll).
        // The debts are then paid from the cash in hand only; the buildings and
        // cards still go back to the bank in step 3.
        debugPrint('The bank could not pay the liquidation: ${raised.failure}');
      } else {
        credited = liquidation;
        await _record(
          gameId: gameId,
          amount: liquidation,
          fromName: 'Bank',
          toName: playerName,
          code: '${bankerId}_$playerId',
        );
      }
    }

    // 2. The creditors, in proportion to what each is owed.
    final double available = worth.cash + credited;
    final List<BankruptcyPayment> planned = split(available, dues);
    final List<BankruptcyPayment> paid = <BankruptcyPayment>[];
    double paidTotal = 0;
    for (final BankruptcyPayment payment in planned) {
      if (payment.paid <= 0) {
        paid.add(payment);
        continue;
      }
      final TransferOutcome moved = await WalletTransfer.pay(
        gameId: gameId,
        fromId: playerId,
        fromRole: WalletTransfer.playerRole,
        toId: payment.playerId,
        toRole: WalletTransfer.playerRole,
        amount: payment.paid,
      );
      if (!moved.ok) {
        debugPrint('Could not pay ${payment.name}: ${moved.failure}');
        paid.add(BankruptcyPayment(
          playerId: payment.playerId,
          name: payment.name,
          due: payment.due,
          paid: 0,
        ));
        continue;
      }
      paid.add(payment);
      paidTotal += payment.paid;
      await _record(
        gameId: gameId,
        amount: payment.paid,
        fromName: playerName,
        toName: payment.name,
        code: '${playerId}_${payment.playerId}',
      );
    }

    // 3. The seat leaves the table: cash to the bank, cards back on the market,
    //    buildings gone with them.
    final KickOutcome kicked = await PlayerExit.kick(
      gameId: gameId,
      playerId: playerId,
      playerName: playerName,
      bankerId: bankerId,
    );
    if (!kicked.ok) {
      return BankruptcyOutcome.rejected(kicked.failure ??
          'The cards could not be returned to the bank, so the game was not '
              'changed. Try again.');
    }

    return BankruptcyOutcome.ok(
      payments: paid,
      raised: worth.cash + credited,
      credited: credited,
      cashToBank: math.max(0, worth.cash + credited - paidTotal),
      cards: kicked.cards,
      buildings: kicked.buildings,
    );
  }

  static Future<Map<String, dynamic>?> _playerRow(
    String gameId,
    String playerId,
  ) async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_playersTable)
          .select()
          .eq('game_id', gameId)
          .eq('player_id', playerId)
          .eq('role', WalletTransfer.playerRole)
          .limit(1);
      if (rows.isEmpty) return null;
      return (rows.first as Map).cast<String, dynamic>();
    } catch (error) {
      debugPrint('Could not read the player row: $error');
      return null;
    }
  }

  /// The cards this player holds, with their buildings and mortgage state.
  ///
  /// Ownership comes from the row's own id columns, then from `code`, for the
  /// same reason as [PlayerExit]: a card that has been traded away has to stay
  /// with its new owner.
  static Future<List<Map<String, dynamic>>> _heldCards(
    String gameId,
    String playerId,
  ) async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(_cardsTable)
          .select()
          .eq('game_id', gameId);
      return rows
          .cast<Map<String, dynamic>>()
          .where((Map<String, dynamic> row) => _ownerIdOf(row) == playerId)
          .toList();
    } catch (error) {
      debugPrint('Could not read the cards: $error');
      return const <Map<String, dynamic>>[];
    }
  }

  static String? _ownerIdOf(Map<String, dynamic> row) {
    final String? explicit = row['receiver_id']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final String code = row['code']?.toString() ?? '';
    final List<String> parts = code.split('_');
    if (parts.length < 2 || parts[1].isEmpty) return null;
    return parts[1];
  }

  /// One line in the ledger. Bookkeeping only: the money has already moved.
  static Future<void> _record({
    required String gameId,
    required double amount,
    required String fromName,
    required String toName,
    required String code,
  }) async {
    try {
      await Supabase.instance.client.from('transactions').insert(<String, dynamic>{
        'game_id': gameId,
        'value': amount,
        'from': fromName,
        'to': toName,
        'code': code,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': DateFormat('HH:mm:ss').format(DateTime.now()),
      });
    } catch (error) {
      debugPrint('Could not record the bankruptcy movement: $error');
    }
  }
}
