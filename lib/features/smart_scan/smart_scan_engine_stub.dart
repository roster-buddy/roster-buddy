import 'dart:typed_data';

import 'smart_scan_result.dart';

class SmartScanException implements Exception {
  const SmartScanException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SmartScanEngine {
  SmartScanEngine._();

  static bool get isSupported => false;

  static Future<SmartScanResult> recogniseImage({
    required Uint8List bytes,
    required String fileName,
  }) {
    throw const SmartScanException(
      'OCR is currently supported only on iPhone and Android.',
    );
  }

  static Future<List<SmartScanResult>> recognisePdf({
    required Uint8List bytes,
    required String fileName,
  }) {
    throw const SmartScanException(
      'PDF OCR is currently supported only on iPhone and Android.',
    );
  }
}
