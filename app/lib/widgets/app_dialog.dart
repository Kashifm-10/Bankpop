import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The one dialog look.
///
/// Every confirm/cancel and every "that did not work" in the app goes through
/// this file, so they share a cream card, a round corner, a green title with an
/// icon, and the same button order (cancel on the left, the action on the
/// right). The screens used to each build their own `AlertDialog` with a
/// slightly different colour - grey, pale yellow, cream - which is exactly the
/// inconsistency this removes.
///
/// The palette follows the app's greens, and dark mode gets a dark card with
/// the same accents so a dialog is never a white flash in a dark room.
class AppDialogPalette {
  const AppDialogPalette._({
    required this.surface,
    required this.title,
    required this.body,
    required this.accent,
    required this.actions,
  });

  final Color surface;
  final Color title;
  final Color body;
  final Color accent;
  final Color actions;

  /// The light-mode greens the rest of the app is drawn in.
  static const AppDialogPalette light = AppDialogPalette._(
    surface: Color(0xFFFFF8E1),
    title: Color(0xFF33691E),
    body: Color(0xFF33691E),
    accent: Color(0xFF689F38),
    actions: Color(0xFF2E7D32),
  );

  static const AppDialogPalette dark = AppDialogPalette._(
    surface: Color(0xFF26291F),
    title: Color(0xFFC5E1A5),
    body: Color(0xFFE0E0E0),
    accent: Color(0xFF9CCC65),
    actions: Color(0xFF9CCC65),
  );

  static AppDialogPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Shows a dialog in the app's style.
///
/// [content] and [message] are alternatives: a plain sentence for a notice, or
/// a widget when the dialog needs a summary, a switch or a list.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String title,
  IconData icon = Icons.info_outline,
  /// An illustrated icon (`assets/Icons/`) drawn in place of [icon].
  ///
  /// A dialog that is about the same thing as a game button should wear the
  /// same picture, so "Leave game?" shows the leave button's own artwork
  /// rather than a look-alike glyph.
  String? art,
  String? message,
  Widget? content,
  List<Widget> actions = const <Widget>[],
  bool barrierDismissible = true,
  Color? accent,
  bool allowBack = true,
}) {
  final AppDialogPalette palette = AppDialogPalette.of(context);
  final Color tint = accent ?? palette.accent;

  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext dialogContext) {
      final double width = MediaQuery.sizeOf(dialogContext).width;
      return PopScope(
        canPop: allowBack,
        child: AlertDialog(
          backgroundColor: palette.surface,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Same 36 px footprint either way, so the title sits at the
              // same place whether the badge is a glyph or a drawing.
              if (art != null)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(art, fit: BoxFit.contain),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: tint),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.title,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // A long summary scrolls instead of overflowing on a short screen.
          // On a wide window the card keeps a readable width instead of
          // stretching a sentence across the whole screen.
          content: SizedBox(
            width: math.min(width, 420),
            child: SingleChildScrollView(
              child: content ??
                  Text(
                    message ?? '',
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      color: palette.body,
                    ),
                  ),
            ),
          ),
          actions: actions,
        ),
      );
    },
  );
}

/// One yes/no dialog. Returns true only when the action was confirmed.
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continue',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline,
  String? art,
  Widget? extra,
  bool destructive = false,
}) async {
  final AppDialogPalette palette = AppDialogPalette.of(context);
  final bool? answer = await showAppDialog<bool>(
    context,
    title: title,
    icon: icon,
    art: art,
    accent: destructive ? const Color(0xFFC62828) : null,
    barrierDismissible: false,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (extra != null) ...<Widget>[extra, const SizedBox(height: 14)],
        Text(
          message,
          style: TextStyle(fontSize: 14.5, height: 1.4, color: palette.body),
        ),
      ],
    ),
    actions: <Widget>[
      AppDialogButton(
        label: cancelLabel,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      AppDialogButton(
        label: confirmLabel,
        primary: true,
        destructive: destructive,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  return answer ?? false;
}

/// The two buttons every dialog is built from.
class AppDialogButton extends StatelessWidget {
  const AppDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final AppDialogPalette palette = AppDialogPalette.of(context);
    final Color colour = destructive
        ? const Color(0xFFC62828)
        : (primary ? palette.actions : palette.title);

    if (!primary) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: colour,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: destructive ? colour : palette.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

/// One line of a dialog: a coloured dot and a short sentence. Used by the
/// summaries (start a game, remove a player) so their rows line up.
class AppDialogPoint extends StatelessWidget {
  const AppDialogPoint({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppDialogPalette palette = AppDialogPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon ?? Icons.circle,
              size: icon == null ? 6 : 16, color: palette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: palette.body, height: 1.3),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: palette.title,
            ),
          ),
        ],
      ),
    );
  }
}
