import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/routes.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/game_controls.dart';
import 'package:mon/widgets/guide_kit.dart';

/// The guide the home screen's "How to use" card opens.
///
/// This used to be a dialog; it is a screen because a dialog had a fixed height,
/// two tabs squeezed into a small box, and no address in the browser. It is no
/// longer a wall of paragraphs either: each tab opens with the four moves a new
/// player needs (the strip at the top), then numbers the rest so a reader can
/// come back to "card 4", and draws the game's own buttons beside the words that
/// describe them.
class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: GuideStyle.paper,
        appBar: AppBar(
          backgroundColor: GuideStyle.green,
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
        body: const AppContent(
          maxWidth: 900,
          child: TabBarView(
            children: <Widget>[
              _PlayerGuide(),
              _BankerGuide(),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the two tabs share: the page they sit in, and the way out to the rules.
class _GuideBody extends StatelessWidget {
  const _GuideBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        ...children,
        const SizedBox(height: 4),
        const _RulesCard(),
      ],
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: GuideStyle.amberCard,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: const Icon(Icons.menu_book_outlined, color: Color(0xFFF57F17)),
        title: const Text(
          'The rules of the game',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: GuideStyle.amberInk,
          ),
        ),
        subtitle: const Text(
          'Rent, houses, mortgages, trades and jail - what this app expects at '
          'the table.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF9E7B18)),
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFFF57F17)),
        onTap: () => context.push(AppRoutes.gameRules),
      ),
    );
  }
}

class _PlayerGuide extends StatelessWidget {
  const _PlayerGuide();

