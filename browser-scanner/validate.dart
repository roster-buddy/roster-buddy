// Consumes actual OCR output from Chromium and WebKit, then exercises the
// production row reconstruction, classification and amendment parser.
import 'dart:convert';
import 'dart:io';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/parser/daily_amendment_parser.dart';
import 'package:roster_buddy/core/parser/document_classifier.dart';
import 'package:roster_buddy/features/smart_scan/smart_scan_page_text_reconstructor.dart';
import 'package:roster_buddy/features/smart_scan/smart_scan_result.dart';

Future<void> main() async {
  final fixtures = Directory('browser-scanner/.results')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList();
  if (fixtures.length != 4) {
    throw StateError('Expected photo and PDF OCR from both browsers');
  }
  for (final fixture in fixtures) {
    final pages = (jsonDecode(fixture.readAsStringSync()) as List).map((
      dynamic item,
    ) {
      final page = item as Map<String, dynamic>;
      return SmartScanResult(
        fullText: page['fullText'] as String,
        lines: (page['lines'] as List).map((dynamic item) {
          final line = item as Map<String, dynamic>;
          return SmartScanTextLine(
            text: line['text'] as String,
            left: (line['left'] as num).toDouble(),
            top: (line['top'] as num).toDouble(),
            right: (line['right'] as num).toDouble(),
            bottom: (line['bottom'] as num).toDouble(),
          );
        }).toList(),
      );
    }).toList();
    final text = SmartScanPageTextReconstructor.reconstructPages(pages);
    final type = const DocumentClassifier().classify(text);
    if (type != DocumentType.fortyEightHourAmendment) {
      throw StateError('Heading lost: ${fixture.path}');
    }
    final result = await DailyAmendmentParser(
      documentType: type,
    ).parse(pageText: text);
    if (!result.canImport || result.duties.length != pages.length) {
      throw StateError(
        'OCR did not produce complete duties in ${fixture.path}:\n${text.join("\n")}\n${result.warnings.map((w) => w.message).join("\n")}',
      );
    }
    for (var i = 0; i < result.duties.length; i++) {
      final d = result.duties[i];
      if (d.payrollNumber != '21910' ||
          d.bookOn != '04:25' ||
          d.bookOff != '12:58' ||
          d.date != DateTime(2026, 8, 3 + i) ||
          d.turnNumber != '${204 + i}') {
        throw StateError(
          'Wrong calendar record from ${fixture.path}: ${d.rawText}',
        );
      }
    }
    stdout.writeln(
      'PASS real browser OCR → parser → correct calendar records: ${fixture.path}',
    );
  }
}
