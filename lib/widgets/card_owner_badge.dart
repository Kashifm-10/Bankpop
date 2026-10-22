import 'package:flutter/material.dart';
import 'package:mon/services/player_cards.dart';

/// The owner's face and name, sized to sit in a deed's footer where the sell
/// action would otherwise be.
///
/// A sold card's deed looks exactly like an unsold one; this is the only thing
/// that differs, so the card, its rent and its price stay where the player
/// expects them.
class CardOwnerBadge extends StatelessWidget {
  const CardOwnerBadge({super.key, required this.owner});

  final CardOwner owner;

  static const String _fallbackAvatar = 'assets/avatars/boy1.jpg';

  @override
  Widget build(BuildContext context) {
    final String? raw = owner.avatar;
    final String path = (raw == null || raw.isEmpty) ? _fallbackAvatar : raw;
    final String initial =
        owner.name.trim().isEmpty ? '?' : owner.name.trim()[0].toUpperCase();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF689F38),
          ),
          child: ClipOval(
            child: Image.asset(
              path,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              // The source avatars are 500-1200px; decoding at 56 keeps this
              // footer badge cheap.
              cacheWidth: 56,
              errorBuilder: (BuildContext context, Object error,
                      StackTrace? stackTrace) =>
                  Container(
                width: 28,
                height: 28,
                color: const Color(0xFF689F38),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                owner.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF33691E),
                ),
              ),
              const Text(
                'owns this card',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
