import '../../core/models/duty_type.dart';
import '../../core/models/parse_result.dart';
import '../../core/models/parse_warning.dart';
import 'smart_scan_page_text_reconstructor.dart';
import 'smart_scan_result.dart';

class ScanImportPolicy {
  ScanImportPolicy._();

  static Set<String> _payrolls(String text) =>
      RegExp(r'\b([0-9]{4,8})\s+[A-Za-z]{2,5}\b')
          .allMatches(text)
          .map((m) => m[1]!)
          .toSet();

  static bool hasRosterRows(List<SmartScanResult> pages) => pages.any(
    (p) =>
        _payrolls(p.fullText).isNotEmpty ||
        _payrolls(SmartScanPageTextReconstructor.reconstruct(p)).isNotEmpty,
  );

  static bool allRowsRead(ParseResult result, List<SmartScanResult> pages) =>
      reviewReasons(result, pages).isEmpty;

  static List<String> reviewReasons(
    ParseResult result,
    List<SmartScanResult> pages,
  ) {
    final reasons = <String>[];
    if (!result.canImport || result.duties.isEmpty) {
      reasons.add(
        'Some rows could not be read safely. Check the warnings below.',
      );
    }
    if (result.identifiedDates.isEmpty) {
      reasons.add('The sheet date could not be confirmed.');
    }
    if (result.pagesProcessed != pages.length) {
      reasons.add('Not every page was processed.');
    }
    if (result.warnings.any(
      (w) => w.severity != ParseWarningSeverity.information,
    )) {
      reasons.add('The scan has warnings that need checking.');
    }
    if (result.duties.any((d) => d.dutyType == DutyType.unknown)) {
      reasons.add('Some duty types could not be recognised.');
    }
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page.confidence != null && page.confidence! < 65) {
        reasons.add(
          'Page ${i + 1}: text recognition is uncertain. Check the rows against the original sheet.',
        );
      }
      final payrolls = {
        ..._payrolls(page.fullText),
        ..._payrolls(SmartScanPageTextReconstructor.reconstruct(page)),
      };
      final duties = result.duties.where((d) => d.pageNumber == i + 1).toList();
      final parsedPayrolls = duties.map((d) => d.payrollNumber).toSet();
      if (payrolls.isEmpty) {
        reasons.add(
          'Page ${i + 1}: the scanner could not verify all payroll rows.',
        );
      } else if (payrolls.length != duties.length ||
          !parsedPayrolls.containsAll(payrolls)) {
        reasons.add(
          'Page ${i + 1}: ${payrolls.length} payroll rows detected, '
          '${duties.length} shift records read. Some rows could be missing or mismatched.',
        );
      }
    }
    return reasons;
  }
}
