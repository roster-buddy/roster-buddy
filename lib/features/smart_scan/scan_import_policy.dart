import '../../core/models/duty_type.dart';
import '../../core/models/parse_result.dart';
import '../../core/models/parse_warning.dart';
import 'smart_scan_page_text_reconstructor.dart';
import 'smart_scan_result.dart';

class ScanImportPolicy {
  ScanImportPolicy._();

  static Set<String> _payrolls(String text) => RegExp(
    r'\b([0-9]{4,8})\s+[A-Za-z]{2,5}\b',
  ).allMatches(text).map((m) => m[1]!).toSet();

  static bool hasRosterRows(List<SmartScanResult> pages) => pages.any(
    (p) => _payrolls(p.fullText).isNotEmpty ||
        _payrolls(SmartScanPageTextReconstructor.reconstruct(p)).isNotEmpty,
  );

  static bool allRowsRead(ParseResult result, List<SmartScanResult> pages) {
    if (!result.canImport || result.duties.isEmpty ||
        result.identifiedDates.isEmpty || result.pagesProcessed != pages.length ||
        result.warnings.any((w) => w.severity != ParseWarningSeverity.information) ||
        result.duties.any((d) => d.dutyType == DutyType.unknown) ||
        pages.any((p) => p.confidence != null && p.confidence! < 65)) {
      return false;
    }
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final payrolls = {..._payrolls(page.fullText),
        ..._payrolls(SmartScanPageTextReconstructor.reconstruct(page))};
      final duties = result.duties.where((d) => d.pageNumber == i + 1).toList();
      if (payrolls.isEmpty || payrolls.length != duties.length) return false;
    }
    return true;
  }
}
