import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mon/services/card_actions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which of the board's two packs a draw comes from.
enum CardDeckKind {
  chance,
  chest;

  /// The session column this pack is kept in, so every device at the table
  /// draws the same card in the same order.
  String get column => this == CardDeckKind.chance ? 'chance_deck' : 'chest_deck';

  /// How the pack is named on screen.
  String get label => this == CardDeckKind.chance ? 'Chance' : 'Community Chest';
}

/// A shuffled pack and how far into it the table has drawn.
///
/// A card is not taken out of the pack when it is drawn: the pack is worked
/// through in order, and once every card has been seen the pack is shuffled
/// again. Storing the position rather than moving cards keeps the pack the same
/// size and makes "run out" a thing the table can see.
class CardPack {
  const CardPack({required this.cards, this.drawn = 0});

  /// A pack that has never been dealt.
  static const CardPack empty = CardPack(cards: <String>[]);

  final List<String> cards;
  final int drawn;

  /// Cards still unseen before the pack is finished.
  int get left => cards.length - drawn;

  bool get finished => left <= 0;

  /// The cards of [cards] that are still part of a pack: the ones in
  /// [exclude] are in a player's hand, so they are not dealt - not now, not
  /// after a reshuffle.
  static List<String> playable(List<String> cards, Set<String> exclude) =>
      exclude.isEmpty
          ? List<String>.of(cards)
          : cards.where((String card) => !exclude.contains(card)).toList();

  /// This pack with [exclude] taken out of it, and the draw position moved with
  /// them.
  ///
  /// A card that has gone into somebody's hand is not part of the pack whether
  /// it is still listed in the stored one or not, and the card that would have
  /// been dealt next still is - which is what keeps the position honest when a
  /// jail-free card is claimed in the middle of a deal.
  CardPack without(Set<String> exclude) {
    if (exclude.isEmpty || !cards.any(exclude.contains)) return this;
    final List<String> kept =
        cards.where((String card) => !exclude.contains(card)).toList();
    final int moved =
        cards.take(drawn).where((String card) => !exclude.contains(card)).length;
    return CardPack(cards: kept, drawn: moved);
  }

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'cards': cards, 'drawn': drawn};

  /// The pack as it was stored, or null when this is not one.
  static CardPack? fromJson(Object? value) {
    if (value is! Map) return null;
    final Object? rawCards = value['cards'];
    if (rawCards is! List) return null;
    final Object? rawDrawn = value['drawn'];
    final int drawn = rawDrawn is num ? rawDrawn.toInt() : 0;
    return CardPack(
      cards: rawCards.whereType<String>().toList(),
      drawn: drawn < 0 ? 0 : drawn,
    );
  }

  /// The next card, and the pack it leaves behind.
  ///
  /// [exclude] is what a player is holding: those cards are left out of the
  /// stored pack and out of the shuffle a finished pack starts again from, so a
  /// card in a hand never turns up in the deal until it comes back.
  ///
  /// A pack that was never dealt, or one that has been worked through, starts
  /// again from a fresh shuffle of [fresh]. Only the second case is a
  /// reshuffle: the first draw of a game is just the pack the game started
  /// with, and the banker has nothing to be told about it. [fresh] has to hold
  /// at least one card that is not excluded.
  CardDeckDraw deal(
    List<String> fresh, {
    Set<String> exclude = const <String>{},
    Random? random,
  }) {
    final CardPack current = without(exclude);
    List<String> packCards = current.cards;
    int packDrawn = current.drawn;
    bool reshuffled = false;

    if (packCards.isEmpty || packDrawn >= packCards.length) {
      reshuffled = packCards.isNotEmpty;
      packCards = shuffle(playable(fresh, exclude), random: random);
      packDrawn = 0;
    }

    final String card = packCards[packDrawn];
    return CardDeckDraw(
      card: card,
      pack: CardPack(cards: packCards, drawn: packDrawn + 1),
      reshuffled: reshuffled,
    );
  }

  /// The same cards in a new order.
  static List<String> shuffle(List<String> cards, {Random? random}) {
    final List<String> copy = List<String>.of(cards);
    copy.shuffle(random ?? Random());
    return copy;
  }
}

