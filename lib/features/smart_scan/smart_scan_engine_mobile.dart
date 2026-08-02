import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import 'smart_scan_result.dart';

class SmartScanException implements Exception {
  const SmartScanException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SmartScanEngine {
  SmartScanEngine._();

  static const int maximumPdfPages = 60;
  static const double maximumRenderedWidth = 2400;

  static bool get isSupported => Platform.isIOS || Platform.isAndroid;

  static Future<SmartScanResult> recogniseImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _ensureSupported();

    if (bytes.isEmpty) {
      throw const SmartScanException('The selected image is empty.');
    }

    final Directory temporaryDirectory = await getTemporaryDirectory();
    final String extension = _extensionFor(fileName);

    final File temporaryFile = File(
      '${temporaryDirectory.path}/'
      'roster_buddy_${DateTime.now().microsecondsSinceEpoch}$extension',
    );

    final TextRecognizer recognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );

    try {
      await temporaryFile.writeAsBytes(bytes, flush: true);

      return await _recogniseFile(file: temporaryFile, recognizer: recognizer);
    } on SmartScanException {
      rethrow;
    } catch (_) {
      throw const SmartScanException(
        'Roster Buddy could not read text from this image.',
      );
    } finally {
      await recognizer.close();
      await _deleteIfPresent(temporaryFile);
    }
  }

  static Future<List<SmartScanResult>> recognisePdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _ensureSupported();

    if (bytes.isEmpty) {
      throw const SmartScanException('The selected PDF is empty.');
    }

    PdfDocument? document;
    final TextRecognizer recognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );

    final Directory temporaryDirectory = await getTemporaryDirectory();
    final List<File> renderedFiles = <File>[];

    try {
      document = await PdfDocument.openData(bytes);

      if (document.pagesCount < 1) {
        throw const SmartScanException(
          'The selected PDF does not contain any pages.',
        );
      }

      if (document.pagesCount > maximumPdfPages) {
        throw SmartScanException(
          'This PDF has ${document.pagesCount} pages. '
          'Roster Buddy currently supports up to $maximumPdfPages pages '
          'in one document.',
        );
      }

      final List<SmartScanResult> results = <SmartScanResult>[];

      for (
        int pageNumber = 1;
        pageNumber <= document.pagesCount;
        pageNumber++
      ) {
        PdfPage? page;

        try {
          page = await document.getPage(pageNumber);

          final double renderScale = math.min(
            maximumRenderedWidth / page.width,
            3,
          );

          final double renderedWidth = math.max(
            page.width,
            page.width * renderScale,
          );

          final double renderedHeight = math.max(
            page.height,
            page.height * renderScale,
          );

          final PdfPageImage? renderedImage = await page.render(
            width: renderedWidth,
            height: renderedHeight,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
            quality: 100,
            forPrint: true,
          );

          if (renderedImage == null || renderedImage.bytes.isEmpty) {
            throw SmartScanException(
              'Roster Buddy could not render PDF page $pageNumber.',
            );
          }

          final File renderedFile = File(
            '${temporaryDirectory.path}/'
            'roster_buddy_pdf_'
            '${DateTime.now().microsecondsSinceEpoch}_'
            '$pageNumber.png',
          );

          renderedFiles.add(renderedFile);

          await renderedFile.writeAsBytes(renderedImage.bytes, flush: true);

          results.add(
            await _recogniseFile(file: renderedFile, recognizer: recognizer),
          );
        } on SmartScanException {
          rethrow;
        } catch (_) {
          throw SmartScanException(
            'Roster Buddy could not read PDF page $pageNumber.',
          );
        } finally {
          if (page != null && !page.isClosed) {
            await page.close();
          }
        }
      }

      if (!results.any((SmartScanResult result) => result.hasText)) {
        throw const SmartScanException(
          'No readable text was detected in this PDF.',
        );
      }

      return results;
    } on SmartScanException {
      rethrow;
    } catch (_) {
      throw const SmartScanException(
        'Roster Buddy could not open or read this PDF.',
      );
    } finally {
      await recognizer.close();

      for (final File file in renderedFiles) {
        await _deleteIfPresent(file);
      }

      if (document != null && !document.isClosed) {
        await document.close();
      }
    }
  }

  static Future<SmartScanResult> _recogniseFile({
    required File file,
    required TextRecognizer recognizer,
  }) async {
    final InputImage inputImage = InputImage.fromFilePath(file.path);

    final RecognizedText recognisedText = await recognizer.processImage(
      inputImage,
    );

    final List<SmartScanTextLine> lines = <SmartScanTextLine>[];

    for (final TextBlock block in recognisedText.blocks) {
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

    return SmartScanResult(fullText: recognisedText.text, lines: lines);
  }

  static void _ensureSupported() {
    if (!isSupported) {
      throw const SmartScanException(
        'OCR is currently supported only on iPhone and Android.',
      );
    }
  }

  static Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Temporary-file cleanup must not hide the OCR result.
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

    if (lowerName.endsWith('.heic')) {
      return '.heic';
    }

    if (lowerName.endsWith('.heif')) {
      return '.heif';
    }

    return '.jpg';
  }
}
