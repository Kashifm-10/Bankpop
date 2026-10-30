import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';

/// What a message is for: the mark and colour its notification carries.
enum MessageKind {
  /// Something to know - "the card has already gone", "no players yet".
  info,

  /// Something that worked - money sent, a card sold, a player seated.
  success,

  /// Something that worked, but not as asked - "the bank is short", a pack
  /// already shuffled.
  warning,

  /// Something that did not work, and the caller has nothing to add.
  failure,
}

/// One notification, drawn by `awesome_snackbar_content`.
///
/// These used to be dialogs: an info box that had to be dismissed, even for
/// "payment sent". A notification is now a snackbar - the table keeps its
/// place, nothing covers the board, and every one of them is the same card,
/// whatever screen raised it. This is the app's only notification path, so the
/// 100-odd messages in the screens all read alike.
///
/// Anything that *asks* something or needs a decision is still a dialog: a
/// snackbar can be missed, and a question cannot be (see `showAppConfirm`).
Future<void> showMessage(
  BuildContext context,
  String message, {
  String title = 'Bankpop',
  MessageKind kind = MessageKind.info,
}) async {
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final ContentType type = switch (kind) {
    MessageKind.success => ContentType.success,
    MessageKind.warning => ContentType.warning,
    MessageKind.failure => ContentType.failure,
    MessageKind.info => ContentType.help,
  };

  // Long messages are read at the table, not skimmed: the card stays a little
  // longer for them, and never so long that it is in the way.
  final Duration stay = Duration(
    milliseconds:
        (3200 + message.length * 35).clamp(3200, 7000).toInt(),
  );

  messenger
    // One at a time: a second message replaces the first rather than queueing
    // behind it, so what is on the screen is always what just happened.
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        duration: stay,
        padding: EdgeInsets.zero,
        content: AwesomeSnackbarContent(
          title: title,
          message: message,
          contentType: type,
        ),
      ),
    );
}
