import 'package:flutter/material.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/guide_kit.dart';

/// The house rules, as the app enforces them.
///
/// Two kinds of sentence are on this page, and they are kept visibly apart:
/// what the app *does* (it refuses a build without the full set, it pays 10% to
/// unmortgage) and what happens on the table and is settled by hand (rent, jail,
/// dice). Each card is badged green when the app checks it and amber when the
/// table owns it, so nobody expects the app to have stopped them.
class GameRulesScreen extends StatelessWidget {
  const GameRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GuideStyle.paper,
      appBar: AppBar(
        backgroundColor: GuideStyle.green,
        foregroundColor: Colors.white,
        title: const Text(
          'Game rules',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: AppContent(
        maxWidth: 820,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          children: <Widget>[
            const GuideHero(
              icon: Icons.balance,
              title: 'How this table settles things',
              subtitle: 'These are the rules this app follows. It is a money '
                  'keeper, not a referee: it enforces the arithmetic it can see '
                  '- building, mortgages, trades, who may move money - and '
                  'leaves the board to the table.',
              chips: <String>[
                'Build evenly',
                '4 houses, then a hotel',
                'Unmortgage +10%',
                'Buildings sell at half',
              ],
            ),
            const SizedBox(height: 12),
            const _TagLegend(),
            const SizedBox(height: 8),
            for (int i = 0; i < _rules.length; i++) _rules[i].asCard(i + 1),
            const SizedBox(height: 2),
            const GuideFootnote(
              text: 'An amber card is a table rule: the app will not stop you, '
                  'so agree it at the table and let the banker settle it. A '
                  'green card is checked by the app itself.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Says, once, what the two badge colours mean - every card below leans on it.
class _TagLegend extends StatelessWidget {
  const _TagLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        _LegendChip(
          label: 'Green: the app enforces it',
          color: GuideStyle.greenDeep,
          fill: GuideStyle.soft,
        ),
        _LegendChip(
          label: 'Amber: settle it at the table',
          color: GuideStyle.amberInk,
          fill: GuideStyle.amberCard,
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
    required this.fill,
  });

  final String label;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _Rule {
  const _Rule({
    required this.icon,
    required this.title,
    required this.tag,
    required this.lines,
    this.appEnforced = true,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String tag;
  final List<String> lines;
  final bool appEnforced;
  final String? footer;

  Widget asCard(int number) => GuideCard(
        number: number,
        icon: icon,
        title: title,
        tag: tag,
        tagColor: appEnforced ? GuideStyle.greenDeep : GuideStyle.amberInk,
        lines: lines,
        footer: footer,
      );
}

const List<_Rule> _rules = <_Rule>[
  _Rule(
    icon: Icons.tune,
    title: 'Setting up',
    tag: 'The banker sets it, once',
    lines: <String>[
      'The banker decides the total in the bank, the cash each player starts '
          'with, and the amount the bank pays when a player passes GO. Those '
          'three numbers are saved with the game and are the same for everyone '
          'at the table.',
      'The banker also chooses how money moves: ScanPay (QR codes) or '
          'InstantPay (tap a player to pay them). It cannot change mid-game.',
      'If the table is using the board, the banker turns on Play with Cards. '
          'Only then are cards, houses, mortgages, trades and the two packs '
          'available.',
    ],
  ),
  _Rule(
    icon: Icons.directions_walk,
    title: 'A turn',
    tag: 'Settled at the table',
    appEnforced: false,
    lines: <String>[
      'Roll and move on the physical board. The app does not roll for you and '
          'does not track which square you are on.',
      'When you pass GO, the banker pays the round advance to you from the '
          'bank; it is recorded like any other payment, and the banker confirms '
          'it first.',
      'Landing on a property, a tax square, Chance or Community Chest is '
          'settled between the players and the banker. In a cards game the app '
          'can show the card and collect or pay its amount, but it never decides '
          'the move.',
      'Jail, bail and getting out of jail follow the board game you are '
          'playing; the app has no jail button and cannot keep you in.',
    ],
  ),
  _Rule(
    icon: Icons.home_work_outlined,
    title: 'Buying property',
    tag: 'The app records the sale',
    lines: <String>[
      'A player buys an unowned property by paying its printed price to the '
          'bank. In a cards game the banker then hands over the card with Give '
          'Card, and the buyer scans it into My cards.',
      'In a game without cards the deed stays physical and the payment is '
          'recorded in the app so the balances stay true.',
      'A property can only change hands through a purchase, a trade or the '
          'banker removing a player - and a card that is already owned cannot '
          'be sold again.',
    ],
  ),
  _Rule(
    icon: Icons.request_quote_outlined,
    title: 'Rent',
    tag: 'Settled at the table',
    appEnforced: false,
    lines: <String>[
      'Rent is paid by the player who landed on the property to its owner, '
          'through the app, so the banker has a record of it.',
      'The amount is the one printed on the card: a mortgage on the card means '
          'no rent is collected on it.',
      'Station rent grows with how many stations the same owner holds. Utility '
          'rent depends on the dice, as printed on the card.',
      'Rent is never paid on a property the bank owns.',
    ],
  ),
  _Rule(
    icon: Icons.apartment,
    title: 'Houses and hotels',
    tag: 'The app enforces it',
    lines: <String>[
      'Build only on colour properties. Stations and utilities never take '
          'houses or hotels.',
      'You must own every property in that colour set before the first house '
          'goes up.',
      'Build evenly: no card in the set may be more than one house ahead of the '
          'others, and the same rule applies in reverse when you sell.',
      'Four houses on every card in the set, then a hotel. A hotel replaces the '
          'four houses on that card.',
      'Nothing can be built on a set while any card in it is mortgaged.',
      'Selling a building back to the bank pays half what it cost, and only '
          'when the set is being sold evenly. Selling a hotel returns the four '
          'houses it replaced.',
    ],
    footer: 'The app refuses a build that breaks any of these, so a set cannot '
        'end up uneven by accident.',
  ),
  _Rule(
    icon: Icons.account_balance_outlined,
    title: 'Mortgages',
    tag: 'The app enforces it',
    lines: <String>[
      'Mortgaging a property pays the player half its printed price from the '
          'bank. The card stays with its owner, marked as mortgaged.',
      'A mortgaged property collects no rent.',
      'Unmortgaging costs the mortgage value plus 10% interest to the bank.',
      'A mortgage is only allowed once the buildings on that colour set have '
          'been sold back - the bank will not mortgage a property with houses '
          'standing on the set.',
      'When a mortgaged card changes hands in a trade, the new owner pays the '
          'bank the 10% interest on it.',
    ],
  ),
  _Rule(
    icon: Icons.handshake_outlined,
    title: 'Trades',
    tag: 'The app enforces it',
    lines: <String>[
      'Players may trade properties, cash, or both. A trade that includes a '
          'mortgaged property settles its interest with the bank first.',
      'The other player has to accept, and the banker sees the deal too - '
          'nothing changes hands until both sides agree.',
      'A trade moves the cards and the money together, so the board and the '
          'wallets cannot disagree afterwards.',
    ],
  ),
  _Rule(
    icon: Icons.flag_outlined,
    title: 'Bankruptcy and removal',
    tag: 'The app enforces it',
    lines: <String>[
      'A player who cannot pay is out of the game. They can declare bankrupt, '
          'or the banker removes them from their row.',
      'Either way their cash goes into the bank and their cards go back on the '
          'market with any buildings taken off first. The seat keeps a REMOVED '
          'badge.',
      'A removed player cannot rejoin that game, but the banker can seat them '
          'again with a fresh request if the table agrees.',
    ],
  ),
  _Rule(
    icon: Icons.casino_outlined,
    title: 'Chance and Community Chest',
    tag: 'The app deals them',
    lines: <String>[
      'In a cards game both packs live on the board and are dealt in the same '
          'order for everyone, so the table cannot disagree about what came '
          'up.',
      'A dealt card shows its own amount: the green button pays the reward or '
          'takes the payment the card names, and nothing is left to remember.',
      'The count on a pack is how many cards are unseen. A pack that has been '
          'worked through is shuffled again, and the banker can shuffle on '
          'purpose at any time.',
      'A Get out of Jail Free card that a player is holding is out of the pack '
          'until it is used, so a shuffle never deals it back to somebody else.',
    ],
  ),
  _Rule(
    icon: Icons.pause_circle_outline,
    title: 'Pausing and ending',
    tag: 'The app enforces it',
    lines: <String>[
      'The banker can pause the game for everyone, for a break or a rule '
          'argument. Nothing can be paid, advanced, built or traded while it is '
          'paused.',
      'Resuming is the banker\'s call; the amber banner on every screen says '
          'who paused it, and the banker gets Resume there.',
      'Ending a game is final. The table becomes read-only, the red banner '
          'keeps the date it ended, and no player can join it again.',
      'An ended or paused game is still in Your Games. Opening it shows the '
          'table as it was, with its controls disabled and the banner on top.',
    ],
  ),
  _Rule(
    icon: Icons.style_outlined,
    title: 'Cards mode',
    tag: 'The app enforces it',
    lines: <String>[
      'The board is on the screen: it shows every card and who owns it, and '
          'tapping one opens its deed, with rent, house prices and mortgage '
          'value.',
      'The banker sells cards with Give Card; the buyer scans the sale QR. The '
          'money and the card move in one step.',
      'A card bought back by the bank, or returned when its owner is removed, '
          'goes back on the market without its buildings.',
      'With cards off, the app is a ledger only: no cards, no houses, no '
          'trades - money still moves and is still recorded.',
    ],
  ),
];
