import 'package:flutter/material.dart';

/// One message box, used everywhere a bottom snackbar used to be.
///
/// Snackbars sat over the bottom sheet and the board and vanished after two
/// seconds, so half the messages in this app were missed. A message here waits
/// for OK, which matters for the things this screen used to say: an unmet build
/// rule, a payment that failed, a card that has already gone.
Future<void> showMessage(
  BuildContext context,
  String message, {
  String title = 'Bankpop',
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFFFFF8E1),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF689F38),
        ),
      ),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
