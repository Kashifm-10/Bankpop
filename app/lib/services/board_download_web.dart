import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The browser: hand the bytes to a hidden link and click it, which saves the
/// file to wherever the browser puts downloads - no share sheet, no tab.
Future<String?> saveImage(Uint8List bytes, String fileName) async {
  _save(bytes.toJS, 'image/png', fileName);
  return null;
}

Future<String?> saveJson(Uint8List bytes, String fileName) async {
  _save(bytes.toJS, 'application/json', fileName);
  return null;
}

void _save(JSAny data, String type, String fileName) {
  final web.Blob blob = web.Blob(
    <JSAny>[data].toJS,
    web.BlobPropertyBag(type: type),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement link =
      web.document.createElement('a') as web.HTMLAnchorElement;
  link.href = url;
  link.download = fileName;
  link.style.display = 'none';
  web.document.body?.append(link);
  link.click();
  link.remove();
  web.URL.revokeObjectURL(url);
}
