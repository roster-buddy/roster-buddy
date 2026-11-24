import '../../core/models/document_type.dart';
import '../../core/models/duty.dart';
import '../../core/models/parse_result.dart';
import '../../core/parser/daily_amendment_parser.dart';
import '../../core/parser/parser_utils.dart';
import '../../core/services/printed_roster_identity.dart';
import 'smart_scan_page_text_reconstructor.dart';
import 'smart_scan_result.dart';

/// Keeps provider table rows when rebuilding word positions loses duty details.
/// Whole pages are selected; clocks are never guessed or joined across drivers.
class DailyScanText {
  DailyScanText._();

  static Set<String> _identities(String text) => RegExp(
    r'(?<![0-9])([0-9]{4})(?![0-9])\s+([A-Za-z]{2,5})\b',
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
          RegExp(r'^\s*[0-9]{4}\s+[A-Za-z]{2,5}\b').hasMatch(line) &&
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

  static final _namedRow = RegExp(
    r"^\s*[:/\\|]*\s*([A-Za-z][A-Za-z .’'-]+?)\s+(\d{4})\s+([A-Za-z]{2,5})\b",
  );

  static String _recoverIncompleteRows(
    String primary,
    ParseResult original,
    ParseResult? retry,
  ) {
    if (retry == null) return primary;
    if (!original.hasBlockingWarnings || original.identifiedDates.length != 1) {
      return primary;
    }

    if (retry.identifiedDates.length != 1 ||
        retry.identifiedDates.first != original.identifiedDates.first) {
      return primary;
    }

    final lines = primary.split(RegExp(r'\r?\n'));
    final originalPayrolls = original.duties.map((duty) => duty.payrollNumber).toSet();
    final counts = <String, int>{};
    for (final line in lines) {
      final payroll = _namedRow.firstMatch(line)?[2];
      if (payroll != null) counts.update(payroll, (count) => count + 1, ifAbsent: () => 1);
    }

    for (var index = 0; index < lines.length; index++) {
      final row = _namedRow.firstMatch(lines[index]);
      final payroll = row?[2];
      if (row == null || counts[payroll] != 1 || originalPayrolls.contains(payroll)) {
        continue;
      }

      final matches = retry.duties.where((duty) => duty.payrollNumber == payroll);
      if (matches.length != 1) continue;
      final duty = matches.single;
      final candidateText = duty.rawText;
      final candidate = candidateText == null ? null : _namedRow.firstMatch(candidateText);
      if (candidate == null ||
          ParserUtils.normaliseWhitespace(candidate[1]!).toUpperCase() !=
              ParserUtils.normaliseWhitespace(row[1]!).toUpperCase() ||
          candidate[3]!.toUpperCase() != row[3]!.toUpperCase() ||
          duty.turnNumber == null || duty.bookOn == null || duty.bookOff == null) {
        continue;
      }

      // Any surviving clock must agree with the reread. Replace the whole
      // row so fields from different OCR readings cannot be combined.
      final clocks = RegExp(r'\b(?:[01]?\d|2[0-3])[:;][0-5]\d\b')
          .allMatches(lines[index])
          .map((match) => match[0]!.replaceAll(';', ':').padLeft(5, '0'));
      if (clocks.every((clock) => clock == duty.bookOn || clock == duty.bookOff)) {
        lines[index] = candidateText!;
      }
    }
    return lines.join('\n');
  }

  static Future<List<String>> bestPages(
    List<SmartScanResult> pages, DocumentType type,
  ) async {
    final parser = DailyAmendmentParser(documentType: type);
    final selected = <String>[];
    for (final page in pages) {
      final rebuilt = SmartScanPageTextReconstructor.reconstruct(page);
      final retry = page.alternateText.trim().isEmpty
          ? null
          : await parser.parse(pageText: [page.alternateText]);
      final rawNative = page.fullText;
      var nativeResult = await parser.parse(pageText: [rawNative]);
      final native = _recoverIncompleteRows(rawNative, nativeResult, retry);
      if (native != rawNative) {
        nativeResult = await parser.parse(pageText: [native]);
      }
      if (page.lines.isEmpty || native == rebuilt) {
        selected.add(native);
        continue;
      }
      var rebuiltText = rebuilt;
      var rebuiltResult = await parser.parse(pageText: [rebuiltText]);
      final rebuiltOriginallyHasDate =
          rebuiltResult.identifiedDates.isNotEmpty;
      // The enlarged positional pass often reads rows that the natural page
      // pass misses, but can crop away the report heading. Give that reading
      // the date already confirmed by the natural pass so it can contribute
      // safe, complementary payroll rows. This does not infer a date from the
      // device or filename.
      if (!rebuiltOriginallyHasDate &&
          nativeResult.identifiedDates.isNotEmpty) {
        final date = nativeResult.identifiedDates.first;
        final heading =
            'Report for ${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/'
            '${(date.year % 100).toString().padLeft(2, '0')}';
        rebuiltText = '$heading\n$rebuilt';
        rebuiltResult = await parser.parse(pageText: [rebuiltText]);
      }
      final recovered = _recoverIncompleteRows(rebuiltText, rebuiltResult, retry);
      if (recovered != rebuiltText) {
        rebuiltText = recovered;
        rebuiltResult = await parser.parse(pageText: [rebuiltText]);
      }
      final nativeByKey = {for (final d in nativeResult.duties) _key(d): d};
      final nativeHasDate = nativeResult.identifiedDates.isNotEmpty;
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
      // A daily roster cannot be imported without its report date. The
      // positional OCR reread can reconstruct the table well but occasionally
      // drops the heading entirely. Never let that undated reread replace a
      // cloud reading which retained a valid report date.
      final useNative = nativeHasDate &&
          (!rebuiltOriginallyHasDate ||
              (datesAgree &&
                  ((keepsIdentities && keepsReadDuties && improves) ||
                      nativeHasBetterCoverage ||
                      nativePreservesPayrollOnlyRow)));
      var choice = useNative ? native : rebuiltText;
      final choiceResult = useNative ? nativeResult : rebuiltResult;
      final otherResult = useNative ? rebuiltResult : nativeResult;
      final choicePayrolls = choiceResult.duties
          .map((duty) => PrintedRosterIdentity.payrollKey(duty.payrollNumber))
          .whereType<String>()
          .toSet();
      final complementaryRows = (nativePreservesPayrollOnlyRow
              ? const <Duty>[]
              : otherResult.duties)
          .where((duty) => !choicePayrolls.contains(
                PrintedRosterIdentity.payrollKey(duty.payrollNumber),
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
