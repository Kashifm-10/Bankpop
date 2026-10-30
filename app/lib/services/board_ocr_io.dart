import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_ocr_native/flutter_ocr_native.dart'
    show OcrReader, OcrResult, TextBlock, TextLine;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

/// The phone and desktop reader.
///
/// Android and iOS get ML Kit, which is the model the phone already carries;
/// Windows, macOS and Linux get [flutter_ocr_native], which is Windows.Media.Ocr
/// on Windows, Vision on macOS and Tesseract on Linux (the Linux build needs
/// `libtesseract` installed). Both read on the device and neither uploads
/// anything.
bool get ocrSupported =>
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isWindows ||
    Platform.isMacOS ||
    Platform.isLinux;

Future<List<String>> readBoardLines(String path, {Uint8List? bytes}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return _readWithMlKit(path);
  }
  return _readWithNative(path, bytes);
}

/// ML Kit: one line per recognised line, in the order the picture reads.
///
/// The phone's picker always leaves a real file behind, so the path is enough;
/// only the browser has no path to hand over, and it has its own reader.
Future<List<String>> _readWithMlKit(String path) async {
  final mlkit.TextRecognizer recognizer =
      mlkit.TextRecognizer(script: mlkit.TextRecognitionScript.latin);
  try {
    final mlkit.InputImage image = mlkit.InputImage.fromFilePath(path);
    final mlkit.RecognizedText text = await recognizer.processImage(image);
    return <String>[
      for (final mlkit.TextBlock block in text.blocks)
        for (final mlkit.TextLine line in block.lines) line.text,
    ];
  } finally {
    // The recogniser holds a native model; closing it hands that back.
    await recognizer.close();
  }
}

/// Windows, macOS and Linux, through the platform's own reader.
///
/// A printed board is low contrast under a camera, so the package's own
/// fallback matters here: when the first pass comes back empty or unsure it
/// sharpens the picture and reads it again before answering.
Future<List<String>> _readWithNative(String path, Uint8List? bytes) async {
  final OcrReader reader = OcrReader();
  try {
    final OcrResult result = bytes != null && bytes.isNotEmpty
        ? await reader.readFromBytes(bytes)
        : await reader.readFromPath(path);
    return <String>[
      for (final TextBlock block in result.blocks)
        for (final TextLine line in block.lines) line.text,
    ];
  } finally {
    await reader.dispose();
  }
}
