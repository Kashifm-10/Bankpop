import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mon/services/game_session.dart';
import 'package:mon/widgets/app_dialog.dart';

/// The band across the top of a game screen while the table is not being played.
///
/// A suspension is amber and carries the banker's name, because the banker is
/// the only one who can lift it; an ended game is red and says that nothing can
/// move any more. The player's screen and the banker's screen draw the same
/// band, so the two never describe the same pause differently.
///
/// The band is not the gate - the screens hide every action themselves - it is
/// what explains why those actions are gone.
class GameStatusBanner extends StatelessWidget {
  const GameStatusBanner({
    super.key,
    required this.session,
    this.bankerView = false,
    this.onDetails,
    this.onResume,
  });

  final GameSession session;

  /// The banker's own screen says "until you resume" and offers the control;
  /// a player's screen names the banker instead.
  final bool bankerView;

  final VoidCallback? onDetails;
  final VoidCallback? onResume;

  /// "This game was ended on 23 Oct 2026, 2:15 PM", or the bare fact when the
  /// session row predates the end date.
  String _endedPhrase() {
    final DateTime? endedAt = session.endedAt;
    if (endedAt == null) return 'This game has ended';
    return 'This game was ended on '
        '${DateFormat('d MMM yyyy, h:mm a').format(endedAt.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final bool ended = session.isEnded;
    final Color accent =
        ended ? const Color(0xFFC62828) : const Color(0xFF8D6E63);
    final Color surface =
        ended ? const Color(0xFFFFCDD2) : const Color(0xFFFFE082);

    final String text = ended
        ? (bankerView
            ? '${_endedPhrase()} - players can look at their holdings, nothing '
                'can move.'
            : '${_endedPhrase()} - you can look at your holdings, but nothing '
                'can be paid, traded, built or advanced.')
        : (bankerView
            ? 'Game paused - the table is view only until you resume.'
            : 'Paused by ${session.bankerName}. Only the banker can resume it, '
                'so the table is view only until then.');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            ended ? Icons.flag : Icons.pause_circle_filled,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5)),
          ),
          if (bankerView && !ended && onResume != null)
            TextButton(onPressed: onResume, child: const Text('Resume'))
          else if (onDetails != null)
            TextButton(onPressed: onDetails, child: const Text('Details')),
        ],
      ),
    );
  }
}

/// The pause or end of the game, told once to a player who is at the table.
///
/// Not dismissible by tapping outside or by the back gesture: the only ways out
/// are staying to look at the board or going back to the title screen, which is
/// exactly the pair of choices the rules leave a player when the banker stops
/// the table. Returns once the player has chosen.
Future<void> showGameStatusDialog(
  BuildContext context, {
  required GameSession session,
  required VoidCallback onReturnToTitle,
}) async {
  final bool ended = session.isEnded;
  final String banker = session.bankerName;
  final DateTime? endedAt = session.endedAt;
  final String endedWhen = endedAt == null
      ? 'The banker ($banker) ended this game.'
      : 'The banker ($banker) ended this game on '
          '${DateFormat('d MMM yyyy, h:mm a').format(endedAt.toLocal())}.';

  await showAppDialog<void>(
    context,
    title: ended ? 'Game ended' : 'Game paused',
    icon: ended ? Icons.flag : Icons.pause_circle_filled,
    accent: ended ? const Color(0xFFC62828) : const Color(0xFFEF6C00),
    barrierDismissible: false,
    allowBack: false,
    message: ended
        ? '$endedWhen Your balance and your cards stay on the board to look '
            'at, but no more rent, trades, card purchases, buildings or '
            'advances can happen in it.'
        : 'The banker ($banker) paused this game. Only they can resume it, and '
            'play continues exactly where it stopped, so nothing can be paid, '
            'traded, built or advanced until then.',
    actions: <Widget>[
      AppDialogButton(
        label: ended ? 'View holdings' : 'Stay',
        onPressed: () => Navigator.of(context).pop(),
      ),
      AppDialogButton(
        label: 'Return to title screen',
        primary: true,
        onPressed: () {
          Navigator.of(context).pop();
          onReturnToTitle();
        },
      ),
    ],
  );
}
