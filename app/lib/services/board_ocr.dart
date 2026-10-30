import 'dart:typed_data';

import 'board_ocr_stub.dart'
    if (dart.library.js_interop) 'board_ocr_web.dart'
    if (dart.library.io) 'board_ocr_io.dart' as engine;

/// Reading the words off a picture of a board.
///
/// Every reader here runs on the device that opened the picture - the board is
/// never uploaded, so there is no key, no account and no connection involved.
/// No single package covers all the platforms this app ships on, so there is one
/// reader per family:
///
/// * Android and iOS - Google ML Kit's text recogniser, bundled with the app.
/// * Windows, macOS and Linux - [flutter_ocr_native], which is Windows.Media.Ocr
///   on Windows, Apple's Vision on macOS and Tesseract on Linux.
/// * the browser - Tesseract.js, compiled to WebAssembly and fetched once on
///   first use.
///
/// The choice is made at compile time by the conditional import above, so a
/// platform never carries the code of another one's reader, and [isSupported]
/// answers for the platform it was built for.
abstract final class BoardOcr {
  /// Whether this build can read a picture at all.
  static bool get isSupported => engine.ocrSupported;

  /// The lines in the picture at [path] (or in [bytes], when the platform's
  /// picker hands back bytes rather than a file), top to bottom.
  ///
  /// The browser has no file to open, so it takes [bytes]; every other platform
  /// prefers the file at [path] and falls back to [bytes].
  static Future<List<String>> readLines(String path, {Uint8List? bytes}) =>
      engine.readBoardLines(path, bytes: bytes);
}
