/// The web build has no sockets, so nothing here can send SMTP mail. The
/// caller must take the edge-function path instead; this exists so the shared
/// code compiles for web.
class DirectMailer {
  const DirectMailer._();

  static Future<void> send({
    required String host,
    required int port,
    required String username,
    required String password,
    required String senderName,
    required String to,
    required String subject,
    required String text,
    required String html,
  }) async {
    throw UnsupportedError('SMTP sockets are not available in a browser');
  }
}
