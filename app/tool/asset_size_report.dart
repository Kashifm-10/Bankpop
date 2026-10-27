// Dev-only: reports the width, height and decoded memory cost of every bundled
// image, so an oversized source can be caught before it ships.
//
//   dart run tool/asset_size_report.dart
//
// A JPEG/PNG holds its pixels compressed; the decoder expands them to
// width x height x 4 bytes in memory. A 1200x1200 avatar drawn at 50 px costs
// 5.5 MB of bitmap either way - which is why every Image.asset/CircleAvatar in
// this app either sets cacheWidth or wraps the provider in ResizeImage.
//
// Reads the header bytes only; no image library needed.

import 'dart:io';

const int _maxBytes = 64 * 1024; // headers live in the first few KB

int _u16(List<int> b, int i) => (b[i] << 8) | b[i + 1];

int _u32(List<int> b, int i) =>
    (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

/// Width and height from a JPEG's SOF marker, or null if there is none.
(int, int)? _jpegSize(List<int> d) {
  int i = 2;
  while (i < d.length - 9) {
    if (d[i] != 0xFF) {
      i++;
      continue;
    }
    final int marker = d[i + 1];
    // SOF0-SOF15, excluding DHT (0xC4), JPG (0xC8) and DAC (0xCC).
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      return (_u16(d, i + 7), _u16(d, i + 5)); // height then width on the wire
    }
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    i += 2 + _u16(d, i + 2);
  }
  return null;
}

/// Width and height from a PNG's IHDR chunk, or null if this is not a PNG.
(int, int)? _pngSize(List<int> d) {
  const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  for (int i = 0; i < signature.length; i++) {
    if (d.length <= i || d[i] != signature[i]) return null;
  }
  if (d.length < 24) return null;
  return (_u32(d, 16), _u32(d, 20));
}

void main() {
  final List<FileSystemEntity> entries =
      Directory('assets').listSync(recursive: true);
  double totalMb = 0;
  final List<String> lines = <String>[];

  for (final FileSystemEntity entity in entries) {
    if (entity is! File) continue;
    final String path = entity.path.replaceAll(r'\', '/');
    final String ext = path.split('.').last.toLowerCase();
    if (!<String>{'jpg', 'jpeg', 'png'}.contains(ext)) continue;

    final File file = File(path);
    final int size = file.lengthSync();
    final List<int> head = file
        .openSync()
        .let((RandomAccessFile f) => f.readSync(size < _maxBytes ? size : _maxBytes));

    final (int, int)? dims = ext == 'png' ? _pngSize(head) : _jpegSize(head);
    if (dims == null) {
      lines.add('${path.padRight(46)}   (header not readable)');
      continue;
    }
    final (int width, int height) = dims;
    final double mb = width * height * 4 / (1024 * 1024);
    totalMb += mb;
    lines.add('${path.padRight(46)}${'${width}x$height'.padLeft(11)}'
        '${'${(size / 1024).toStringAsFixed(1)} KB'.padLeft(11)}'
        '   decoded ${'${mb.toStringAsFixed(1)} MB'.padLeft(8)}');
  }

  lines.sort((String a, String b) {
    double mbOf(String line) =>
        double.tryParse(line.split('decoded').last.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    return mbOf(b).compareTo(mbOf(a));
  });
  for (final String line in lines) {
    stdout.writeln(line);
  }
  stdout.writeln('total decoded if every image were held at once: '
      '${totalMb.toStringAsFixed(1)} MB');
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
