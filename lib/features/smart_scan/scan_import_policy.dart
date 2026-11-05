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

  /// Browser OCR supplies both its natural reading order and positioned words.
  /// The daily parser deliberately chooses the better of those two versions.
  /// Do the same when checking completeness: merging both sets can create a
  /// phantom extra payroll when the poorer version misreads one digit.
  static Set<String> _bestPayrolls(
    SmartScanResult page,
    Set<String?> parsedPayrolls,
  ) {
    final candidates = <Set<String>>[
      _payrolls(page.fullText),
      _payrolls(SmartScanPageTextReconstructor.reconstruct(page)),
    ];
    candidates.sort((first, second) {
      int score(Set<String> values) {
        final matches = values.where(parsedPayrolls.contains).length;
        final extras = values
            .where((value) => !parsedPayrolls.contains(value))
            .length;
        final missing = parsedPayrolls
            .where((value) => value != null && !values.contains(value))
            .length;
        return matches * 100 - extras * 10 - missing;
      }

      return score(second).compareTo(score(first));
    });
    return candidates.first;
  }

  static String _bestPayrollText(
    SmartScanResult page,
    Set<String?> parsedPayrolls,
  ) {
    final candidates = <String>[
      page.fullText,
      SmartScanPageTextReconstructor.reconstruct(page),
    ];
    candidates.sort((first, second) {
      int score(String text) {
        final values = _payrolls(text);
        final matches = values.where(parsedPayrolls.contains).length;
        final extras = values
            .where((value) => !parsedPayrolls.contains(value))
            .length;
        final missing = parsedPayrolls
            .where((value) => value != null && !values.contains(value))
            .length;
        return matches * 100 - extras * 10 - missing;
      }

      return score(second).compareTo(score(first));
    });
    return candidates.first;
  }

  static List<ParseWarning> unmatchedRows(
    ParseResult result,
    List<SmartScanResult> pages,
  ) {
    final rows = <ParseWarning>[];
    for (var i = 0; i < pages.length; i++) {
      final parsedPayrolls = result.duties
          .where((d) => d.pageNumber == i + 1)
          .map((d) => d.payrollNumber)
          .toSet();
      final text = _bestPayrollText(pages[i], parsedPayrolls);
      final missing = _payrolls(text).where(
        (payroll) => !parsedPayrolls.contains(payroll),
      );
      for (final payroll in missing) {
        final line = text.split(RegExp(r'\r?\n')).firstWhere(
          (value) => RegExp(
            '\\b${RegExp.escape(payroll)}\\s+[A-Za-z]{2,5}\\b',
          ).hasMatch(value),
          orElse: () => 'Payroll $payroll',
        );
        rows.add(
          ParseWarning(
            message: 'Unresolved roster row on page ${i + 1}: ${line.trim()}',
            pageNumber: i + 1,
            severity: ParseWarningSeverity.blocking,
          ),
        );
      }
    }
    return rows;
  }

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
      final duties = result.duties.where((d) => d.pageNumber == i + 1).toList();
      final parsedPayrolls = duties.map((d) => d.payrollNumber).toSet();
      final payrolls = _bestPayrolls(page, parsedPayrolls);
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
      if (payrolls.length >= 5) {
        final lengths = <int, int>{};
        for (final payroll in payrolls) {
          lengths.update(payroll.length, (count) => count + 1, ifAbsent: () => 1);
        }
        final majority = lengths.values.reduce((a, b) => a > b ? a : b);
        if (lengths.length > 1 && majority / payrolls.length >= 0.8) {
          reasons.add(
            'Page ${i + 1}: one or more payroll numbers have a different length from the rest. '
            'Check those rows for a scanning error.',
          );
        }
      }
    }
    return reasons;
  }
}
