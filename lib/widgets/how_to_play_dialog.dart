import 'package:flutter/material.dart';
import 'package:mon/widgets/app_dialog.dart';

/// The guide behind the "How to use" card and the profile's "How to Play".
///
/// One place, so the two entry points cannot drift apart, and one function so
/// a test can open it directly at a small size.
class HowToPlayGuide {
  const HowToPlayGuide._();

  /// The in-app guide, rewritten for what the app actually does now.
  ///
  /// One short section per thing a player has to do, in the order they do it,
  /// with the icon they will look for on the screen. The old version repeated
  /// the same bullets under ScanPay and InstantPay, which told nobody what to
  /// tap - and it knew nothing about cards, houses, trades, pausing a game or
  /// the badges beside a name.
  static void show(BuildContext context) {
    final AppDialogPalette palette = AppDialogPalette.of(context);

    Widget section(IconData icon, String title, List<String> lines) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 17, color: palette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: palette.title,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...lines.map(
              (String line) => Padding(
                padding: const EdgeInsets.only(left: 25, bottom: 3),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: palette.body,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget tab(List<Widget> sections) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ...sections,
              Text(
                'Tap the info icon at the top of any screen to see what each '
                'button does.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: palette.body.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        );

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('How to play'),
          contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: DefaultTabController(
              length: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TabBar(
                    labelColor: palette.title,
                    unselectedLabelColor: palette.body.withValues(alpha: 0.6),
                    indicatorColor: palette.accent,
                    tabs: const <Widget>[
                      Tab(text: 'As a player'),
                      Tab(text: 'As the banker'),
                    ],
                  ),
                  SizedBox(
                    height: (MediaQuery.sizeOf(dialogContext).height - 270)
                        .clamp(200.0, 430.0),
                    child: TabBarView(
                      children: <Widget>[
                        tab(<Widget>[
                          section(Icons.login, 'Join a game', <String>[
                            'Start Game -> Play as a Player.',
                            'Scan the banker QR code, or type the 5-character '
                                'Game ID.',
                            'The banker accepts you, and your starting cash '
                                'appears in your wallet.',
                          ]),
                          section(
                              Icons.qr_code_scanner, 'Pay someone', <String>[
                            'ScanPay: scan the QR in their wallet screen.',
                            'InstantPay: tap the pay icon on their row in the '
                                'player list.',
                            'Every payment is listed under the history icon at '
                                'the top of the screen.',
                          ]),
                          section(Icons.style_outlined, 'Cards game', <String>[
                            'Only when the banker turned on Play with Cards.',
                            'The banker sells a property with Give Card: scan '
                                'the sale QR (ScanPay) and it lands in My Cards.',
                            'Build houses and hotels from My Cards. You need '
                                'the whole colour set, built evenly.',
                            'Trades, mortgages and selling a building are asked '
                                'from My Cards, and the banker or the other '
                                'player approves them.',
                          ]),
                          section(Icons.badge_outlined,
                              'What the badge means', <String>[
                            'REMOVED: the banker removed them. Their cash went '
                                'to the bank, their cards went back on the '
                                'market empty, and they cannot rejoin - though '
                                'the banker can put them back with a fresh '
                                'seat.',
                            'There is no online or offline badge: a phone that '
                                'is asleep still owns its seat, and leaving the '
                                'screen does not change anything.',
                          ]),
                          section(Icons.pause_circle_outline,
                              'Paused or ended', <String>[
                            'A paused game keeps your cash and cards - you come '
                                'back exactly where you stopped.',
                            'An ended game cannot change any more, but it stays '
                                'in Your Games.',
                          ]),
                        ]),
                        tab(<Widget>[
                          section(Icons.play_circle_outline,
                              'Start a game', <String>[
                            'Start Game -> Become a Banker.',
                            'Enter the bank total, the cash each player starts '
                                'with, and the round advance.',
                            'Choose ScanPay (QR codes) or InstantPay (tap to '
                                'pay).',
                            'Turn on Play with Cards if you are using the board, '
                                'then check the summary and tap Start Game.',
                          ]),
                          section(
                              Icons.person_add_alt, 'Accept players', <String>[
                            'A request pops up when someone scans your Join Game '
                                'QR or types the ID.',
                            'Accept moves their stake out of the bank and seats '
                                'them at the table.',
                          ]),
                          section(Icons.tune, 'The row of icons', <String>[
                            'QR: the Join Game code to show the table.',
                            'History: every payment in the game.',
                            'Board: who owns which card (cards games only).',
                            'Pause / end: suspends the game for everyone, or '
                                'finishes it for good.',
                            'Receive / Give Card: take a payment, or sell a '
                                'board card.',
                          ]),
                          section(Icons.person_remove_alt_1,
                              'Removing a player', <String>[
                            'Tap the red person icon at the end of their row.',
                            'Their cash, their cards and any houses or hotels go '
                                'back to the bank.',
                            'The row keeps a REMOVED badge, and that player '
                                'cannot rejoin this game.',
                          ]),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            AppDialogButton(
              label: 'Got it',
              primary: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }
}
