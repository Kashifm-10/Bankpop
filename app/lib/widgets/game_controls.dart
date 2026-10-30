import 'package:flutter/material.dart';

/// One control on a game screen: the icon, the name a player can recognise,
/// and the sentence that explains what it does.
///
/// The game screens draw their actions as icons only, so this is also the data
/// behind the legend sheet the info button opens. Keeping the label and the
/// explanation next to the icon means a button and its documentation cannot
/// drift apart.
class GameControl {
  const GameControl({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
    this.art,
    this.artScale = 0.68,
  });

  /// The glyph, used when the control has no illustrated icon.
  final IconData icon;

  /// The legend heading, and the tooltip/screen-reader label of the button.
  final String label;

  /// What tapping it does, in one sentence.
  final String detail;

  /// The accent colour for the icon - the button's "purpose" colour.
  final Color color;

  /// An illustrated icon (`assets/Icons/`) that replaces [icon] on the button.
  ///
  /// These are drawn full colour rather than tinted, so a control that has art
  /// is not colour-coded by [color] - the drawing carries the meaning, and the
  /// palette's accent colour is only kept for the legend text and the glyph
  /// fallback. Null for a control that still draws its [icon].
  final String? art;

  /// How much of the tile [art] fills, along the shorter side.
  ///
  /// Square drawings are happy at the default. A wide one - the board is half
  /// as tall as it is long - has to take more of the tile, or it reads as a
  /// sliver next to the square icons.
  final double artScale;
}

/// The palette the game screens share. Cream paper, dark brown ink and a small
/// shadow, so the buttons read as the same family as the board art instead of
/// as system widgets.
abstract final class GameControlStyle {
  static const Color paper = Color(0xFFFFF8E1);
  static const Color ink = Color(0xFF5D4037);
  static const Color disabled = Color(0xFFEFEBE9);
}

/// The controls the app knows how to draw and explain.
abstract final class GameControls {
  static const GameControl info = GameControl(
    icon: Icons.info_outline,
    art: 'assets/Icons/controls.png',
    label: 'Controls',
    detail: 'Opens this list, explaining every icon on the screen.',
    color: Color(0xFF1565C0),
  );

  static const GameControl history = GameControl(
    icon: Icons.history,
    art: 'assets/Icons/history.png',
    label: 'Transactions',
    detail: 'Every payment made at this table, newest first.',
    color: Color(0xFF6D4C41),
  );

  static const GameControl board = GameControl(
    icon: Icons.grid_on,
    art: 'assets/Icons/board_trimmed.png',
    // The board is drawn in perspective and wide, so it uses nearly the whole
    // tile to sit at the same weight as the square icons beside it.
    artScale: 0.95,
    label: 'Board',
    detail: 'The board, with who owns what. Tap a property to read its deed.',
    color: Color(0xFF2E7D32),
  );

  static const GameControl leave = GameControl(
    icon: Icons.logout,
    art: 'assets/Icons/leave.png',
    label: 'Leave game',
    detail: 'Leaves this table and goes back to Your Games. The game keeps '
        'running for everyone else.',
    color: Color(0xFF8D6E63),
  );

  static const GameControl receive = GameControl(
    icon: Icons.qr_code_2,
    art: 'assets/Icons/show_qr.png',
    label: 'Show QR',
    detail: 'Shows your QR code, so another player can scan it and pay you.',
    color: Color(0xFF00796B),
  );

  static const GameControl giveCard = GameControl(
    icon: Icons.back_hand_outlined,
    art: 'assets/Icons/give_card.png',
    label: 'Give card',
    detail: 'On a property\'s deed: sells that card to a player - by QR in a '
        'ScanPay game, or to the player you pick in an InstantPay game.',
    color: Color(0xFF1565C0),
  );

  static const GameControl myCards = GameControl(
    icon: Icons.credit_card,
    art: 'assets/Icons/my_cards.png',
    label: 'My cards',
    detail: 'The cards you own. Tap one to read its deed, mortgage it or sell '
        'its houses.',
    color: Color(0xFF1565C0),
  );

  /// The bank paying a player: the reward button in the banker's player rows,
  /// and the payout line on a Chance or Community Chest card.
  static const GameControl reward = GameControl(
    icon: Icons.redeem,
    art: 'assets/Icons/reward.png',
    label: 'Reward player',
    detail: 'Gives cash from the bank to the player you pick, or pays out the '
        'reward a card names.',
    color: Color(0xFF2E7D32),
  );

  static const GameControl trade = GameControl(
    icon: Icons.swap_horiz,
    art: 'assets/Icons/trade.png',
    label: 'Trade',
    detail: 'Build an offer of cards, cash or both and send it to a player.',
    color: Color(0xFF7B1FA2),
  );

  /// The two packs the banker deals from, drawn as the decks themselves.
  ///
  /// The art is landscape (623 x 382, the drawing cropped to its own bounds),
  /// so these two are drawn by [DeckButton] rather than a square sticker - the
  /// tile takes the picture's own ratio and nothing else. Chance is red and
  /// the Chest blue, the two colours apart.
  /// A cards game is the only one where a card can be dealt, so these two are
  /// only on the screen in one.
  static const GameControl chanceDeck = GameControl(
    icon: Icons.casino_outlined,
    art: 'assets/Icons/chance_deck_l_trimmed.png',
    label: 'Chance deck',
    detail: 'Deals the next Chance card and shows the table what it asks for.',
    color: Color(0xFFC62828),
  );

