import '../models/document_type.dart';
import '../models/duty.dart';
import '../models/duty_code.dart';
import '../models/duty_type.dart';
import '../models/parse_result.dart';
import '../models/parse_warning.dart';
import '../models/roster_source.dart';
import 'amendment_column_map.dart';
import 'base_parser.dart';
import 'parser_utils.dart';
import 'table_extractor.dart';

class DailyAmendmentParser implements BaseParser {
  DailyAmendmentParser({
    required this.documentType,
    TableExtractor? tableExtractor,
    AmendmentColumnDetector? columnDetector,
  }) : tableExtractor = tableExtractor ?? const TableExtractor(),
       columnDetector = columnDetector ?? const AmendmentColumnDetector() {
    if (!_supportedTypes.contains(documentType)) {
      throw ArgumentError.value(
        documentType,
        'documentType',
        'DailyAmendmentParser only supports 10-Day, 7-Day and 48-Hour documents.',
      );
    }
  }

  final DocumentType documentType;
  final TableExtractor tableExtractor;
  final AmendmentColumnDetector columnDetector;

  static const Set<DocumentType> _supportedTypes = {
    DocumentType.tenDayAmendment,
    DocumentType.sevenDayAmendment,
    DocumentType.fortyEightHourAmendment,
  };

  @override
  DocumentType get supportedType => documentType;

  RosterSource get rosterSource {
    switch (documentType) {
      case DocumentType.tenDayAmendment:
        return RosterSource.tenDay;

      case DocumentType.sevenDayAmendment:
        return RosterSource.sevenDay;

      case DocumentType.fortyEightHourAmendment:
        return RosterSource.fortyEightHour;

      default:
        throw StateError('Unsupported daily amendment type: $documentType');
    }
  }

  @override
  bool canParse(List<String> pageText) {
    if (pageText.isEmpty) {
      return false;
    }

    final text = pageText.join('\n').toUpperCase();
    final table = tableExtractor.extract(pageText);
    final detectedColumns = columnDetector.detect(table.rows);

    final hasDailySheetColumns =
        detectedColumns?.hasRequiredColumns == true ||
        ((text.contains('PAY NO') ||
                text.contains('PAYROLL') ||
                text.contains('PAY NUMBER')) &&
            (text.contains('TURN') ||
                text.contains('BOOK ON') ||
                text.contains('BOOK OFF') ||
                text.contains('ROSTERED HOURS')));

    if (!hasDailySheetColumns) {
      return false;
    }

    switch (documentType) {
      case DocumentType.tenDayAmendment:
        return text.contains('10 DAY') ||
            text.contains('10-DAY') ||
            text.contains('TEN DAY');

      case DocumentType.sevenDayAmendment:
        return text.contains('7 DAY') ||
            text.contains('7-DAY') ||
            text.contains('SEVEN DAY');

      case DocumentType.fortyEightHourAmendment:
        return text.contains('48 HOUR') ||
            text.contains('48-HOUR') ||
            text.contains('FORTY EIGHT HOUR') ||
            _looksLikeSundaySheet(text);

      default:
        return false;
    }
  }

