import 'package:flutter/material.dart';
import 'package:mon/widgets/app_dialog.dart';

/// One message box, used everywhere a bottom snackbar used to be.
///
/// Snackbars sat over the bottom sheet and the board and vanished after two
/// seconds, so half the messages in this app were missed. A message here waits
/// for OK, which matters for the things this screen used to say: an unmet build
/// rule, a payment that failed, a card that has already gone.
///
/// Drawn by [showAppDialog], so it is the same card, title and button as every
/// other dialog in the app.
Future<void> showMessage(
  BuildContext context,
  String message, {
  String title = 'Bankpop',
}) {
  return showAppDialog<void>(
    context,
    title: title,
    icon: Icons.info_outline,
    message: message,
    actions: <Widget>[
      AppDialogButton(
        label: 'OK',
        primary: true,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}
