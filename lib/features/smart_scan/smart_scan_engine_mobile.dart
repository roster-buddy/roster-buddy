import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'smart_scan_result.dart';

class SmartScanException implements Exception {
  const SmartScanException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SmartScanEngine {
  SmartScanEngine._();

  static bool get isSupported => Platform.isIOS || Platform.isAndroid;

  static Future<SmartScanResult> recogniseImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!isSupported) {
      throw const SmartScanException(
        'OCR is currently supported only on iPhone and Android.',
      );
    }

    if (bytes.isEmpty) {
      throw const SmartScanException('The selected image is empty.');
    }

    final String extension = _extensionFor(fileName);
    final Directory temporaryDirectory = await getTemporaryDirectory();
    final File temporaryFile = File(
      '${temporaryDirectory.path}/'
      'roster_buddy_${DateTime.now().microsecondsSinceEpoch}$extension',
    );

    final TextRecognizer recognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );

    try {
      await temporaryFile.writeAsBytes(bytes, flush: true);

      final InputImage inputImage = InputImage.fromFilePath(temporaryFile.path);

      final RecognizedText recognizedText = await recognizer.processImage(
        inputImage,
      );

      final List<SmartScanTextLine> lines = [];

      for (final TextBlock block in recognizedText.blocks) {
        for (final TextLine line in block.lines) {
          final rect = line.boundingBox;

          lines.add(
            SmartScanTextLine(
              text: line.text,
              left: rect.left,
              top: rect.top,
              right: rect.right,
              bottom: rect.bottom,
            ),
          );
        }
      }

      return SmartScanResult(fullText: recognizedText.text, lines: lines);
    } on SmartScanException {
      rethrow;
    } catch (_) {
      throw const SmartScanException(
        'Roster Buddy could not read text from this image.',
      );
    } finally {
      await recognizer.close();

      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }

  static String _extensionFor(String fileName) {
    final String lowerName = fileName.toLowerCase();

    if (lowerName.endsWith('.png')) {
      return '.png';
    }

    if (lowerName.endsWith('.jpeg')) {
      return '.jpeg';
    }

    return '.jpg';
  }
}
