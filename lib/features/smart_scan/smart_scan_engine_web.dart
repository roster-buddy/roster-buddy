import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'smart_scan_result.dart';

@JS('rosterScanDocument')
external JSPromise<JSString> _scanDocument(
  JSUint8Array bytes,
  JSString name,
  JSBoolean pdf,
  JSFunction progress,
);

@JS('rosterCancelScan')
external void _cancelScan();

class SmartScanException implements Exception {
  const SmartScanException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SmartScanEngine {
  SmartScanEngine._();
  static bool get isSupported => true;
  static void cancel() => _cancelScan();

  static Future<SmartScanResult> recogniseImage({
    required Uint8List bytes,
    required String fileName,
    void Function(String, double?)? onProgress,
  }) async => (await _recognise(bytes, fileName, false, onProgress)).single;

  static Future<List<SmartScanResult>> recognisePdf({
    required Uint8List bytes,
    required String fileName,
    void Function(String, double?)? onProgress,
  }) => _recognise(bytes, fileName, true, onProgress);

  static Future<List<SmartScanResult>> _recognise(
    Uint8List bytes,
    String name,
    bool pdf,
    void Function(String, double?)? onProgress,
  ) async {
    try {
      final encoded = await _scanDocument(
        bytes.toJS,
        name.toJS,
        pdf.toJS,
        ((JSString message, JSNumber fraction) {
          final value = fraction.toDartDouble;
          onProgress?.call(message.toDart, value < 0 ? null : value);
        }).toJS,
      ).toDart;
      final decoded = jsonDecode(encoded.toDart);
      if (decoded is Map<String, dynamic>) {
        throw SmartScanException(decoded['error'] as String);
      }
      final pages = decoded as List<dynamic>;
      return pages
          .map((dynamic value) {
            final page = value as Map<String, dynamic>;
            return SmartScanResult(
              fullText: page['fullText'] as String,
              confidence: (page['confidence'] as num?)?.toDouble(),
              lines: (page['lines'] as List<dynamic>)
                  .map((dynamic value) {
                    final line = value as Map<String, dynamic>;
                    return SmartScanTextLine(
                      text: line['text'] as String,
                      left: (line['left'] as num).toDouble(),
                      top: (line['top'] as num).toDouble(),
                      right: (line['right'] as num).toDouble(),
                      bottom: (line['bottom'] as num).toDouble(),
                    );
                  })
                  .toList(growable: false),
            );
          })
          .toList(growable: false);
    } on SmartScanException {
      rethrow;
    } catch (_) {
      throw const SmartScanException(
        'The scanner could not start. Reload Roster Buddy, check your connection and try again.',
      );
    }
  }
}
