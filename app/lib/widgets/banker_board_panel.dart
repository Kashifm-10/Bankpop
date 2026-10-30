import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/card_deck.dart';
import 'package:mon/services/player_cards.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/bankpop_board_view.dart';
import 'package:mon/widgets/deck_button.dart';
import 'package:mon/widgets/give_card_flow.dart';

/// The game's board, always on the banker's screen.
///
/// It used to be behind a button in the app bar, so checking who owns what - and
/// giving a card - always began with a popup. The board is part of the screen
/// now: a tap opens that card's deed, and with cards mode on the same deed sells
/// it, exactly as the give-card popup did.
class BankerBoardPanel extends StatefulWidget {
  const BankerBoardPanel({
    super.key,
    required this.gameId,
    required this.payOption,
    required this.bankerId,
    this.canGiveCards = true,
    this.alignment = Alignment.center,
    this.deckBuilder,
    this.onDrawCard,
  });

  final String gameId;
  final String payOption;
  final String bankerId;

  /// Cards mode: a tap may sell the card. Without it the board is a reference,
  /// and a tap only opens the deed.
  final bool canGiveCards;

  /// Where the square sits in the room it is given.
  ///
  /// A board in a row with the players is put at the top of that row, so it
  /// starts where they start instead of leaving a band of empty paper above it;
  /// on a phone it is centred in a region cut to its own size.
  final Alignment alignment;

  /// The two packs, when the game deals cards: drawn on the board itself, over
  /// the piles its art prints at the bottom of the middle square. The builder
  /// is handed the width the tile should take.
  ///
  /// They live here rather than in the banker's row of buttons because that is
  /// where a player looks for a pack - on the board, beside the square that is
  /// named after it - and because the row is needed for the bank's own actions.
  final Widget Function(CardDeckKind kind, double width, DeckStatus status)?
      deckBuilder;

  /// Deals the next card of a pack when its tile on the board is tapped. The
  /// panel then re-reads how much is left, so the mark on the tile moves with
  /// the draw instead of waiting for the next poll.
  final Future<void> Function(CardDeckKind kind)? onDrawCard;

  @override
  State<BankerBoardPanel> createState() => _BankerBoardPanelState();
}

class _BankerBoardPanelState extends State<BankerBoardPanel> {
  /// Where the middle square of the board sits: one corner in from every side,
  /// and nine tiles across. Both are fractions of the whole board.
  static const double _innerStart = 14 / 118;
  static const double _innerSpan = 90 / 118;

  /// The two packs sit along the bottom of that square, pushed out towards its
  /// corners: a narrow margin inside each edge, and whatever is left over opens
  /// up between them. The pair then frames the board instead of huddling in the
  /// middle of it.
  static const double _deckTileWidth = 0.38;
  static const double _deckEdge = 0.03;

  /// How tall the tile comes out at that width: the deck art is 623 x 382, so
  /// the tiles are the same height whatever the board's size.
  static const double _deckTileHeight = _deckTileWidth * 382 / 623;

  /// How far the row sits off the bottom of the square: the same margin the
  /// tiles keep from its sides, so all three edges of the pair are in by the
  /// same amount.
  static const double _deckBottom = _deckEdge;

  BankpopBoard? _board;
  Map<int, CardOwner> _owners = const <int, CardOwner>{};
  Timer? _refresh;
  bool _failed = false;

  /// How much of each pack is unseen, and which one is being shuffled right
  /// now - the two marks the tiles carry.
  int? _chanceLeft;
  int? _chestLeft;
  Set<CardDeckKind> _shuffling = const <CardDeckKind>{};

