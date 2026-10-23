import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/routes.dart';

/// The guide the home screen's "How to use" card opens.
///
/// This used to be a dialog. On a phone the dialog had a fixed height and two
/// tabs, so the text either scrolled inside a small box or got cut off; in the
/// browser it had no address, so it could not be linked, bookmarked or walked
/// back out of. As a screen it has both, and there is room for the parts added
/// since the dialog was written: accounts and verification, a temporary
/// password, pausing and ending a game, and the web build's own behaviour.
class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF8E1),
        appBar: AppBar(
          backgroundColor: const Color(0xFF689F38),
          foregroundColor: Colors.white,
          title: const Text(
            'How to use',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            indicatorColor: Color(0xFFFFF9C4),
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFDCEDC8),
            tabs: <Widget>[
              Tab(text: 'As a player'),
              Tab(text: 'As the banker'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _GuideTab(
              lead: 'Joining a table, paying, cards and houses - and what the '
                  'banner at the top of a game means.',
              sections: _playerSections,
              webNote: true,
            ),
            _GuideTab(
              lead: 'Opening a table, seating players, and keeping the bank '
                  'honest.',
              sections: _bankerSections,
              webNote: false,
            ),
          ],
        ),
      ),
    );
  }

  static const List<_GuideSection> _playerSections = <_GuideSection>[
    _GuideSection(
      icon: Icons.login,
      title: 'Getting in',
      lines: <String>[
        'Play as a guest: the whole app works, and your games stay on this '
            'device.',
        'Sign in with an account when you want the same games on another '
            'phone or in a browser.',
        'A new account needs an email, a password and the same password typed '
            'again. We send a verification link - open it, then come back and '
            'sign in. Until it is opened, signing in is refused.',
        'Forgot the password? "Forgot password?" on the sign-in screen emails '
            'a temporary one. It is not your real password: signing in with '
            'it takes you straight to a screen where you choose a new one, '
            'and only then does your real password change.',
      ],
    ),
    _GuideSection(
      icon: Icons.qr_code_scanner,
      title: 'Join a game',
      lines: <String>[
        'Start Game -> Play as a Player.',
        'Scan the banker\'s QR code, or type the game ID by hand.',
        'The banker accepts the request, and your starting cash appears in '
            'your wallet.',
        'A REMOVED badge means the banker took your seat away. Cash and cards '
            'went back to the bank, and you cannot rejoin this game unless the '
            'banker seats you again.',
      ],
    ),
    _GuideSection(
      icon: Icons.payments_outlined,
      title: 'Pay and get paid',
      lines: <String>[
        'ScanPay: scan the QR in the other player\'s wallet screen.',
        'InstantPay: tap the pay icon on their row in the player list.',
        'Every payment is listed under the history icon at the top of the '
            'screen, and the banker sees the same list.',
        'The wallet QR on your own screen is what someone else scans to pay '
            'you.',
      ],
    ),
    _GuideSection(
      icon: Icons.style_outlined,
      title: 'Cards, houses and deals',
      lines: <String>[
        'Only in a game where the banker switched on Play with Cards.',
        'Buying a property: the banker uses Give Card, and you scan the sale '
            'QR with ScanPay. The card appears in My Cards.',
        'Build only when you own every card in that colour set, and build '
            'evenly: every card in the set needs its next house before any '
            'card takes another. Four houses on every card, then a hotel.',
        'Nothing can be built while any card in the set is mortgaged, and '
            'stations and utilities never take houses.',
        'Mortgage, unmortgage, sell a building and trade from My Cards. The '
            'banker or the other player approves the request before it '
            'happens.',
        'The board icon shows who owns what; tapping a card there opens its '
            'deed.',
      ],
    ),
    _GuideSection(
      icon: Icons.pause_circle_outline,
      title: 'Paused or ended',
      lines: <String>[
        'A banner at the top of the table always says which state the game is '
            'in.',
        'Paused: everything freezes where it is. Your cash and cards are kept, '
            'and only the banker can resume the game.',
        'Ended: the banner carries the date. Nothing can be paid, traded, '
            'built, advanced or joined again, but the table still opens so you '
            'can look at your holdings.',
        'Both kinds still appear in Your Games, so a paused or finished game '
            'is always one tap away.',
      ],
    ),
  ];

  static const List<_GuideSection> _bankerSections = <_GuideSection>[
    _GuideSection(
      icon: Icons.play_circle_outline,
      title: 'Start a game',
      lines: <String>[
        'Start Game -> Become a Banker.',
        'Enter the bank total, the cash each player starts with, and the '
            'amount paid when a player passes GO.',
        'Choose ScanPay (QR codes) or InstantPay (tap to pay).',
        'Turn on Play with Cards if you are using the board, then check the '
            'summary and start the game.',
        'The game ID and the Join Game QR are what the other players use to '
            'find the table.',
      ],
    ),
    _GuideSection(
      icon: Icons.person_add_alt,
      title: 'Seat players',
      lines: <String>[
        'A request appears when someone scans your Join Game QR or types the '
            'game ID.',
        'Accept moves their stake out of the bank and seats them. Reject '
            'leaves them outside the game.',
        'A player who was removed cannot ask again; seat them with a fresh '
            'request if you change your mind.',
      ],
    ),
    _GuideSection(
      icon: Icons.tune,
      title: 'The row of icons',
      lines: <String>[
        'QR: the Join Game code to show the table.',
        'History: every payment, purchase and building in the game.',
        'Board: who owns which card, in a cards game.',
        'Receive: take a payment into the bank, by scan or by hand.',
        'Give Card: sell a board card, with its sale QR.',
        'Pause / end: suspend the game for everyone, or finish it for good.',
        'The info icon explains each button on the screen you are looking at.',
      ],
    ),
    _GuideSection(
      icon: Icons.person_remove_alt_1,
      title: 'Remove a player',
      lines: <String>[
        'Tap the red person icon at the end of their row.',
        'Their cash, their cards and any houses or hotels go back to the bank.',
        'The row keeps a REMOVED badge; the seat is not taken by anybody '
            'else.',
      ],
    ),
    _GuideSection(
      icon: Icons.shield_moon_outlined,
      title: 'Pause, resume, hand over, end',
      lines: <String>[
        'Pause freezes the table for everyone, including you. The amber banner '
            'names the banker, and Resume sits in that banner on the banker\'s '
            'device.',
        'Hand over the bank when someone else takes the ledger; the new banker '
            'gets the same controls.',
        'End finishes the game for good. The table becomes read-only and the '
            'red banner keeps the date it ended.',
        'An ended game is not reopened automatically when the app starts.',
      ],
    ),
    _GuideSection(
      icon: Icons.lock_outline,
      title: 'Your own account',
      lines: <String>[
        'The banker needs an account too if the games should follow them to '
            'another device.',
        'Creating one sends a verification link; signing in is allowed after '
            'it is opened.',
        'Change the password from Profile -> Change password, where the '
            'current password is asked for first.',
      ],
    ),
  ];
}

