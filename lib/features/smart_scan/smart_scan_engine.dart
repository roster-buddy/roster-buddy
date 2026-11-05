import 'dart:typed_data';

import 'smart_scan_cloud_client.dart';
import 'smart_scan_local_engine.dart' as local;
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
    late SmartScanCloudException cloudError;

    try {
      return await SmartScanCloudClient.recogniseImage(
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
      return await local.SmartScanEngine.recogniseImage(
        bytes: bytes,
        fileName: fileName,
        onProgress: onProgress,
      );
    } on local.SmartScanException catch (error) {
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