  @override
  Widget build(BuildContext context) {
    return const _GuideBody(
      children: <Widget>[
        GuideHero(
          icon: Icons.person_outline,
          title: 'You are sitting at the table',
          subtitle: 'Join a game, move money, buy and build - and know what '
              'every icon on your screen does. Four moves get you playing.',
          chips: <String>[
            'Guest or account',
            'ScanPay or InstantPay',
            'Cards optional',
          ],
        ),
        SizedBox(height: 14),
        GuideQuickStart(
          stops: <GuideStop>[
            GuideStop(
              icon: Icons.qr_code_scanner,
              label: 'Join',
              detail: 'Start Game -> Play as a player, then scan the banker\'s '
                  'QR or type the code.',
            ),
            GuideStop(
              icon: Icons.event_seat_outlined,
              label: 'Sit down',
              detail: 'The banker accepts you, and your starting cash lands in '
                  'your wallet.',
            ),
            GuideStop(
              icon: Icons.casino_outlined,
              label: 'Play',
              detail: 'Pay, buy, build and trade as the board says - the app '
                  'keeps the money straight.',
            ),
            GuideStop(
              icon: Icons.logout,
              label: 'Leave',
              detail: 'Leave game (or back) asks first. The table carries on '
                  'without you.',
            ),
          ],
        ),
        SizedBox(height: 10),
        GuideCallout(
          text: 'The info icon in the corner of a game screen lists every '
              'button on that screen, in the same words this page uses.',
        ),
        GuideCard(
          number: 1,
          icon: Icons.login,
          title: 'Getting in',
          lines: <String>[
            'Play as a guest: the whole app works, and your games stay on this '
                'device.',
            'Sign in with an account when you want the same games on another '
                'phone or in a browser.',
            'A new account needs an email, a password and the same password '
                'again. We send a verification link - open it, then sign in. '
                'Until it is opened, signing in is refused.',
            'Email never arrived? The sign-up screen and the sign-in screen '
                'both offer to resend it, and an unverified account shows as '
                'pending.',
            'Forgot the password? "Forgot password?" emails a temporary one. '
                'Signing in with it opens a screen to choose a new password, '
                'and only then does the old one stop working.',
          ],
        ),
        GuideCard(
          number: 2,
          icon: Icons.meeting_room_outlined,
          title: 'Join a table',
          lines: <String>[
            'The banker shows a Join QR, or reads out the Game ID.',
            'Scan it with your camera, or type the code by hand.',
            'The banker accepts the request, and your starting cash appears in '
                'your wallet.',
            'A REMOVED badge means the banker took your seat: your cash and '
                'cards went back to the bank, and you cannot ask to rejoin - '
                'the banker has to seat you with a fresh request.',
          ],
        ),
        GuideCard(
          number: 3,
          icon: Icons.payments_outlined,
          title: 'Money in and out',
          lines: <String>[
            'ScanPay: tap Scan and point it at the other player\'s wallet QR - '
                'or at the bank\'s sale QR to buy a card.',
            'InstantPay: tap Pay on a player\'s row and the amount goes '
                'straight to them, with no QR in between.',
            'Pay to bank sends money to the bank from your own balance.',
            'Every payment lands in Transactions, and both sides are told '
                'about it - money arriving reaches you even when you are '
                'looking at another screen.',
            'Passing GO: the banker pays the advance, and it is recorded like '
                'any other payment.',
          ],
        ),
        GuideCard(
          number: 4,
          icon: Icons.style_outlined,
          title: 'Buying a property',
          lines: <String>[
            'Only in a game where the banker switched on Play with Cards.',
            'The banker sells the card with Give Card; scan its QR and the card '
                'moves into My cards.',
            'Tap any property on the board to read its deed: rent, house '
                'price, mortgage value.',
            'In a cards game you may mortgage, sell buildings and trade from My '
                'cards - everything else stays physical.',
          ],
        ),
        GuideCard(
          number: 5,
          icon: Icons.apartment,
          title: 'Houses and hotels',
          lines: <String>[
            'Own every card in the colour set before the first house goes up.',
            'Build evenly: no card may be more than one house ahead of the '
                'others, and selling follows the same rule in reverse.',
            'Four houses on every card in the set, then a hotel - a hotel '
                'replaces that card\'s four houses.',
            'Nothing can be built while any card in the set is mortgaged; '
                'stations and utilities never take houses.',
            'Selling a building back to the bank pays half of what it cost.',
          ],
        ),
        GuideCard(
          number: 6,
          icon: Icons.handshake_outlined,
          title: 'Trades and requests',
          lines: <String>[
            'Trade builds an offer of cards, cash or both, and sends it to a '
                'player.',
            'The other player accepts, and the banker sees the deal too: '
                'nothing moves until both sides agree.',
            'A mortgaged card in a trade settles its 10% interest with the '
                'bank first.',
            'Some purchases need the banker: a request appears on their screen '
                'and clears once they answer it.',
          ],
        ),
        GuideCard(
          number: 7,
          icon: Icons.casino_outlined,
          title: 'Chance and Community Chest',
          lines: <String>[
            'The packs are the board itself, not a button: in a cards game '
                'Chance and Community Chest sit on the board, beside the square '
                'they belong to.',
            'Tap a pack to deal the next card, and a dialog shows the table '
                'what it asks for. There is no separate "draw a card" button '
                'any more - the pack you tap is the card you draw.',
            'The green button on that dialog pays you your reward, or takes the '
                'payment the card demands - the amount is the card\'s, not '
                'yours to choose.',
            'The numbers on a pack (19/22) are how many cards are left. The '
                'banker shuffles when a pack runs out, and a card in somebody\'s '
                'hand never comes back into the deal.',
          ],
        ),
        GuideCard(
          number: 8,
          icon: Icons.pause_circle_outline,
          title: 'Paused, ended, leaving',
          lines: <String>[
            'A banner at the top of the table always says which state the game '
                'is in.',
            'Paused: everything freezes. Your cash and cards are kept, and only '
                'the banker resumes the game.',
            'Ended: the banner carries the date. Nothing can be paid, traded, '
                'built, advanced or joined again, but the table still opens so '
                'you can look at your holdings.',
            'Leave game - or the phone\'s back button, or the browser\'s - asks '
                'before you go, and the game keeps running for everyone else.',
            'While your game is running you are kept at the table: other '
                'screens send you back to it until you leave on purpose.',
            'Both kinds still appear in Your Games, so a paused or finished '
                'game is one tap away.',
          ],
        ),
        GuideCard(
          number: 9,
          icon: Icons.public,
          title: 'In the browser',
          lines: <String>[
            'Every screen has its own address. Refreshing keeps the screen you '
                'are on, and a link can be bookmarked or sent to the other '
                'players.',
            'Back walks through the screens you visited; it does not drop you '
                'out of a table you are still in.',
            'Scrollbars are hidden on purpose - drag, scroll or use the arrow '
                'keys. The page still scrolls.',
          ],
        ),
        GuideHeading(
          text: 'The buttons on your screen',
          icon: Icons.touch_app_outlined,
        ),
        GuideButtonRow(control: GameControls.scan),
        GuideButtonRow(control: GameControls.history),
        GuideButtonRow(control: GameControls.board),
        GuideButtonRow(control: GameControls.chanceDeck),
        GuideButtonRow(control: GameControls.chestDeck),
        GuideButtonRow(control: GameControls.myCards),
        GuideButtonRow(control: GameControls.trade),
        GuideButtonRow(control: GameControls.receive),
        GuideButtonRow(control: GameControls.reward),
        GuideButtonRow(control: GameControls.bankrupt),
        GuideButtonRow(control: GameControls.leave),
        GuideCallout(
          icon: Icons.flag_outlined,
          warning: true,
          text: 'Declaring bankruptcy ends your game: your cash, houses and '
              'cards are sold and the money pays the players you owe.',
        ),
      ],
    );
  }
}

