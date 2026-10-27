/// Sends mail straight from the app on platforms with sockets.
///
/// `package:mailer` needs `dart:io`, which the browser does not have. This
/// conditional import compiles the real sender for Android, iOS and desktop,
/// and a stub that reports "not supported here" for web - where
/// [EmailSender] posts to the `send-mail` edge function instead.
library;

export 'direct_mailer_stub.dart' if (dart.library.io) 'direct_mailer_io.dart';
