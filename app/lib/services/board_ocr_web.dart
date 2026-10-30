import 'dart:typed_data';

import 'package:ocr_flutter_web/ocr_flutter_web.dart';

/// The browser reader.
///
/// ML Kit and the desktop readers are native, so the browser build gets its own:
/// Tesseract.js, compiled to WebAssembly, fetched from a CDN the first time a
/// board is read. It runs in the tab, so the picture still never leaves the
/// device - the download is the engine, not the board.
///
/// Tesseract.js hands back its text with the blocks it read kept apart: a block's
/// lines are separated by a newline, and one block from the next by a blank line.
/// Splitting on that blank line is what keeps a name printed over two lines in
/// one square - the same block the phone's reader reports, recovered from the
/// text instead of guessed at from the words.
const bool ocrSupported = true;

Future<List<List<String>>> readBoardBlocks(
  String path, {
  Uint8List? bytes,
}) async {
  if (bytes == null || bytes.isEmpty) {
    // There is no file to open in the browser: the picker hands back bytes, and
    // its object URLs are not paths the engine can read.
    throw UnsupportedError('The picture has to be handed over as bytes.');
  }
  final String text = await OcrFlutterWeb().extractText(
    bytes,
    filename: 'board.jpg',
    // English only: asking for Hindi too would download a second model for a
    // board this app prints in English.
    language: 'eng',
  );
  final List<List<String>> blocks = <List<String>>[];
  List<String> block = <String>[];
  for (final String line in text.split('\n')) {
    if (line.trim().isEmpty) {
      if (block.isNotEmpty) {
        blocks.add(block);
        block = <String>[];
      }
      continue;
    }
    block.add(line.trim());
  }
  if (block.isNotEmpty) blocks.add(block);
  return blocks;
}