  @override
  Future<ParseResult> parse({required List<String> pageText}) async {
    final table = tableExtractor.extract(pageText);
    final duties = <Duty>[];
    final warnings = <ParseWarning>[];
    final seenKeys = <String>{};
    final reportDates = <DateTime>{};

    for (var pageIndex = 0; pageIndex < pageText.length; pageIndex++) {
      final pageNumber = pageIndex + 1;
      final page = pageText[pageIndex];
      final dutyDate = _extractPageDate(page);

      if (dutyDate == null) {
        warnings.add(
          ParseWarning(
            message: 'No valid duty date was detected on page $pageNumber.',
            pageNumber: pageNumber,
          ),
        );
        continue;
      }

      reportDates.add(dutyDate);
      final pageRows = _joinWrappedRows(table.rowsForPage(pageNumber));
      final columnMap = columnDetector.detect(pageRows);

      if (columnMap == null) {
        warnings.add(
          ParseWarning(
            message:
                'No usable amendment header was detected on page $pageNumber. '
                'Roster Buddy used fallback row recognition for this page.',
            pageNumber: pageNumber,
            severity: ParseWarningSeverity.information,
          ),
        );
      }

      for (final row in pageRows) {
        if (row.isEmpty || _isHeaderRow(row, columnMap)) {
          continue;
        }

        final printed = _printedRow.firstMatch(row.rawText);
        final duty = printed != null || columnMap == null
            ? _parseFallbackRow(row: row, date: dutyDate)
            : _parseMappedRow(row: row, date: dutyDate, columnMap: columnMap);

        if (printed != null && duty == null) {
          warnings.add(
            ParseWarning(
              message:
                  'A roster row could not be read safely on page $pageNumber: ${row.rawText}',
              pageNumber: pageNumber,
              severity: ParseWarningSeverity.blocking,
            ),
          );
        }
        if (duty != null && seenKeys.add(duty.uniqueKey)) {
          duties.add(duty);
        }
      }
    }

    if (duties.isEmpty) {
      warnings.add(
        const ParseWarning(
          message:
              'No amendment rows containing a payroll number and duty information were detected.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    return ParseResult(
      documentType: documentType,
      duties: duties,
      identifiedDates: reportDates.toList(),
      pagesProcessed: pageText.length,
      recordsDetected: duties.length,
      warnings: warnings,
    );
  }

  bool _isHeaderRow(ExtractedTableRow row, AmendmentColumnMap? columnMap) {
    // "Amended Turn" is a remark on real data rows, not a table heading.
    if (_printedRow.hasMatch(row.rawText)) return false;
    if (row.isLikelyHeader) {
      return true;
    }

    if (columnMap == null) {
      return false;
    }

    return row.pageNumber == columnMap.headerPageNumber &&
        row.lineNumber == columnMap.headerLineNumber;
  }

  Duty? _parseMappedRow({
    required ExtractedTableRow row,
    required DateTime date,
    required AmendmentColumnMap columnMap,
  }) {
    final payrollNumber = ParserUtils.normalisePayrollNumber(
      columnMap.payrollValue(row),
    );

    if (!_isPlausiblePayrollNumber(payrollNumber)) {
      return null;
    }

    final turnNumber = ParserUtils.normaliseTurnNumber(
      columnMap.turnValue(row),
    );

    final bookOn = ParserUtils.normaliseTime(columnMap.bookOnValue(row));

    final bookOff = ParserUtils.normaliseTime(columnMap.bookOffValue(row));

    final amendmentCode = _normaliseAmendmentCode(
      columnMap.amendmentCodeValue(row),
    );

    if (!_hasDutyInformation(
      turnNumber: turnNumber,
      amendmentCode: amendmentCode,
      bookOn: bookOn,
      bookOff: bookOff,
    )) {
      return null;
    }

    final codeDefinition = DutyCodeLibrary.find(amendmentCode);
    final dutyType = _determineDutyType(
      codeDefinition: codeDefinition,
      rawText: row.rawText,
      hasTimes: bookOn != null || bookOff != null,
    );

    final printedRosteredMinutes = ParserUtils.parseRosteredMinutes(
      columnMap.rosteredHoursValue(row),
    );

    final calculatedMinutes = bookOn != null && bookOff != null
        ? ParserUtils.calculateDutyMinutes(bookOn, bookOff)
        : 0;

    final rosteredMinutes =
        printedRosteredMinutes ??
        (calculatedMinutes > 0 ? calculatedMinutes : null);

    final printedRemarks = columnMap.remarksValue(row);
    final codeMeaning = codeDefinition?.preferredMeaning;

    return Duty(
      date: date,
      source: rosterSource,
      dutyType: dutyType,
      turnNumber: turnNumber,
      bookOn: bookOn,
      bookOff: bookOff,
      rosteredMinutes: rosteredMinutes,
      payrollNumber: payrollNumber,
      driverName: _cleanOptionalValue(columnMap.nameValue(row)),
      depot: _cleanOptionalValue(columnMap.depotValue(row)),
      amendmentCode: amendmentCode,
      mileage: _cleanOptionalValue(columnMap.mileageValue(row)),
      pageNumber: row.pageNumber,
      rawText: row.rawText,
      remarks: _buildRemarks(
        codeMeaning: codeMeaning,
        printedRemarks: printedRemarks,
      ),
    );
  }

  // Printed Daily Roster Reports have wrapped headings and blank columns.
  // Match the name/pay/depot prefix, then read clocks ONLY after the depot.
  static final _printedRow = RegExp(
    r'^(.+?)\s+([0-9]{4,8})\s+([A-Za-z]{2,5})\b(.*)$',
  );
  static final _printedClock = RegExp(
    r'(?<![0-9])([0-2]?[0-9])[:;]([0-5][0-9])(?![0-9])',
  );

  Duty? _parseFallbackRow({
    required ExtractedTableRow row,
    required DateTime date,
  }) {
    final match = _printedRow.firstMatch(row.rawText);
    if (match == null) return null;
    final name = match.group(1)!.trim();
    if (!RegExp(r'[A-Za-z]{2,}').hasMatch(name) ||
        RegExp(r'[0-9]{3,}|[/\\:]').hasMatch(name) ||
        name.toLowerCase().contains('vacancy')) {
      return null;
    }
    final payroll = match.group(2)!;
    final depot = match.group(3)!.toUpperCase();
    final tail = match.group(4)!
        .replaceAll(RegExp(r'\[\s*\d+\s*\]|\(\s*\d+\s*\)'), ' ')
        .trim();
    final clocks = _printedClock.allMatches(tail).toList();
    final prefix = clocks.isEmpty
        ? tail
        : tail.substring(0, clocks.first.start);
    final tokens = prefix
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty)
        .toList();
    String? code;
    String? turn;
    for (final scannedToken in tokens) {
      // OCR can confuse D with O in this no-duty code. Only correct a
      // standalone code on rows without shift clocks; keep rawText intact.
      final token = clocks.isEmpty
          ? _correctNoDutyCode(scannedToken)
          : scannedToken;
      if (RegExp(r'^(?:WO)?[0-9]{1,4}$').hasMatch(token)) {
        turn = token.replaceFirst(RegExp(r'^WO'), '');
      } else if (token == 'ALLOC' || DutyCodeLibrary.contains(token)) {
        code ??= token;
      }
    }
    final definition = DutyCodeLibrary.find(code);
    final type = _determineDutyType(
      codeDefinition: definition,
      rawText: ' $tail ',
      hasTimes: clocks.length >= 2,
    );
    final nonWorking =
        type == DutyType.annualLeave ||
        type == DutyType.restDay ||
        type == DutyType.sick ||
        type == DutyType.unavailable ||
        type == DutyType.publicHoliday;
    if (!nonWorking && clocks.length != 2) return null;
    if (nonWorking && code == null) return null;
    final on = nonWorking
        ? null
        : ParserUtils.normaliseTime(clocks[0].group(0));
    final off = nonWorking
        ? null
        : ParserUtils.normaliseTime(clocks[1].group(0));
    if (!nonWorking && (on == null || off == null)) return null;
    final remaining = clocks.length >= 2 ? tail.substring(clocks[1].end) : '';
    final duration = RegExp(
      r'^\s*([0-9]{1,2}[.:][0-9]{2})\b',
    ).firstMatch(remaining);
    return Duty(
      date: date,
      source: rosterSource,
      dutyType: type,
      turnNumber: nonWorking ? null : turn,
      bookOn: on,
      bookOff: off,
      rosteredMinutes: nonWorking
          ? null
          : ParserUtils.parseRosteredMinutes(duration?.group(1)) ??
                ParserUtils.calculateDutyMinutes(on!, off!),
      payrollNumber: payroll,
      driverName: name,
      depot: depot,
      amendmentCode: code,
      pageNumber: row.pageNumber,
      rawText: row.rawText,
      remarks: definition?.preferredMeaning,
    );
  }

  List<ExtractedTableRow> _joinWrappedRows(List<ExtractedTableRow> rows) {
    final joined = <ExtractedTableRow>[];
    for (final row in rows) {
      // Only numeric clocks/hours and the standard remark can continue a row.
      // A new named driver, vacancy, heading or unknown text starts its own row.
      final continuation = RegExp(
        r'^(?:(?:[0-9]{1,2}[:.;][0-9]{2})\s*)*(?:Amended\s+Turn)?$',
        caseSensitive: false,
      ).hasMatch(row.rawText);
      if (continuation && joined.isNotEmpty &&
          _printedRow.hasMatch(joined.last.rawText)) {
        final previous = joined.removeLast();
        joined.add(ExtractedTableRow(
          pageNumber: previous.pageNumber,
          lineNumber: previous.lineNumber,
          rawText: '${previous.rawText} ${row.rawText}',
          columns: [...previous.columns, ...row.columns],
        ));
      } else {
        joined.add(row);
      }
    }
    return joined;
  }

  DateTime? _extractPageDate(String pageText) {
    // Screenshot viewer timestamps may precede a partially cropped report heading.
    // A weekday followed by a date is still a report heading when "Report" is cut off.
    final headings = RegExp(
      r'\b(?:REPORT\s+FOR|MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY|SUNDAY)\b[^\n]*',
      caseSensitive: false,
    ).allMatches(pageText);
    for (final heading in headings) {
      final dates = ParserUtils.extractDates(heading.group(0)!);
      if (dates.isNotEmpty) return dates.first;
    }
    final dates = ParserUtils.extractDates(pageText);

    if (dates.isEmpty) {
      return null;
    }

    return dates.first;
  }

  String _correctNoDutyCode(String code) {
    if (code == 'NONA') return 'NDNA';
    if (code == 'NO') return 'ND';
    return code;
  }

  String? _normaliseAmendmentCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final scannedCode = DutyCodeLibrary.normaliseCode(value);
    final code = _correctNoDutyCode(scannedCode);

    if (code.isEmpty) {
      return null;
    }

    if (DutyCodeLibrary.contains(code)) {
      return code;
    }

    for (final match in RegExp(r'[A-Z]{1,3}\d?').allMatches(code)) {
      final candidate = match.group(0);

      if (candidate != null && DutyCodeLibrary.contains(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  bool _isPlausiblePayrollNumber(String? value) {
    if (value == null) {
      return false;
    }

    return RegExp(r'^\d{4,8}$').hasMatch(value);
  }

  bool _hasDutyInformation({
    required String? turnNumber,
    required String? amendmentCode,
    required String? bookOn,
    required String? bookOff,
  }) {
    return turnNumber != null ||
        amendmentCode != null ||
        bookOn != null ||
        bookOff != null;
  }

  DutyType _determineDutyType({
    required DutyCodeDefinition? codeDefinition,
    required String rawText,
    required bool hasTimes,
  }) {
    if (codeDefinition != null && codeDefinition.dutyType != DutyType.unknown) {
      return codeDefinition.dutyType;
    }

    final text = rawText.toUpperCase();

    if (text.contains('ANNUAL LEAVE') ||
        text.contains(' A/L ') ||
        text.contains(' ALD ') ||
        text.contains(' ALW ')) {
      return DutyType.annualLeave;
    }

    if (text.contains('SICK')) {
      return DutyType.sick;
    }

    if (text.contains('REST DAY') || text.contains('RESTDAY')) {
      return DutyType.restDay;
    }

    if (text.contains('TRAINING') ||
        text.contains('COURSE') ||
        text.contains('BRIEF')) {
      return DutyType.training;
    }

    if (text.contains('MEDICAL')) {
      return DutyType.medical;
    }

    if (text.contains('BANK HOLIDAY') || text.contains('PUBLIC HOLIDAY')) {
      return DutyType.publicHoliday;
    }

    if (hasTimes) {
      return DutyType.working;
    }

    return DutyType.unknown;
  }

  String? _buildRemarks({
    required String? codeMeaning,
    required String? printedRemarks,
  }) {
    final meaning = _cleanOptionalValue(codeMeaning);
    final remarks = _cleanOptionalValue(printedRemarks);

    if (meaning == null) {
      return remarks;
    }

    if (remarks == null) {
      return meaning;
    }

    if (remarks.toUpperCase() == meaning.toUpperCase()) {
      return remarks;
    }

    return '$meaning — $remarks';
  }

  String? _cleanOptionalValue(String? value) {
    if (value == null) {
      return null;
    }

    final cleaned = ParserUtils.normaliseWhitespace(value);

    return cleaned.isEmpty ? null : cleaned;
  }

  bool _looksLikeSundaySheet(String text) {
    final containsSunday =
        text.contains('SUNDAY') || RegExp(r'\bSUN\b').hasMatch(text);

    final containsDailyColumns =
        text.contains('PAY NO') ||
        text.contains('PAYROLL') ||
        text.contains('PAY NUMBER');

    final explicitlyAnotherType =
        text.contains('10 DAY') ||
        text.contains('10-DAY') ||
        text.contains('TEN DAY') ||
        text.contains('7 DAY') ||
        text.contains('7-DAY') ||
        text.contains('SEVEN DAY');

    return containsSunday && containsDailyColumns && !explicitlyAnotherType;
  }
}
