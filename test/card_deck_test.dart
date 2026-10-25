import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/card_deck.dart';

const List<String> _cards = <String>['a', 'b', 'c'];

void main() {
  test('a new pack deals every card once, in a shuffled order', () {
    CardDeckDraw draw = CardPack.empty.deal(_cards, random: Random(1));
    expect(draw.reshuffled, isFalse, reason: 'the game\'s own first deal');
    expect(draw.left, 2);

    final List<String> seen = <String>[draw.card];
    for (int i = 0; i < 2; i++) {
      draw = draw.pack.deal(_cards, random: Random(1));
      expect(draw.reshuffled, isFalse, reason: 'still the same pack');
      seen.add(draw.card);
    }

    expect(seen.toSet(), _cards.toSet(), reason: 'no card is drawn twice');
    expect(draw.left, 0);
  });

  test('a finished pack is shuffled again, and the draw says so', () {
    const CardPack finished = CardPack(cards: _cards, drawn: 3);
    expect(finished.finished, isTrue);

    final CardDeckDraw draw = finished.deal(_cards, random: Random(2));
    expect(draw.reshuffled, isTrue);
    expect(_cards.contains(draw.card), isTrue);
    expect(draw.left, 2);
  });

  test('a stored pack survives the round trip through JSON', () {
    const CardPack pack = CardPack(cards: <String>['a', 'b', 'c'], drawn: 2);
    final CardPack? restored = CardPack.fromJson(pack.toJson());

    expect(restored, isNotNull);
    expect(restored!.cards, <String>['a', 'b', 'c']);
    expect(restored.drawn, 2);
    expect(restored.left, 1);
  });

  test('anything that is not a stored pack is ignored', () {
    expect(CardPack.fromJson(null), isNull);
    expect(CardPack.fromJson('a b c'), isNull);
    expect(CardPack.fromJson(<String, dynamic>{'cards': 'a b c'}), isNull);
  });

  group('a card in a player\'s hand', () {
    const String jail = 'Get out of Jail Free';
    const Set<String> held = <String>{jail};
    final List<String> pack = <String>['a', jail, 'b', 'c'];

    test('leaves the stored pack, and the position moves back with it', () {
      const CardPack drawn =
          CardPack(cards: <String>['a', jail, 'b', 'c'], drawn: 2);

      final CardPack kept = drawn.without(held);
      expect(kept.cards, <String>['a', 'b', 'c']);
      // The card that would have been dealt next still is: the held card sat
      // at 1, so the position drops by one.
      expect(kept.drawn, 1);

      final CardDeckDraw draw =
          kept.deal(CardPack.playable(pack, held), exclude: held);
      expect(draw.card, 'b', reason: 'the card that was next still is');
      expect(draw.reshuffled, isFalse);
    });

    test('is dealt neither from the pack nor from a reshuffle', () {
      const CardPack finished = CardPack(cards: <String>['a', 'b', 'c'], drawn: 3);

      // The caller passes the board's own list - jail card and all - the way a
      // finished pack starts again, and the shuffle still has to leave it out.
      final CardDeckDraw draw = finished.deal(pack, exclude: held,
          random: Random(7));

      expect(draw.reshuffled, isTrue);
      expect(draw.card, isNot(jail));
      expect(draw.pack.cards, isNot(contains(jail)));
      expect(draw.left, 2, reason: 'three cards are playable, one was dealt');
    });

    test('is kept out of the playable list a shuffle deals from', () {
      expect(
        CardPack.playable(pack, held),
        <String>['a', 'b', 'c'],
        reason: 'the hand has its card, the pack deals the rest',
      );
      expect(CardPack.playable(pack, const <String>{}), pack);
    });
  });
}
