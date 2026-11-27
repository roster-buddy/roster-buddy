import 'dart:typed_data';

import 'smart_scan_cloud_client.dart';
import 'smart_scan_local_engine.dart' as local;
import 'smart_scan_quality.dart';
import 'smart_scan_page_text_reconstructor.dart';
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

    final isDailyReport = cloudResult != null &&
        RegExp(r'\b(?:Daily\s+Roster\s+Report|Report\s+for\s+(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday))\b',
          caseSensitive: false,
        ).hasMatch(cloudResult.fullText);
    if (cloudResult != null &&
        (!local.SmartScanEngine.isSupported ||
            (!SmartScanQuality.needsLocalRescue(cloudResult.fullText) &&
                !(isDailyReport &&
                    SmartScanQuality.needsLocalRescue(
                      SmartScanPageTextReconstructor.reconstruct(cloudResult),
                    ))))) {
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
        detailedDailyReport: isDailyReport,
      );
      if (cloudResult == null) return localResult;
      // The daily parser validates the secure service's natural reading
      // against the locally reconstructed table and only keeps complementary
      // payroll rows. It never joins a time from one driver to another.
      return SmartScanResult(
        fullText: cloudResult.fullText,
        alternateText: localResult.alternateText.isEmpty
            ? localResult.fullText
            : localResult.alternateText,
        additionalReadings: isDailyReport
            ? [
                localResult.fullText,
                SmartScanPageTextReconstructor.reconstruct(localResult),
              ]
            : const [],
        lines: isDailyReport && cloudResult.lines.isNotEmpty || localResult.lines.isEmpty
            ? cloudResult.lines
            : localResult.lines,
        confidence: isDailyReport
            ? cloudResult.confidence
            : localResult.confidence ?? cloudResult.confidence,
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

  /// Re-reads a Base Roster locally in both page orientations.
  ///
  /// Office copiers commonly save otherwise clear roster sheets upside down.
  /// The quick secure OCR can still return a few isolated numbers from those
  /// pages, which previously looked like a successful scan and prevented the
  /// local reader from correcting the orientation.
  static Future<List<SmartScanResult>> recogniseBaseRosterPdf({
    required Uint8List bytes,
    required String fileName,
    void Function(String, double?)? onProgress,
  }) async {
    if (!local.SmartScanEngine.isSupported) {
      throw const SmartScanException(
        'Base Roster orientation correction is unavailable on this device.',
      );
    }

    try {
      return await local.SmartScanEngine.recognisePdf(
        bytes: bytes,
        fileName: fileName,
        onProgress: onProgress,
        retryUpsideDown: true,
      );
    } on local.SmartScanException catch (error) {
      throw SmartScanException(error.message);
    }
  }
}