/// One draw: the card shown to the table and the pack left after it.
class CardDeckDraw {
  const CardDeckDraw({
    required this.card,
    required this.pack,
    this.reshuffled = false,
  });

  final String card;
  final CardPack pack;

  /// True when the pack had been worked through and was shuffled again for
  /// this draw.
  final bool reshuffled;

  /// Cards still unseen in the pack.
  int get left => pack.left;
}

/// The Chance and Community Chest packs of a game.
///
/// They are kept on the game's row in `game_sessions` (see
/// supabase/card_decks.sql) rather than on the banker's phone, so a second
/// banker device - or the same one after a restart - carries on where the
/// table left off instead of dealing a different order. A project that has not
/// run that script yet still deals cards: the pack then lives in memory for as
/// long as the app is open, and nothing else about the game changes.
class CardDeck {
  const CardDeck._();

  /// Packs held for this app run, used when the columns cannot be read or
  /// written. Keyed `gameId:kind`.
  static final Map<String, CardPack> _local = <String, CardPack>{};

  static String _key(String gameId, CardDeckKind kind) =>
      '$gameId:${kind.name}';

  /// Shuffles both packs once, when the game starts.
  static Future<void> startGame({
    required String gameId,
    required List<String> chance,
    required List<String> chest,
  }) async {
    if (gameId.isEmpty) return;
    await shuffle(gameId: gameId, kind: CardDeckKind.chance, cards: chance);
    await shuffle(gameId: gameId, kind: CardDeckKind.chest, cards: chest);
  }

  /// Puts [cards] back in a new order and starts dealing from the top again.
  ///
  /// Whatever a player is holding stays out of the shuffle: the banker may
  /// shuffle at any time, and a held jail-free card must not come back into
  /// play because of it.
  static Future<void> shuffle({
    required String gameId,
    required CardDeckKind kind,
    required List<String> cards,
  }) async {
    if (gameId.isEmpty) return;
    final Set<String> exclude = await _heldJailFree(gameId, kind, cards);
    final CardPack pack =
        CardPack(cards: CardPack.shuffle(CardPack.playable(cards, exclude)));
    _local[_key(gameId, kind)] = pack;
    try {
      await Supabase.instance.client
          .from('game_sessions')
          .update(<String, dynamic>{kind.column: pack.toJson()})
          .eq('game_id', gameId);
    } catch (error) {
      debugPrint('Could not store the ${kind.column}: $error');
    }
  }

  /// The next card of the pack, or null when the board has no cards in it.
  ///
  /// The pack is dealt from where the last draw left it; a pack that has been
  /// worked through is shuffled again first, and the draw says so. Cards in a
  /// player's hand are dealt neither from the stored pack nor from that
  /// reshuffle.
  static Future<CardDeckDraw?> draw({
    required String gameId,
    required CardDeckKind kind,
    required List<String> cards,
    Random? random,
  }) async {
    if (cards.isEmpty) return null;
    final Set<String> exclude = await _heldJailFree(gameId, kind, cards);
    final List<String> fresh = CardPack.playable(cards, exclude);
    if (fresh.isEmpty) return null;

    final CardPack pack = await _read(gameId, kind) ?? CardPack.empty;
    final CardDeckDraw draw = pack.deal(fresh, exclude: exclude, random: random);
    await _write(gameId, kind, draw.pack);
    return draw;
  }

  /// How many cards of [kind] are still unseen.
  ///
  /// A pack that has never been dealt, or one whose column cannot be read,
  /// counts as a full pack minus what a player holds: the next draw shuffles
  /// what is playable and deals from the top of it, so that is how many cards
  /// the table will see.
  static Future<int> left({
    required String gameId,
    required CardDeckKind kind,
    required List<String> cards,
  }) async {
    final Set<String> exclude = await _heldJailFree(gameId, kind, cards);
    final CardPack? pack = await _read(gameId, kind);
    if (pack == null || pack.cards.isEmpty) {
      return CardPack.playable(cards, exclude).length;
    }
    final int left = pack.without(exclude).left;
    return left < 0 ? 0 : left;
  }

