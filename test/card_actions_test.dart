import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/card_actions.dart';

void main() {
  test('a reward card pays the player', () {
    for (final String card in <String>[
      'Collect £50',
      'Bank pays you dividend of £50',
      'Your building loan matures (Collect £150)',
      'You have won a crossword competition (£100)',
      'Income tax refund - £20',
      'Receive interest on 7% preference shares - £25',
    ]) {
      final CardAction action = CardAction.parse(card);
      expect(action.kind, CardActionKind.reward, reason: card);
      expect(action.amount, greaterThan(0), reason: card);
    }
  });

  test('a payment card takes money from the player', () {
    for (final String card in <String>[
      'Pay school fees of £150',
      'Pay hospital £100',
      "Pay doctor's fee - £50",
      'Drunk in charge - Fine £20',
      'Speeding fine - £15',
    ]) {
      final CardAction action = CardAction.parse(card);
      expect(action.kind, CardActionKind.pay, reason: card);
      expect(action.amount, greaterThan(0), reason: card);
    }
  });

  test('both street repairs cards carry their two rates', () {
    for (final String card in <String>[
      'You are assessed for street repairs - £40 per house, £115 per hotel',
      'Street repairs - £40 per house, £115 per hotel',
    ]) {
      final CardAction action = CardAction.parse(card);
      expect(action.kind, CardActionKind.repairs, reason: card);
      expect(action.perHouse, 40, reason: card);
      expect(action.perHotel, 115, reason: card);
      expect(action.repairsFor(3, 1), 3 * 40 + 115);
    }
  });

  test('general repairs without rates cannot be billed from the text', () {
    expect(
      CardAction.parse('Make general repairs on all your properties').kind,
      CardActionKind.none,
    );
  });

  test('a collect-from-each card names the amount once', () {
    final CardAction action =
        CardAction.parse('It is your birthday! Collect £10 from each player');
    expect(action.kind, CardActionKind.collectFromEach);
    expect(action.amount, 10);

    final CardAction every =
        CardAction.parse('Collect £50 from every player');
    expect(every.kind, CardActionKind.collectFromEach);
    expect(every.amount, 50);
  });

  test('the jail card is kept rather than paid', () {
    expect(
      CardAction.parse('Get out of Jail Free').kind,
      CardActionKind.jailFree,
    );
  });

  test('movement cards are left to the table', () {
    for (final String card in <String>[
      'Advance to Go',
      'Go back 3 spaces',
      'Take a trip to Mumbai Terminus Station',
      'Go to Jail (Do not pass Go, do not collect the advance)',
      // The figure on an advance card is the square's own payment, not a
      // reward to hand out from the deck.
      'Advance to GO (Collect £200)',
    ]) {
      expect(CardAction.parse(card).kind, CardActionKind.none, reason: card);
    }
  });
}
