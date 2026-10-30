import 'dart:typed_data';

/// The fallback for a platform with neither a browser nor a native reader.
///
/// Every target this app ships on has a real reader now - ML Kit on the phone,
/// the platform's own engine on the desktop and Tesseract.js in the browser - so
/// this file is only what a new, unhandled platform compiles against.
const bool ocrSupported = false;

Future<List<List<String>>> readBoardBlocks(
  String path, {
  Uint8List? bytes,
}) async {
  throw UnsupportedError('Reading a board photograph is not available here.');
}