class _BankerGuide extends StatelessWidget {
  const _BankerGuide();

  @override
  Widget build(BuildContext context) {
    return const _GuideBody(
      children: <Widget>[
        GuideHero(
          icon: Icons.account_balance_outlined,
          title: 'You are running the bank',
          subtitle:
              'Open a table, seat the players, and keep the money honest. '
              'The bank never plays a turn - it records what the table agrees.',
          chips: <String>[
            'Bank total',
            'Starting cash',
            'Pass-GO advance',
            'Play with Cards',
          ],
          tint: Color(0xFF1E88E5),
        ),
        SizedBox(height: 14),
        GuideQuickStart(
          stops: <GuideStop>[
            GuideStop(
              icon: Icons.play_circle_outline,
              label: 'Open a table',
              detail: 'Start Game -> Become a banker. Set the bank total, the '
                  'stake and the advance.',
            ),
            GuideStop(
              icon: Icons.person_add_alt,
              label: 'Seat players',
              detail: 'Show the Join QR, then accept each request that comes '
                  'in.',
            ),
            GuideStop(
              icon: Icons.payments_outlined,
              label: 'Run the bank',
              detail: 'Receive money, sell cards, pay rewards and advances as '
                  'the table asks.',
            ),
            GuideStop(
              icon: Icons.flag_outlined,
              label: 'Close it',
              detail: 'Suspend for a break, or end the game for good once the '
                  'last property is counted.',
            ),
          ],
        ),
        SizedBox(height: 10),
        GuideCallout(
          text:
              'Nobody has joined yet? The players panel says so and carries a '
              '"Show join QR" button, so you never have to hunt for the code.',
        ),
        GuideCard(
          number: 1,
          icon: Icons.play_circle_outline,
          title: 'Start a game',
          lines: <String>[
            'Enter the bank total, the cash each player starts with, and the '
                'amount the bank pays when a player passes GO. Everyone at the '
                'table plays by those three numbers.',
            'Choose ScanPay (QR codes) or InstantPay (tap a player to pay '
                'them). The choice is fixed for the game.',
            'Turn on Play with Cards if the table is using the board: it is '
                'what puts cards, houses, mortgages, trades and the two packs '
                'on the screen.',
            'The board is always on your screen. You keep your place in the '
                'game even while you are reading a deed.',
          ],
          footer: 'The game ID and the Join QR are how the others find the '
              'table.',
        ),
        GuideCard(
          number: 2,
          icon: Icons.person_add_alt,
          title: 'Seat players',
          lines: <String>[
            'A request appears when someone scans your Join QR or types the '
                'game ID.',
            'Accept moves their stake out of the bank and seats them. Reject '
                'leaves them outside the game.',
            'A player you removed cannot ask again; seat them with a fresh '
                'request if the table agrees.',
            'The Join QR button opens it again whenever you need it.',
          ],
        ),
        GuideCard(
          number: 3,
          icon: Icons.tune,
          title: 'Your player rows',
          lines: <String>[
            'Each row carries the player\'s name, wallet and colour, with their '
                'actions at the end.',
            'Pay takes money from the bank to that player; Reward does the '
                'same for a card\'s payout or a bonus you decide on.',
            'Advance pays the pass-GO amount, and asks you to confirm first so '
                'a stray tap cannot pay twice.',
            'Remove takes the seat away: cash, cards and buildings go back to '
                'the bank, and the row keeps a REMOVED badge.',
            'A player who is gone has no pay or advance button left - there is '
                'nothing to pay them.',
          ],
        ),
        GuideCard(
          number: 4,
          icon: Icons.style_outlined,
          title: 'Selling a card',
          lines: <String>[
            'In a cards game, tap the property on the board to open its deed.',
            'Give Card shows the sale QR: the buyer scans it and the money and '
                'the card move in one step.',
            'In an InstantPay game the same button asks which player is buying '
                'and settles it directly.',
            'Nothing can be sold twice: a card that already has an owner shows '
                'whose it is.',
          ],
        ),
        GuideCard(
          number: 5,
          icon: Icons.handshake_outlined,
          title: 'Deals and requests',
          lines: <String>[
            'A trade the players agree on appears for you to see, and the cards '
                'and cash move together - the board and the wallets cannot '
                'disagree afterwards.',
            'Requests for a card, a mortgage or a building arrive in the queue '
                'and clear as you answer them.',
            'If a request stops making sense, reject it: the player is told, '
                'and nothing moves.',
          ],
        ),
        GuideCard(
          number: 6,
          icon: Icons.casino_outlined,
          title: 'The two packs',
          lines: <String>[
            'Chance and Community Chest sit on the board, on the squares they '
                'belong to, with a count of the cards left - there is no draw '
                'button in the app bar.',
            'Tap a pack to deal the next card; the dialog shows what it asks '
                'for and the green button pays or collects it.',
            'The shuffle mark on a pack reorders it - and asks you first, '
                'because the order the table is working through is thrown '
                'away.',
            'A pack that has been worked through shuffles itself; the count '
                'starts again.',
          ],
        ),
        GuideCard(
          number: 7,
          icon: Icons.shield_moon_outlined,
          title: 'Suspend, resume, hand over, end',
          lines: <String>[
            'Suspend freezes the table for everyone, including you. The amber '
                'banner names the banker, and Resume sits in that banner on '
                'your device.',
            'Hand the bank over with a QR from the same menu. Only somebody who '
                'is not already in the game can scan it, and you confirm the '
                'swap before anything moves.',
            'After a hand-over you stay as an ex-banker: you can watch, but not '
                'play or move money.',
            'End finishes the game for good. The table becomes read-only and '
                'the red banner keeps the date it ended.',
            'An ended game is never reopened automatically when the app starts.',
          ],
        ),
        GuideCard(
          number: 8,
          icon: Icons.lock_outline,
          title: 'Your own account',
          lines: <String>[
            'The banker needs an account too, if the games should follow them '
                'to another device.',
            'Creating one sends a verification link; signing in is allowed '
                'after it is opened.',
            'Change the password from Profile -> Change password, where the '
                'current password is asked for first.',
          ],
        ),
        GuideHeading(
          text: 'The buttons on your screen',
          icon: Icons.touch_app_outlined,
        ),
        GuideButtonRow(control: GameControls.showBankQr),
        GuideButtonRow(control: GameControls.history),
        GuideButtonRow(control: GameControls.board),
        GuideButtonRow(control: GameControls.chanceDeck),
        GuideButtonRow(control: GameControls.chestDeck),
        GuideButtonRow(control: GameControls.receive),
        GuideButtonRow(control: GameControls.giveCard),
        GuideButtonRow(control: GameControls.reward),
        GuideButtonRow(control: GameControls.suspend),
        GuideCallout(
          icon: Icons.info_outline,
          text:
              'The info icon opens the same list for whichever screen you are '
              'on, so the legend is always the buttons in front of you.',
        ),
      ],
    );
  }
}
