import 'package:flutter/material.dart';
import 'package:mon/services/player_exit.dart';

/// The small chip beside a player's name that says they are no longer at the
/// table: `REMOVED` after the banker took their seat.
///
/// There are only two standings - seated and removed - so there is nothing else
/// to draw: no heartbeat means the app never claims to know who is watching, and
/// a player who closed the app still owns their row.
class PlayerStandingBadge extends StatelessWidget {
  const PlayerStandingBadge({
    super.key,
    required this.standing,
    this.compact = false,
  });

  final PlayerStanding standing;

  /// Smaller text, for the tight banker row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (standing != PlayerStanding.kicked) return const SizedBox.shrink();

    const Color colour = Color(0xFFC62828);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colour.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.person_remove_alt_1,
              size: compact ? 10 : 12, color: colour),
          const SizedBox(width: 4),
          Text(
            'REMOVED',
            style: TextStyle(
              fontSize: compact ? 8.5 : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}