  static const GameControl chestDeck = GameControl(
    icon: Icons.inventory_2_outlined,
    art: 'assets/Icons/chest_deck_l_trimmed.png',
    label: 'Community Chest deck',
    detail: 'Deals the next Community Chest card and shows the table what it '
        'asks for.',
    color: Color(0xFF1565C0),
  );

  /// One scanner for the whole hand: it reads a player's pay QR and the bank's
  /// card QR, so there is only one camera button on the screen.
  static const GameControl scan = GameControl(
    icon: Icons.qr_code_scanner,
    art: 'assets/Icons/scan.png',
    label: 'Scan',
    detail: 'Scan a player\'s QR to pay them, or the bank\'s card QR to buy '
        'the property it is selling.',
    color: Color(0xFFC62828),
  );

  static const GameControl payBank = GameControl(
    icon: Icons.payments_outlined,
    art: 'assets/Icons/pay_bank.png',
    label: 'Pay to bank',
    detail: 'Pays the bank straight from your balance - no scanning in this '
        'game.',
    color: Color(0xFFC62828),
  );

  /// The table's invitation: the QR a player scans to ask for a seat, and the
  /// code beside it. Called Join QR because that is what a player uses it for.
  static const GameControl showBankQr = GameControl(
    icon: Icons.groups,
    art: 'assets/Icons/join_trimmed.png',
    artScale: 0.84,
    label: 'Join QR',
    detail: 'Shows the game ID and its QR, so a player who is not at the table '
        'yet can scan it and join this game.',
    color: Color(0xFF1E88E5),
  );

  static const GameControl bankrupt = GameControl(
    icon: Icons.gavel,
    art: 'assets/Icons/declare_trimmed.png',
    label: 'Declare bankrupt',
    detail: 'Leaves the table for good: your cash, houses and cards are sold '
        'and the money pays the players you owe.',
    color: Color(0xFFB71C1C),
  );

  static const GameControl suspend = GameControl(
    icon: Icons.pause_circle_outline,
    art: 'assets/Icons/pause.png',
    label: 'Suspend game',
    detail: 'Pauses the table for everyone. Nothing is lost - resuming '
        'continues exactly where the table stopped.',
    color: Color(0xFF689F38),
  );

  /// The same menu entry in its other state: a paused game offers resume.
  static const GameControl resume = GameControl(
    icon: Icons.play_circle_outline,
    art: 'assets/Icons/resume.png',
    label: 'Resume game',
    detail: 'Lets everyone play on from where the game was paused.',
    color: Color(0xFF689F38),
  );

  static const GameControl endGame = GameControl(
    icon: Icons.flag_outlined,
    art: 'assets/Icons/end_game.png',
    label: 'End game',
    detail: 'Marks the game finished for good. It can be looked at later, but '
        'nothing can be paid, traded or joined in it again.',
    color: Color(0xFFC62828),
  );

  static const GameControl handOver = GameControl(
    icon: Icons.swap_horiz,
    art: 'assets/Icons/hand_over.png',
    label: 'Hand over the bank',
    detail: 'Shows a QR another player scans to become the banker, with the '
        'bank balance exactly as it is now.',
    color: Color(0xFF2E7D32),
  );

  /// The menu button itself: the same paper sticker as the actions, drawn as
  /// three dots. Used where a screen has more actions than fit in one row.
  static const GameControl menu = GameControl(
    icon: Icons.more_horiz,
    label: 'Game menu',
    detail: 'Pause, end or hand over the bank, and the way out of this table.',
    color: Color(0xFF4E342E),
  );
}

/// A game action as an icon-only sticker button.
///
/// The screens use icons instead of labelled buttons, so the label lives in the
/// tooltip and in the semantics tree: a sighted player gets it on hover, a
/// screen reader reads it, and the legend sheet spells it out.
class GameIconButton extends StatelessWidget {
  const GameIconButton({
    super.key,
    required this.control,
    required this.onPressed,
    this.size = 48,
    this.width,
    this.height,
    this.fill = false,
    this.enabled = true,
    this.artScale,
  });

  final GameControl control;
  final VoidCallback? onPressed;

  /// The square the sticker occupies. App bars get the compact size; the
  /// action rows under the balance card get the full touch target.
  final double size;

  /// A tile that is not a square, for a grid whose cells divide the space they
  /// are given rather than sitting at a fixed size in it. Defaults to [size].
  final double? width;
  final double? height;

  /// True when the tile is handed a cell and should fill it, rather than
  /// drawing at its own size inside it. The wide wallet grid works this way so
  /// its stickers leave no bare paper between them.
  final bool fill;
  final bool enabled;