class _GuideTab extends StatelessWidget {
  const _GuideTab({
    required this.lead,
    required this.sections,
    required this.webNote,
  });

  final String lead;
  final List<_GuideSection> sections;
  final bool webNote;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        Text(
          lead,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: Color(0xFF558B2F),
          ),
        ),
        const SizedBox(height: 14),
        for (final _GuideSection section in sections) section,
        if (webNote) ...<Widget>[
          const _GuideSection(
            icon: Icons.public,
            title: 'In the browser',
            lines: <String>[
              'Every screen has its own address. Refreshing keeps the screen '
                  'you are on, and a link can be bookmarked or sent to the '
                  'other players.',
              'The browser\'s back button walks back through the screens you '
                  'visited; it does not leave the table by accident.',
              'Scrollbars are hidden on purpose - drag, scroll or use the '
                  'arrow keys. The page still scrolls.',
            ],
          ),
        ],
        const SizedBox(height: 6),
        Card(
          color: const Color(0xFFFFF9C4),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            leading:
                const Icon(Icons.menu_book_outlined, color: Color(0xFFF57F17)),
            title: const Text(
              'The rules of the game',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF827717),
              ),
            ),
            subtitle: const Text(
              'Money, rent, builds, mortgages, trades, jail and ending a game '
              '- what this app expects at the table.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF9E7B18)),
            ),
            trailing: const Icon(Icons.chevron_right, color: Color(0xFFF57F17)),
            onTap: () => context.push(AppRoutes.gameRules),
          ),
        ),
      ],
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: const Color(0xFF689F38)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF33691E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final String line in lines)
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 4),
              child: Text(
                line,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF558B2F),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
