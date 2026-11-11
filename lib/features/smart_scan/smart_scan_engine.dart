import 'dart:typed_data';

import 'smart_scan_cloud_client.dart';
import 'smart_scan_local_engine.dart' as local;
import 'smart_scan_quality.dart';
import 'smart_scan_result.dart';

class SmartScanException implements Exception {
  const SmartScanException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SmartScanEngine {
  SmartScanEngine._();

  static bool get isSupported => true;

  static void cancel() => local.SmartScanEngine.cancel();

  static Future<SmartScanResult> recogniseImage({
    required Uint8List bytes,
    required String fileName,
    void Function(String, double?)? onProgress,
  }) async {
    SmartScanCloudException? cloudError;
    SmartScanResult? cloudResult;

    try {
      cloudResult = await SmartScanCloudClient.recogniseImage(
        bytes: bytes,
        fileName: fileName,
        onProgress: onProgress,
      );
    } on SmartScanCloudException catch (error) {
      cloudError = error;
    }

    if (cloudResult != null &&
        (!SmartScanQuality.needsLocalRescue(cloudResult.fullText) ||
            !local.SmartScanEngine.isSupported)) {
      return cloudResult;
    }

    if (cloudResult != null) {
      onProgress?.call('Re-reading unclear roster rows…', 0.8);
    } else if (!local.SmartScanEngine.isSupported) {
      throw SmartScanException(cloudError!.message);
    }

    try {
      final localResult = await local.SmartScanEngine.recogniseImage(
        bytes: bytes,
        fileName: fileName,
        onProgress: onProgress,
      );
      if (cloudResult == null) return localResult;
      // The daily parser validates the secure service's natural reading
      // against the locally reconstructed table and only keeps complementary
      // payroll rows. It never joins a time from one driver to another.
      return SmartScanResult(
        fullText: cloudResult.fullText,
        lines: localResult.lines.isEmpty ? cloudResult.lines : localResult.lines,
        confidence: localResult.confidence ?? cloudResult.confidence,
      );
    } on local.SmartScanException catch (error) {
      if (cloudResult != null) return cloudResult;
      throw SmartScanException(error.message);
    }
  }

  static Future<List<SmartScanResult>> recognisePdf({
    required Uint8List bytes,
    required String fileName,
    void Function(String, double?)? onProgress,
  }) async {
    late SmartScanCloudException cloudError;

    try {
      return await SmartScanCloudClient.recognisePdf(
        bytes: bytes,
        fileName: fileName,
        onProgress: onProgress,
      );
    } on SmartScanCloudException catch (error) {
      cloudError = error;
    }

    if (!local.SmartScanEngine.isSupported) {
      throw SmartScanException(cloudError.message);
    }

    try {
      return await local.SmartScanEngine.recognisePdf(
        bytes: bytes,
        fileName: fileName,
        onProgress: onProgress,
      );
    } on local.SmartScanException catch (error) {
      throw SmartScanException(error.message);
    }
  }
}
