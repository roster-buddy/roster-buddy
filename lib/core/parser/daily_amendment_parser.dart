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

      final pageRows = table.rowsForPage(pageNumber);
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

        final duty = columnMap == null
            ? _parseFallbackRow(row: row, date: dutyDate)
            : _parseMappedRow(row: row, date: dutyDate, columnMap: columnMap);

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
      pagesProcessed: pageText.length,
      recordsDetected: duties.length,
      warnings: warnings,
    );
  }

  bool _isHeaderRow(ExtractedTableRow row, AmendmentColumnMap? columnMap) {
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

  Duty? _parseFallbackRow({
    required ExtractedTableRow row,
    required DateTime date,
  }) {
    final payrollNumber = _findFallbackPayrollNumber(row);

    if (!_isPlausiblePayrollNumber(payrollNumber)) {
      return null;
    }

    final times = ParserUtils.extractTimes(row.rawText);
    final bookOn = times.isNotEmpty ? times.first : null;
    final bookOff = times.length > 1 ? times[1] : null;

    final turnNumber = _findFallbackTurnNumber(row);
    final amendmentCode = _findFallbackAmendmentCode(row);

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

    final calculatedMinutes = bookOn != null && bookOff != null
        ? ParserUtils.calculateDutyMinutes(bookOn, bookOff)
        : 0;

    return Duty(
      date: date,
      source: rosterSource,
      dutyType: dutyType,
      turnNumber: turnNumber,
      bookOn: bookOn,
      bookOff: bookOff,
      rosteredMinutes: calculatedMinutes > 0 ? calculatedMinutes : null,
      payrollNumber: payrollNumber,
      amendmentCode: amendmentCode,
      pageNumber: row.pageNumber,
      rawText: row.rawText,
      remarks: codeDefinition?.preferredMeaning,
    );
  }

  DateTime? _extractPageDate(String pageText) {
    final dates = ParserUtils.extractDates(pageText);

    if (dates.isEmpty) {
      return null;
    }

    return dates.first;
  }

  String? _findFallbackPayrollNumber(ExtractedTableRow row) {
    for (final column in row.columns) {
      final payrollNumber = ParserUtils.normalisePayrollNumber(column);

      if (_isPlausiblePayrollNumber(payrollNumber)) {
        return payrollNumber;
      }
    }

    final matches = RegExp(r'\b\d{4,8}\b').allMatches(row.rawText);

    for (final match in matches) {
      final payrollNumber = ParserUtils.normalisePayrollNumber(match.group(0));

      if (_isPlausiblePayrollNumber(payrollNumber)) {
        return payrollNumber;
      }
    }

    return null;
  }

  String? _findFallbackTurnNumber(ExtractedTableRow row) {
    final labelledMatch = RegExp(
      r'\b(?:WO|W0|WQ|TURN|DUTY)\s*[-:]?\s*\d{2,4}\b',
      caseSensitive: false,
    ).firstMatch(row.rawText);

    if (labelledMatch != null) {
      return ParserUtils.normaliseTurnNumber(labelledMatch.group(0));
    }

    for (final column in row.columns) {
      final upper = column.toUpperCase();

      if (upper.contains('WO') ||
          upper.contains('W0') ||
          upper.contains('WQ') ||
          upper.contains('TURN') ||
          upper.contains('DUTY')) {
        final turnNumber = ParserUtils.normaliseTurnNumber(column);

        if (turnNumber != null) {
          return turnNumber;
        }
      }
    }

    return null;
  }

  String? _findFallbackAmendmentCode(ExtractedTableRow row) {
    for (final column in row.columns) {
      final candidate = _normaliseAmendmentCode(column);

      if (DutyCodeLibrary.contains(candidate)) {
        return candidate;
      }
    }

    for (final match in RegExp(
      r'\b[A-Z]{1,3}\d?\b',
    ).allMatches(row.rawText.toUpperCase())) {
      final candidate = _normaliseAmendmentCode(match.group(0));

      if (DutyCodeLibrary.contains(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  String? _normaliseAmendmentCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final code = DutyCodeLibrary.normaliseCode(value);

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
