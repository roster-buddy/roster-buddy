import '../../core/models/document_type.dart';
import '../../core/models/duty.dart';
import '../../core/models/parse_result.dart';
import '../../core/parser/daily_amendment_parser.dart';
import 'smart_scan_page_text_reconstructor.dart';
import 'smart_scan_result.dart';

/// Keeps provider table rows when rebuilding word positions loses duty details.
/// Whole pages are selected; clocks are never guessed or joined across drivers.
class DailyScanText {
  DailyScanText._();

  static Set<String> _identities(String text) => RegExp(
    r'\b([0-9]{4,8})\s+([A-Za-z]{2,5})\b',
  ).allMatches(text).map((m) => '${m[1]}|${m[2]!.toUpperCase()}').toSet();

  static String _key(Duty duty) =>
      '${duty.date.toIso8601String()}|${duty.payrollNumber}';

  static bool _agrees(Duty first, Duty second) =>
      first.bookOn == second.bookOn && first.bookOff == second.bookOff &&
      first.turnNumber == second.turnNumber && first.dutyType == second.dutyType;

  static int _blocking(ParseResult result) =>
      result.warnings.where((w) => w.preventsImport).length;

  static Set<String> _resultPayrolls(ParseResult result) => result.duties
      .map((d) => d.payrollNumber)
      .whereType<String>()
      .toSet();

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
      final rebuiltPayrolls = _resultPayrolls(rebuiltResult);
      final nativePayrolls = _resultPayrolls(nativeResult);
      final overlap = rebuiltPayrolls.intersection(nativePayrolls).length;
      final nearSameRoster = rebuiltPayrolls.length >= 5 &&
          rebuiltPayrolls.length == nativePayrolls.length &&
          rebuiltPayrolls.difference(nativePayrolls).isNotEmpty &&
          overlap / rebuiltPayrolls.length >= 0.8;
      final sharedRowsAgree = rebuiltResult.duties
          .where((d) => nativeByKey.containsKey(_key(d)))
          .every((d) => _agrees(d, nativeByKey[_key(d)]!));
      final datesAgree = rebuiltResult.identifiedDates.isNotEmpty &&
          nativeResult.identifiedDates.toSet().containsAll(rebuiltResult.identifiedDates) &&
          rebuiltResult.identifiedDates.toSet().containsAll(nativeResult.identifiedDates);
      final keepsIdentities = _identities(native).containsAll(_identities(rebuilt));
      final keepsReadDuties = rebuiltResult.duties.every((d) =>
          nativeByKey[_key(d)] != null && _agrees(d, nativeByKey[_key(d)]!));
      final improves = nativeResult.duties.length > rebuiltResult.duties.length &&
          _blocking(nativeResult) <= _blocking(rebuiltResult);
      final useNative = datesAgree &&
          ((keepsIdentities && keepsReadDuties && improves) ||
              (nearSameRoster && sharedRowsAgree));
      var choice = useNative ? native : rebuilt;
      final choiceResult = useNative ? nativeResult : rebuiltResult;
      final otherResult = useNative ? rebuiltResult : nativeResult;
      final choiceKeys = choiceResult.duties.map(_key).toSet();
      final complementaryRows = otherResult.duties
          // On a full sheet, equal-size OCR sets differing by one payroll are
          // alternative readings of the same row, not two separate drivers.
          // Prefer the provider's natural reading order and do not append the
          // positioned-word misread as a phantom extra record.
          .where((_) => !nearSameRoster)
          .where((duty) => !choiceKeys.contains(_key(duty)))
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
