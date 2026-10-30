import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Desktop and mobile: write the file to the downloads folder.
///
/// Desktop platforms have one (`getDownloadsDirectory`); Android and iOS do
/// not expose it to an app without storage permissions, so the app's own
/// documents folder is used there and the path is reported back - which is the
/// one place a player can then find it from their file manager.
Future<Directory> _target() async {
  try {
    final Directory? downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  } catch (_) {
    // Not available on this platform; fall through to documents.
  }
  return getApplicationDocumentsDirectory();
}

Future<String?> _write(Uint8List bytes, String fileName) async {
  final Directory directory = await _target();
  final File file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<String?> saveImage(Uint8List bytes, String fileName) =>
    _write(bytes, fileName);

Future<String?> saveJson(Uint8List bytes, String fileName) =>
    _write(bytes, fileName);