  @override
  void initState() {
    super.initState();
    _load();
    // Houses, mortgages and sales happen on other devices, so the board reads
    // the table again now and then rather than going stale on the banker.
    _refresh = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final BankpopBoard board = await BoardCatalog.boardForGame(widget.gameId);
      final Map<int, CardOwner> owners = widget.gameId.isEmpty
          ? const <int, CardOwner>{}
          : await PlayerCards.owners(widget.gameId);
      // What is still in each pack, for the tiles drawn on the board. Only a
      // cards game shows them, so only that game pays for the two reads.
      int? chanceLeft;
      int? chestLeft;
      if (widget.deckBuilder != null && widget.gameId.isNotEmpty) {
        chanceLeft = await CardDeck.left(
          gameId: widget.gameId,
          kind: CardDeckKind.chance,
          cards: board.chanceOptions,
        );
        chestLeft = await CardDeck.left(
          gameId: widget.gameId,
          kind: CardDeckKind.chest,
          cards: board.communityChest,
        );
      }
      if (!mounted) return;
      setState(() {
        _board = board;
        _owners = owners;
        _chanceLeft = chanceLeft;
        _chestLeft = chestLeft;
        _failed = false;
      });
    } catch (error) {
      debugPrint('Could not read the board for the banker: $error');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  /// Deals the next card, then reads the pack again so the tile's count is
  /// already right when the card dialog closes.
  Future<void> _deal(CardDeckKind kind) async {
    final Future<void> Function(CardDeckKind kind)? draw = widget.onDrawCard;
    if (draw == null) return;
    await draw(kind);
    if (!mounted) return;
    await _load();
  }

  /// Puts a pack back in a new order, once the banker says so. The tile shows a
  /// spinner where its shuffle button was until the write has landed.
  ///
  /// A shuffle throws away the order the table is working through, so it is
  /// asked about first - the button is small and sits on the card itself, which
  /// makes a mis-tap easy.
  Future<void> _shuffle(BankpopBoard board, CardDeckKind kind) async {
    if (_shuffling.contains(kind)) return;
    final bool sure = await showAppConfirm(
      context,
      title: 'Shuffle ${kind.label}?',
      icon: Icons.shuffle,
      message: 'The pack is put back in a new order and starts again from the '
          'top. Cards a player is holding stay out of it.',
      confirmLabel: 'Shuffle',
    );
    if (!sure || !mounted) return;
    setState(() => _shuffling = <CardDeckKind>{..._shuffling, kind});
    await CardDeck.shuffle(
      gameId: widget.gameId,
      kind: kind,
      cards: kind == CardDeckKind.chance
          ? board.chanceOptions
          : board.communityChest,
    );
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() => _shuffling = <CardDeckKind>{..._shuffling}..remove(kind));
  }

  Future<void> _giveCard(BankpopSpace space) async {
    if (widget.bankerId.isEmpty) {
      showMessage(context, 'This device has no player id');
      return;
    }
    await showGiveCardFor(
      context: context,
      gameId: widget.gameId,
      payOption: widget.payOption,
      bankerId: widget.bankerId,
      space: space,
    );
    if (!mounted) return;
    // The card may have just changed hands.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final BankpopBoard? board = _board;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Widget content;
        if (board == null) {
          content = _failed
              ? const Text(
                  'The board could not be read.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                )
              : const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF689F38),
                  ),
                );
        } else {
          // A square board, the largest that fits the room it is given.
          final double size =
              box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight;
          final Widget? chanceDeck = _deck(size, board, CardDeckKind.chance, 0);
          final Widget? chestDeck = _deck(size, board, CardDeckKind.chest, 1);
          content = size < 60
              ? const SizedBox.shrink()
              : SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: BankpopBoardView(
                          board: board,
                          size: size,
                          isCardMode: widget.canGiveCards,
                          onSpaceSelected:
                              widget.canGiveCards ? _giveCard : null,
                          owners: _owners,
                        ),
                      ),
                      // The packs sit on the board, over the piles drawn on
                      // it. On a board too small to tap they are left off; the
                      // info sheet still explains what they do.
                      if (chanceDeck != null) chanceDeck,
                      if (chestDeck != null) chestDeck,
                    ],
                  ),
                );
        }

        // One place the content starts, whatever state it is in: where the
        // caller said - at the top when the board shares a row with the
        // players, so it begins where they begin.
        return Align(alignment: widget.alignment, child: content);
      },
    );
  }

  /// One pack, placed on the middle square's bottom row: [index] 0 is the
  /// Chance pack on the left, 1 the Community Chest beside it.
  ///
  /// The tile keeps its own width and lets the drawing decide its height, so
  /// it never stretches; the row is measured in gaps, not in painted piles.
  Widget? _deck(double size, BankpopBoard board, CardDeckKind kind, int index) {
    final Widget Function(CardDeckKind kind, double width, DeckStatus status)?
        builder = widget.deckBuilder;
    if (builder == null) return null;
    final double inner = size * _innerSpan;
    final double width = inner * _deckTileWidth;
    // Below this the drawing is a smudge and the touch target is too small to
    // hit, so the board stays clean instead.
    if (width < 46) return null;

    final List<String> cards = kind == CardDeckKind.chance
        ? board.chanceOptions
        : board.communityChest;
    final int? left = kind == CardDeckKind.chance ? _chanceLeft : _chestLeft;
    final DeckStatus status = DeckStatus(
      // Before the first read lands, the pack counts as untouched.
      left: left ?? cards.length,
      total: cards.length,
      shuffling: _shuffling.contains(kind),
      onShuffle: () => _shuffle(board, kind),
      onPressed: widget.onDrawCard == null ? null : () => _deal(kind),
    );

    // Chance hugs the left edge, Community Chest the right: the gap in the
    // middle is whatever the two edges leave, so it is always the widest space
    // in the row.
    final double across =
        index == 0 ? _deckEdge : 1 - _deckEdge - _deckTileWidth;

    return Positioned(
      left: size * _innerStart + inner * across,
      top: size * _innerStart + inner * (1 - _deckBottom - _deckTileHeight),
      width: width,
      child: builder(kind, width, status),
    );
  }
}
