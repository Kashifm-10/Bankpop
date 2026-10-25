import 'package:flutter/material.dart';
import 'package:mon/widgets/app_content.dart';

/// The house rules, as the app enforces them.
///
/// Two kinds of sentence are on this page, and they are deliberately kept
/// apart: what the app *does* (it refuses a build without the full set, it
/// pays 10% to unmortgage) and what happens on the table and is settled by
/// hand (rent, jail, chance cards). A rule the app does not check is described
/// as a table rule, so nobody expects the app to have stopped them.
class GameRulesScreen extends StatelessWidget {
  const GameRulesScreen({super.key});

  static const List<_RuleSection> _sections = <_RuleSection>[
    _RuleSection(
      icon: Icons.tune,
      title: 'Setting up',
      rules: <String>[
        'The banker decides the total in the bank, the cash each player starts '
            'with, and the amount the bank pays when a player passes GO. Those '
            'three numbers are saved with the game and are the same for '
            'everyone at the table.',
        'The banker also chooses how money moves: ScanPay (QR codes) or '
            'InstantPay (tap a player to pay them).',
        'If the table is using the board, the banker turns on Play with Cards. '
            'Only then are cards, houses, mortgages and trades available.',
      ],
    ),
    _RuleSection(
      icon: Icons.directions_walk,
      title: 'A turn',
      rules: <String>[
        'Roll and move on the physical board. The app does not roll for you and '
            'does not track which square you are on.',
        'When you pass GO, the banker pays the round advance to you from the '
            'bank; it is recorded like any other payment.',
        'Landing on a property, a tax square, Chance or Community Chest is '
            'settled between the players and the banker. The app records the '
            'money, not the card.',
        'Jail, bail and getting out of jail follow the board game you are '
            'playing; the app has no jail button and cannot keep you in.',
      ],
    ),
    _RuleSection(
      icon: Icons.home_work_outlined,
      title: 'Buying property',
      rules: <String>[
        'A player buys an unowned property by paying its printed price to the '
            'bank. In a cards game the banker then hands over the card with '
            'Give Card, and the buyer scans it into My Cards.',
        'In a game without cards, the deed stays physical and the payment is '
            'recorded in the app so the balances stay true.',
        'A property can only change hands through a purchase, a trade or the '
            'banker removing a player.',
      ],
    ),
    _RuleSection(
      icon: Icons.request_quote_outlined,
      title: 'Rent',
      rules: <String>[
        'Rent is paid by the player who landed on the property to its owner, '
            'through the app, so the banker has a record of it.',
        'The amount is the one printed on the card: a mortgage on the card '
            'means no rent is collected on it.',
        'Station rent grows with how many stations the same owner holds. '
            'Utility rent depends on the dice, as printed on the card.',
        'Rent is never paid on a property the bank owns.',
      ],
    ),
    _RuleSection(
      icon: Icons.apartment,
      title: 'Houses and hotels',
      rules: <String>[
        'Build only on colour properties. Stations and utilities never take '
            'houses or hotels.',
        'You must own every property in that colour set before the first '
            'house goes up.',
        'Build evenly: no card in the set may be more than one house ahead of '
            'the others, and the same rule applies in reverse when you sell.',
        'Four houses on every card in the set, then a hotel. A hotel replaces '
            'the four houses on that card.',
        'Nothing can be built on a set while any card in it is mortgaged.',
        'Selling a building back to the bank pays half what it cost, and only '
            'when the set is being sold evenly. Selling a hotel returns the '
            'four houses it replaced.',
      ],
    ),
    _RuleSection(
      icon: Icons.account_balance_outlined,
      title: 'Mortgages',
      rules: <String>[
        'Mortgaging a property pays the player half its printed price from the '
            'bank. The card stays with its owner, marked as mortgaged.',
        'A mortgaged property collects no rent.',
        'Unmortgaging costs the mortgage value plus 10% interest to the bank.',
        'A mortgage is only allowed once the buildings on that colour set have '
            'been sold back - the bank will not mortgage a property with '
            'houses standing on the set.',
        'When a mortgaged card changes hands in a trade, the new owner pays '
            'the bank the 10% interest on it.',
      ],
    ),
    _RuleSection(
      icon: Icons.handshake_outlined,
      title: 'Trades',
      rules: <String>[
        'Players may trade properties, cash, or both. A trade that includes a '
            'mortgaged property settles its interest with the bank first.',
        'The other player has to accept, and the banker sees the deal too - '
            'nothing changes hands until both sides agree.',
        'A trade moves the cards and the money together, so the board and the '
            'wallets cannot disagree afterwards.',
      ],
    ),
    _RuleSection(
      icon: Icons.flag_outlined,
      title: 'Bankruptcy and removal',
      rules: <String>[
        'A player who cannot pay is out of the game. The banker removes them '
            'with the red person icon.',
        'Removal puts their cash into the bank, and their cards back on the '
            'market with any buildings taken off first. The seat keeps a '
            'REMOVED badge.',
        'A removed player cannot rejoin that game, but the banker can seat '
            'them again with a fresh request if the table agrees.',
      ],
    ),
    _RuleSection(
      icon: Icons.pause_circle_outline,
      title: 'Pausing and ending',
      rules: <String>[
        'The banker can pause the game for everyone, for a break or a rule '
            'argument. Nothing can be paid, advanced, built or traded while it '
            'is paused.',
        'Resuming is the banker\'s call; the amber banner on every screen '
            'says who paused it, and the banker gets Resume there.',
        'Ending a game is final. The table becomes read-only, the red banner '
            'keeps the date it ended, and no player can join it again.',
        'An ended or paused game is still in Your Games. Opening it shows the '
            'table as it was, with its controls disabled and the banner on '
            'top.',
      ],
    ),
    _RuleSection(
      icon: Icons.style_outlined,
      title: 'Cards mode',
      rules: <String>[
        'The board popup shows every card and who owns it. Tapping a card '
            'opens its deed, including rent, house prices and mortgage value.',
        'The banker sells cards with Give Card; the buyer scans the sale QR. '
            'The money and the card move in one step.',
        'A card bought back by the bank, or returned when its owner is '
            'removed, goes back on the market without its buildings.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF689F38),
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
          const _IntroCard(),
          const SizedBox(height: 14),
          for (final _RuleSection section in _sections) section,
          const SizedBox(height: 4),
          const Text(
            'Anything the page describes as a table rule is not enforced by '
            'the app: agree it at the table, and let the banker settle it.',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              height: 1.4,
              color: Color(0xFF7CB342),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFE8F5E9),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.balance, color: Color(0xFF2E7D32)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'These are the rules this app follows. It is a money keeper, '
                'not a referee: it enforces the arithmetic it can see - '
                'building, mortgages, trades, who may move money - and leaves '
                'the board to the table.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleSection extends StatelessWidget {
  const _RuleSection({
    required this.icon,
    required this.title,
    required this.rules,
  });

  final IconData icon;
  final String title;
  final List<String> rules;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF9C4),
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: const Color(0xFFF57F17)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF827717),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final String rule in rules)
              Padding(
                padding: const EdgeInsets.only(left: 26, bottom: 5),
                child: Text(
                  rule,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF6D4C41),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
