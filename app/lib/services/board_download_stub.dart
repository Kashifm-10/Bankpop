import 'dart:typed_data';

/// The platforms without files or a browser: there is nowhere to put a
/// download, so the button reports that instead of pretending it worked.
Future<String?> saveImage(Uint8List bytes, String fileName) async =>
    throw UnsupportedError('saving files');

Future<String?> saveJson(Uint8List bytes, String fileName) async =>
    throw UnsupportedError('saving files');
