import 'dart:convert';
import 'dart:typed_data';

import 'board_download_stub.dart'
    if (dart.library.io) 'board_download_io.dart'
    if (dart.library.js_interop) 'board_download_web.dart' as impl;

/// Saving a board to the device: the printable picture, and - for a player's
/// own board - the JSON a friend can import.
///
/// This is a plain download, not a share sheet. A share sheet asks the player
/// to pick somewhere to put a file they only asked to keep, and on the web it
/// has no file support at all; the downloads folder is where a "Download"
/// button is expected to land.
class BoardDownload {
  const BoardDownload._();

  /// Saves PNG [bytes] as [fileName]. Returns the path it was written to, or
  /// null when the browser saved it itself (there is no path to report).
  static Future<String?> image(Uint8List bytes, String fileName) =>
      impl.saveImage(bytes, fileName);

  /// Saves [json] as a `.json` file, the same way.
  static Future<String?> json(String json, String fileName) =>
      impl.saveJson(Uint8List.fromList(utf8.encode(json)), fileName);
}
