import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'smart_scan_result.dart';
import '../../core/parser/document_classifier.dart';
import 'cloud_image_preparation.dart';

class SmartScanCloudException implements Exception {
  const SmartScanCloudException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SmartScanCloudClient {
  SmartScanCloudClient._();

  static const String _functionName = 'roster-ocr';
  static const int _maximumFreeFileBytes = 1000000;

  static Future<SmartScanResult> recogniseImage({
    required Uint8List bytes,
    required String fileName,
    void Function(String, double?)? onProgress,
  }) async {
    final List<SmartScanResult> pages = await _recognise(
      bytes: bytes,
      fileName: fileName,
      isPdf: false,
      onProgress: onProgress,
    );

    if (pages.length != 1) {
      throw const SmartScanCloudException(
        'The secure scanner returned an unexpected number of image pages.',
      );
    }

    final page = pages.single;
    const classifier = DocumentClassifier();
    if (classifier.amendmentStamps([page.fullText]).isNotEmpty ||
        !RegExp(r'DAILY\s+ROSTER|REPORT\s+FOR', caseSensitive: false)
            .hasMatch(page.fullText)) return page;
    onProgress?.call('Checking the sheet stamp…', 0.85);
    try {
      final crop = await prepareCloudStamp(bytes, fileName);
      if (crop == null) return page;
      final stampPages = await _recognise(
        bytes: crop, fileName: 'sheet-stamp.jpg', isPdf: false,
      );
      return SmartScanResult(
        fullText: page.fullText, lines: page.lines, confidence: page.confidence,
        documentHeading: stampPages.map((p) => p.fullText).join('\n'),
      );
    } catch (_) {
      // A stamp failure must leave the readable table available for manual labelling.
      return page;
    }
  }

  static Future<List<SmartScanResult>> recognisePdf({
    required Uint8List bytes,
    required String fileName,
    void Function(String, double?)? onProgress,
  }) => _recognise(
    bytes: bytes,
    fileName: fileName,
    isPdf: true,
    onProgress: onProgress,
  );

  static Future<List<SmartScanResult>> _recognise({
    required Uint8List bytes,
    required String fileName,
    required bool isPdf,
    void Function(String, double?)? onProgress,
  }) async {
    if (bytes.isEmpty) {
      throw const SmartScanCloudException('The selected document is empty.');
    }

    if (!isPdf && (bytes.length > _maximumFreeFileBytes ||
        fileName.toLowerCase().endsWith('.heic') ||
        fileName.toLowerCase().endsWith('.heif'))) {
      onProgress?.call('Preparing photo for scanning…', 0.1);
      try {
        bytes = await prepareCloudImage(bytes, fileName);
        fileName = 'scan.jpg';
      } catch (_) {
        throw const SmartScanCloudException(
          'The photo could not be prepared for scanning. Choose a JPG or PNG photo and retry.',
        );
      }
    }

    if (bytes.length > _maximumFreeFileBytes) {
      throw SmartScanCloudException(
        'This photo is ${(bytes.length / 1000000).toStringAsFixed(1)} MB. The free scanner accepts up to 1 MB. Choose a smaller JPG photo.',
      );
    }

    if (Supabase.instance.client.auth.currentUser == null) {
      throw const SmartScanCloudException(
        'Sign in before using the secure scanner.',
      );
    }

    onProgress?.call('Sending document to the secure scanner…', 0.2);

    try {
      final FunctionResponse response = await Supabase.instance.client.functions
          .invoke(
            _functionName,
            body: <String, dynamic>{
              'fileName': fileName,
              'mimeType': _mimeType(fileName, isPdf),
              'base64Data': base64Encode(bytes),
            },
          );

      onProgress?.call('Reading the roster table…', 0.75);

      dynamic payload = response.data;
      if (payload is String) {
        payload = jsonDecode(payload);
      }

      if (payload is! Map) {
        throw const SmartScanCloudException(
          'The secure scanner returned an invalid response.',
        );
      }

      final Object? error = payload['error'];
      if (error is String && error.trim().isNotEmpty) {
        throw SmartScanCloudException(error.trim());
      }

      final Object? rawPages = payload['pages'];
      if (rawPages is! List || rawPages.isEmpty) {
        throw const SmartScanCloudException(
          'No readable text was found by the secure scanner.',
        );
      }

      final List<SmartScanResult> pages = rawPages.map((dynamic rawPage) {
        if (rawPage is! Map) {
          throw const SmartScanCloudException(
            'The secure scanner returned an invalid page.',
          );
        }

        final Object? rawLines = rawPage['lines'];
        final List<SmartScanTextLine> lines = rawLines is List
            ? rawLines.map((dynamic rawLine) {
                if (rawLine is! Map) {
                  throw const SmartScanCloudException(
                    'The secure scanner returned an invalid text position.',
                  );
                }

                return SmartScanTextLine(
                  text: (rawLine['text'] ?? '').toString(),
                  left: _number(rawLine['left']),
                  top: _number(rawLine['top']),
                  right: _number(rawLine['right']),
                  bottom: _number(rawLine['bottom']),
                );
              }).toList(growable: false)
            : const <SmartScanTextLine>[];

        final Object? rawConfidence = rawPage['confidence'];

        return SmartScanResult(
          fullText: (rawPage['fullText'] ?? '').toString(),
          lines: lines,
          confidence: rawConfidence is num
              ? rawConfidence.toDouble()
              : null,
        );
      }).toList(growable: false);

      if (!pages.any((SmartScanResult page) => page.hasText)) {
        throw const SmartScanCloudException(
          'No readable text was found by the secure scanner.',
        );
      }

      onProgress?.call('Secure scan complete', 1);
      return pages;
    } on SmartScanCloudException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? (details['error'] ?? details['message']) : null;
      throw SmartScanCloudException(
        message is String ? message : 'Secure scanner connection failed (HTTP ${error.status}). Please retry.',
      );
    } catch (_) {
      throw const SmartScanCloudException(
        'The secure scanner could not connect. Check your connection and retry.',
      );
    }
  }

  static double _number(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _mimeType(String fileName, bool isPdf) {
    if (isPdf) {
      return 'application/pdf';
    }

    final String lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerName.endsWith('.heic')) {
      return 'image/heic';
    }
    if (lowerName.endsWith('.heif')) {
      return 'image/heif';
    }
    return 'image/jpeg';
  }
}