  /// Takes [card] out of the pack the next time it is dealt.
  ///
  /// Used for the Get out of Jail Free card: once it is in a player's hand it
  /// is no longer part of the deck. The draw position moves back with it, so
  /// the card that would have been dealt next still is.
  static Future<void> takeOut({
    required String gameId,
    required CardDeckKind kind,
    required String card,
  }) async {
    final CardPack? pack = await _read(gameId, kind);
    if (pack == null) return;
    final int index = pack.cards.indexOf(card);
    if (index < 0) return;
    final List<String> cards = List<String>.of(pack.cards)..removeAt(index);
    final int drawn = pack.drawn > index ? pack.drawn - 1 : pack.drawn;
    await _write(gameId, kind, CardPack(cards: cards, drawn: drawn));
  }

  /// Puts a card that was used back in the pack, at the bottom, so it comes up
  /// again once the pack has been worked through.
  static Future<void> returnCard({
    required String gameId,
    required CardDeckKind kind,
    required String card,
  }) async {
    final CardPack? pack = await _read(gameId, kind);
    if (pack == null) return;
    final List<String> cards = List<String>.of(pack.cards)..add(card);
    await _write(gameId, kind, CardPack(cards: cards, drawn: pack.drawn));
  }

  /// The jail-free card of [kind] if some player is holding it, as the card
  /// text it is written on in [cards]; empty otherwise.
  ///
  /// Each pack prints its own Get out of Jail Free (Chance keeps index 900,
  /// Community Chest 901), and a drawn one is stored as a player's row under
  /// that index - so while that row exists the card belongs to its player, not
  /// to the pack, and it is dealt by nobody: not from the stored pack, not from
  /// a shuffle the banker asks for, not from the reshuffle a worked-through
  /// pack gives itself.
  static Future<Set<String>> _heldJailFree(
    String gameId,
    CardDeckKind kind,
    List<String> cards,
  ) async {
    if (gameId.isEmpty) return const <String>{};

    final Set<String> jailCards = cards
        .where((String card) =>
            CardAction.parse(card).kind == CardActionKind.jailFree)
        .toSet();
    if (jailCards.isEmpty) return const <String>{};

    final int index = kind == CardDeckKind.chance
        ? JailFreeCards.chanceIndex
        : JailFreeCards.chestIndex;

    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('player_cards')
          .select('card_index')
          .eq('game_id', gameId)
          .eq('card_index', index)
          .limit(1);
      return rows.isEmpty ? const <String>{} : jailCards;
    } catch (error) {
      // No table (the script has not been run) or no connection: the pack can
      // only be as good as what the stored one says, which is what it was
      // before this read.
      debugPrint('Could not read the held jail-free card: $error');
      return const <String>{};
    }
  }

  static Future<CardPack?> _read(String gameId, CardDeckKind kind) async {
    if (gameId.isEmpty) return null;
    final String key = _key(gameId, kind);
    try {
      final Map<String, dynamic>? row = await Supabase.instance.client
          .from('game_sessions')
          .select(kind.column)
          .eq('game_id', gameId)
          .maybeSingle();
      final CardPack? pack = CardPack.fromJson(row?[kind.column]);
      if (pack == null) {
        // The server is the truth: a pack that is not there has not been dealt
        // on this game, whatever an earlier run of the app remembers.
        _local.remove(key);
        return null;
      }
      _local[key] = pack;
      return pack;
    } catch (error) {
      // No column (the script has not been run) or no connection: the pack this
      // app run has been dealing from is the best answer there is.
      debugPrint('Could not read the ${kind.column}: $error');
      return _local[key];
    }
  }

  static Future<void> _write(
    String gameId,
    CardDeckKind kind,
    CardPack pack,
  ) async {
    _local[_key(gameId, kind)] = pack;
    try {
      await Supabase.instance.client
          .from('game_sessions')
          .update(<String, dynamic>{kind.column: pack.toJson()})
          .eq('game_id', gameId);
    } catch (error) {
      debugPrint('Could not store the ${kind.column}: $error');
    }
  }
}
