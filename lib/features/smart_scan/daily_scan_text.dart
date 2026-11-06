import '../../core/models/document_type.dart';
import '../../core/models/duty.dart';
import '../../core/models/parse_result.dart';
import '../../core/parser/daily_amendment_parser.dart';
import '../../core/services/printed_roster_identity.dart';
import 'smart_scan_page_text_reconstructor.dart';
import 'smart_scan_result.dart';

/// Keeps provider table rows when rebuilding word positions loses duty details.
/// Whole pages are selected; clocks are never guessed or joined across drivers.
class DailyScanText {
  DailyScanText._();

  static Set<String> _identities(String text) => RegExp(
    r'\b([0-9]{4,8})\s+([A-Za-z]{2,5})\b',
  ).allMatches(text).map((m) => '${m[1]}|${m[2]!.toUpperCase()}').toSet();

  static Set<String> _payrolls(String text) => _identities(text)
      .map((identity) => identity.split('|').first)
      .toSet();

  static String _key(Duty duty) =>
      '${duty.date.toIso8601String()}|'
      '${PrintedRosterIdentity.payrollKey(duty.payrollNumber) ?? duty.payrollNumber}';

  static bool _agrees(Duty first, Duty second) =>
      first.bookOn == second.bookOn && first.bookOff == second.bookOff &&
      first.turnNumber == second.turnNumber && first.dutyType == second.dutyType;

  static String _nameKey(String? value) => (value ?? '')
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool _samePayrollDriver(Duty first, Duty second) {
    if (PrintedRosterIdentity.payrollKey(first.payrollNumber) !=
        PrintedRosterIdentity.payrollKey(second.payrollNumber)) {
      return false;
    }
    final firstName = _nameKey(first.driverName);
    final secondName = _nameKey(second.driverName);
    return firstName.isEmpty || secondName.isEmpty || firstName == secondName;
  }

  static int _blocking(ParseResult result) =>
      result.warnings.where((w) => w.preventsImport).length;

  /// Prefer the OCR reading that turns the printed payroll rows into the same
  /// number of parsed duties. A larger raw duty count is not automatically
  /// better: a broken name can otherwise split one printed row into a phantom
  /// extra duty while losing the real payroll number.
  static int _coverageScore(String text, ParseResult result) {
    final printed = _payrolls(text);
    final parsed = result.duties
        .map((duty) => duty.payrollNumber)
        .whereType<String>()
        .toSet();
    final matched = printed.intersection(parsed).length;
    final missing = printed.difference(parsed).length;
    final extras = parsed.difference(printed).length;
    return matched * 100 - missing * 100 - extras * 10 -
        _blocking(result) * 1000;
  }

  static bool _hasCompletePayrollOnlyRow(String text) => text
      .split(RegExp(r'\r?\n'))
      .any((line) =>
          RegExp(r'^\s*[0-9]{4,8}\s+[A-Za-z]{2,5}\b').hasMatch(line) &&
          RegExp(r'\b[0-2]?[0-9][;:][0-5][0-9]\b')
                  .allMatches(line)
                  .length >=
              2);

  static bool _commonDutiesAgree(ParseResult first, ParseResult second) {
    final secondByKey = {for (final duty in second.duties) _key(duty): duty};
    return first.duties.every((duty) {
      final other = secondByKey[_key(duty)];
      return other == null || _agrees(duty, other);
    });
  }

  static Future<List<String>> bestPages(
    List<SmartScanResult> pages, DocumentType type,
  ) async {
    final parser = DailyAmendmentParser(documentType: type);
    final selected = <String>[];
    for (final page in pages) {
      final rebuilt = SmartScanPageTextReconstructor.reconstruct(page);
      final native = page.fullText;
      if (page.lines.isEmpty || native.trim().isEmpty || native == rebuilt) {
        selected.add(rebuilt);
        continue;
      }
      final rebuiltResult = await parser.parse(pageText: [rebuilt]);
      final nativeResult = await parser.parse(pageText: [native]);
      final nativeByKey = {for (final d in nativeResult.duties) _key(d): d};
      final datesAgree = rebuiltResult.identifiedDates.isNotEmpty &&
          nativeResult.identifiedDates.toSet().containsAll(rebuiltResult.identifiedDates) &&
          rebuiltResult.identifiedDates.toSet().containsAll(nativeResult.identifiedDates);
      final keepsIdentities = _identities(native).containsAll(_identities(rebuilt));
      final keepsReadDuties = rebuiltResult.duties.every((d) =>
          nativeByKey[_key(d)] != null && _agrees(d, nativeByKey[_key(d)]!));
      final improves = nativeResult.duties.length > rebuiltResult.duties.length &&
          _blocking(nativeResult) <= _blocking(rebuiltResult);
      final nativeHasBetterCoverage =
          _coverageScore(native, nativeResult) >
              _coverageScore(rebuilt, rebuiltResult) &&
          _blocking(nativeResult) <= _blocking(rebuiltResult) &&
          _commonDutiesAgree(nativeResult, rebuiltResult);
      final nativePreservesPayrollOnlyRow =
          _hasCompletePayrollOnlyRow(native) &&
          _blocking(nativeResult) == 0 &&
          _commonDutiesAgree(nativeResult, rebuiltResult);
      final useNative = datesAgree &&
          ((keepsIdentities && keepsReadDuties && improves) ||
              nativeHasBetterCoverage ||
              nativePreservesPayrollOnlyRow);
      var choice = useNative ? native : rebuilt;
      final choiceResult = useNative ? nativeResult : rebuiltResult;
      final otherResult = useNative ? rebuiltResult : nativeResult;
      final complementaryRows = (nativePreservesPayrollOnlyRow
              ? const <Duty>[]
              : otherResult.duties)
          .where((duty) => !choiceResult.duties.any(
                (chosen) => _samePayrollDriver(chosen, duty),
              ))
          .map((duty) => duty.rawText)
          .whereType<String>()
          .where((row) => row.trim().isNotEmpty)
          .toList();
      if (complementaryRows.isNotEmpty) {
        choice = '$choice\n${complementaryRows.join('\n')}';
      }
      selected.add(choice);
    }
    return selected;
  }
}