  /// How much of [size] the illustrated art fills. Most icons are drawn with a
  /// margin around them; a deck of cards is a tall face and wants more of the
  /// tile, or it is only a sliver of paper in the middle. Null takes the
  /// control's own [GameControl.artScale], so one icon can fill more of its
  /// tile than the rest without every call site saying so.
  final double? artScale;

  double get _artScale => artScale ?? control.artScale;

  bool get _active => enabled && onPressed != null;

  /// The smaller of the tile's two sides: the artwork is square, so this is
  /// what it has to fit inside.
  double get _shorterSide {
    final double w = width ?? size;
    final double h = height ?? size;
    return w < h ? w : h;
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColour =
        _active ? control.color : GameControlStyle.ink.withValues(alpha: 0.38);
    return Tooltip(
      message: control.label,
      // The Semantics below already carries the label; without this the
      // tooltip's own node doubles it ("Board Board") for a screen reader.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: _active,
        label: control.label,
        hint: control.detail,
        child: Material(
          color: _active ? GameControlStyle.paper : GameControlStyle.disabled,
          // No outline: the soft shadow is what lifts the tile off the paper.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(size * 0.32),
          ),
          elevation: _active ? 2.5 : 0,
          shadowColor: Colors.brown.shade200,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _active ? onPressed : null,
            child: SizedBox(
              // A filled tile takes the whole cell; the others keep their own
              // size, which is what the app bars and phone rows want.
              width: fill ? double.infinity : width ?? size,
              height: fill ? double.infinity : height ?? size,
              child: Center(
                // The artwork is drawn from the shorter side, so an oblong
                // tile keeps a round-looking icon in the middle of it.
                child: control.art == null
                    ? fill
                        // A filled tile has no side to multiply, so the glyph
                        // is drawn large and scaled down to the space it is
                        // given.
                        ? FractionallySizedBox(
                            widthFactor: _artScale,
                            heightFactor: _artScale,
                            child: FittedBox(
                              child: Icon(
                                control.icon,
                                size: 64,
                                color: iconColour,
                              ),
                            ),
                          )
                        : Icon(
                            control.icon,
                            size: _shorterSide * 0.52,
                            color: iconColour,
                          )
                    // The illustrated icons are drawn full colour and fade
                    // rather than take the disabled ink, so a disabled tile
                    // still reads as the same picture.
                    : Opacity(
                        opacity: _active ? 1 : 0.38,
                        child: fill
                            ? Padding(
                                padding: EdgeInsets.all(
                                  size * (1 - _artScale) / 2,
                                ),
                                child: Image.asset(
                                  control.art!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Image.asset(
                                control.art!,
                                width: _shorterSide * _artScale,
                                height: _shorterSide * _artScale,
                                fit: BoxFit.contain,
                              ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The info button: the same sticker, always in the corner of a game screen.
class GameInfoButton extends StatelessWidget {
  const GameInfoButton({
    super.key,
    required this.title,
    required this.controls,
    this.size = 36,
  });

  /// The screen name, e.g. "Banker controls".
  final String title;
  final List<GameControl> controls;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GameIconButton(
      control: GameControls.info,
      size: size,
      onPressed: () => showGameControlsSheet(
        context,
        title: title,
        controls: controls,
      ),
    );
  }
}

/// The legend: one row per icon, with the sentence that explains it.
///
/// Opened from the info button rather than from a help page, so the list is
/// always exactly the buttons on the screen that opened it.
Future<void> showGameControlsSheet(
  BuildContext context, {
  required String title,
  required List<GameControl> controls,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: GameControlStyle.paper,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.info_outline,
                      color: Color(0xFF1565C0), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF33691E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Every icon on this screen, and what it does.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF558B2F),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: controls.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 14,
                    color: Color(0xFFE6DCC3),
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final GameControl control = controls[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Not tappable and not announced: this is the legend
                        // of the icon, and the name beside it is the label.
                        ExcludeSemantics(
                          child: IgnorePointer(
                            child: GameIconButton(
                              control: control,
                              onPressed: () {},
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                control.label,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF4E342E),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                control.detail,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.3,
                                  color: Color(0xFF6D4C41),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The paper tile that opens a game menu.
///
/// Placed as the `child` of a [PopupMenuButton], so it looks exactly like the
/// action stickers beside it while the menu carries the actions that do not fit
/// in the row any more.
class GameMenuTile extends StatelessWidget {
  const GameMenuTile({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: GameControls.menu.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: GameControlStyle.paper,
          borderRadius: BorderRadius.circular(size * 0.32),
          border: Border.all(color: const Color(0xFFE6DCC3)),
        ),
        child: Icon(
          Icons.more_horiz,
          size: size * 0.58,
          color: GameControls.menu.color,
        ),
      ),
    );
  }
}

/// One row of a game menu: the action's own drawing, then its name.
class GameMenuRow extends StatelessWidget {
  const GameMenuRow({super.key, required this.control});

  final GameControl control;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (control.art != null)
          Image.asset(control.art!, width: 22, height: 22, fit: BoxFit.contain)
        else
          Icon(control.icon, size: 20, color: control.color),
        const SizedBox(width: 10),
        Text(control.label),
      ],
    );
  }
}
