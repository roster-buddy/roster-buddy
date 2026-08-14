import '../models/document_type.dart';
import '../models/duty.dart';
import '../models/duty_type.dart';
import '../models/parse_result.dart';
import '../models/parse_warning.dart';
import '../models/roster_source.dart';
import 'base_parser.dart';
import 'parser_utils.dart';
import 'table_extractor.dart';

enum BaseRosterInitialLine { driver, swapPartner }

class BaseRosterParser implements BaseParser {
  const BaseRosterParser({
    this.commencementDate,
    this.rosterNumber,
    this.swapPartnerRosterNumber,
    this.initialLine = BaseRosterInitialLine.driver,
    this.tableExtractor = const TableExtractor(),
  });

  /// The Sunday on which this Base Roster becomes active.
  final DateTime? commencementDate;

  /// The signed-in user's Base Roster number.
  final String? rosterNumber;

  /// Optional permanent mutual-swap partner roster number.
  final String? swapPartnerRosterNumber;

  /// Determines which line supplies the first active calendar week.
  final BaseRosterInitialLine initialLine;

  final TableExtractor tableExtractor;

  @override
  DocumentType get supportedType => DocumentType.baseRoster;

  @override
  bool canParse(List<String> pageText) {
    final String text = pageText.join('\n').toUpperCase();

    final bool hasWeekHeading =
        text.contains('WEEK') ||
        RegExp(
          r'^(?:[1-9]|[1-4][0-9]|5[0-4])(?:\\s|$)',
          multiLine: true,
        ).hasMatch(text);

    final int dayHeadingMatches = <String>[
      'SUN',
      'MON',
      'TUE',
      'WED',
      'THU',
      'FRI',
    ].where(text.contains).length;

    return hasWeekHeading && dayHeadingMatches >= 3;
  }

  @override
  Future<ParseResult> parse({required List<String> pageText}) async {
    final List<ParseWarning> warnings = <ParseWarning>[];

    if (pageText.isEmpty ||
        pageText.every((String page) => page.trim().isEmpty)) {
      return ParseResult(
        documentType: DocumentType.baseRoster,
        pagesProcessed: pageText.length,
        warnings: const <ParseWarning>[
          ParseWarning(
            message: 'The Base Roster contains no readable text.',
            severity: ParseWarningSeverity.blocking,
          ),
        ],
      );
    }

    final DateTime? activeFrom = commencementDate == null
        ? null
        : DateTime(
            commencementDate!.year,
            commencementDate!.month,
            commencementDate!.day,
          );

    if (activeFrom == null) {
      warnings.add(
        const ParseWarning(
          message:
              'The Base Roster commencement Sunday is required before duties can be generated.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    } else if (activeFrom.weekday != DateTime.sunday) {
      warnings.add(
        const ParseWarning(
          message: 'The Base Roster commencement date must be a Sunday.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    final String requestedRosterNumber =
        ParserUtils.normaliseDriverNumber(rosterNumber) ?? '';

    if (requestedRosterNumber.isEmpty) {
      warnings.add(
        const ParseWarning(
          message:
              'A roster number is required to locate the correct Base Roster line.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    final ExtractedTable table = tableExtractor.extract(pageText);
    final List<_BaseRosterWeek> weeks = _extractWeeks(table);

    if (weeks.isEmpty) {
      warnings.add(
        const ParseWarning(
          message:
              'No Base Roster week rows were detected. Check that the full roster grid is visible.',
          severity: ParseWarningSeverity.blocking,
        ),
      );

      return ParseResult(
        documentType: DocumentType.baseRoster,
        pagesProcessed: pageText.length,
        weeksDetected: 0,
        warnings: warnings,
      );
    }

    final int rosterStartIndex = weeks.indexWhere(
      (_BaseRosterWeek week) => week.driverNumber == requestedRosterNumber,
    );

    if (requestedRosterNumber.isNotEmpty && rosterStartIndex < 0) {
      warnings.add(
        ParseWarning(
          message:
              'Roster number $requestedRosterNumber was not found on the Base Roster.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    final String swapRosterNumber =
        ParserUtils.normaliseDriverNumber(swapPartnerRosterNumber) ?? '';

    final int swapStartIndex = swapRosterNumber.isEmpty
        ? -1
        : weeks.indexWhere(
            (_BaseRosterWeek week) => week.driverNumber == swapRosterNumber,
          );

    if (swapRosterNumber.isNotEmpty && swapStartIndex < 0) {
      warnings.add(
        ParseWarning(
          message:
              'Mutual-swap partner roster number $swapRosterNumber was not found on the Base Roster.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    if (warnings.any((ParseWarning warning) => warning.preventsImport)) {
      return ParseResult(
        documentType: DocumentType.baseRoster,
        driverFound: rosterStartIndex >= 0,
        driverNumber: requestedRosterNumber.isEmpty
            ? null
            : requestedRosterNumber,
        pagesProcessed: pageText.length,
        weeksDetected: weeks.length,
        warnings: warnings,
      );
    }

    final List<Duty> duties = <Duty>[];
    final Set<String> seenKeys = <String>{};

    for (int calendarWeek = 0; calendarWeek < weeks.length; calendarWeek++) {
      final int selectedIndex = _selectedRosterIndex(
        calendarWeek: calendarWeek,
        rosterLength: weeks.length,
        driverStartIndex: rosterStartIndex,
        swapStartIndex: swapStartIndex,
      );

      final _BaseRosterWeek selectedWeek = weeks[selectedIndex];
      final DateTime weekSunday = activeFrom!.add(
        Duration(days: calendarWeek * 7),
      );

      for (
        int dayIndex = 0;
        dayIndex < selectedWeek.dayCells.length;
        dayIndex++
      ) {
        final _BaseRosterDayCell cell = selectedWeek.dayCells[dayIndex];
        final Duty? duty = _buildDuty(
          date: weekSunday.add(Duration(days: dayIndex)),
          driverNumber: requestedRosterNumber,
          pageNumber: selectedWeek.pageNumber,
          cell: cell,
        );

        if (duty != null && seenKeys.add(duty.uniqueKey)) {
          duties.add(duty);
        }
      }
    }

    if (duties.isEmpty) {
      warnings.add(
        const ParseWarning(
          message:
              'The correct Base Roster line was found, but no usable Sunday-to-Friday duties were detected.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    return ParseResult(
      documentType: DocumentType.baseRoster,
      duties: duties,
      driverFound: rosterStartIndex >= 0,
      driverNumber: requestedRosterNumber,
      pagesProcessed: pageText.length,
      weeksDetected: weeks.length,
      recordsDetected: duties.length,
      warnings: warnings,
    );
  }

  int _selectedRosterIndex({
    required int calendarWeek,
    required int rosterLength,
    required int driverStartIndex,
    required int swapStartIndex,
  }) {
    if (swapStartIndex < 0) {
      return (driverStartIndex + calendarWeek) % rosterLength;
    }

    final bool firstUsesPartner =
        initialLine == BaseRosterInitialLine.swapPartner;

    final bool usePartner = calendarWeek.isEven
        ? firstUsesPartner
        : !firstUsesPartner;

    final int startingIndex = usePartner ? swapStartIndex : driverStartIndex;

    return (startingIndex + calendarWeek) % rosterLength;
  }

  List<_BaseRosterWeek> _extractWeeks(ExtractedTable table) {
    final List<ExtractedTableRow> rows = table.rows
        .where((ExtractedTableRow row) => !row.isLikelyHeader && !row.isEmpty)
        .toList(growable: false);

    final List<_BaseRosterWeek> weeks = <_BaseRosterWeek>[];

    for (int index = 0; index < rows.length; index++) {
      final ExtractedTableRow dutyRow = rows[index];
      final int? weekNumber = _weekNumber(dutyRow);

      if (weekNumber == null) {
        continue;
      }

      ExtractedTableRow? identityRow;

      for (
        int candidateIndex = index + 1;
        candidateIndex < rows.length;
        candidateIndex++
      ) {
        final ExtractedTableRow candidate = rows[candidateIndex];

        if (_weekNumber(candidate) != null) {
          break;
        }

        if (candidate.pageNumber != dutyRow.pageNumber &&
            candidateIndex > index + 1) {
          break;
        }

        if (_driverNumberFromIdentityRow(candidate) != null) {
          identityRow = candidate;
          break;
        }
      }

      if (identityRow == null) {
        continue;
      }

      final String? detectedDriver = _driverNumberFromIdentityRow(identityRow);

      if (detectedDriver == null) {
        continue;
      }

      final List<_BaseRosterDayCell> cells = _extractDayCells(dutyRow);

      if (cells.length != 6) {
        continue;
      }

      weeks.add(
        _BaseRosterWeek(
          printedWeekNumber: weekNumber,
          driverNumber: detectedDriver,
          pageNumber: dutyRow.pageNumber,
          dayCells: cells,
        ),
      );
    }

    return weeks;
  }

  int? _weekNumber(ExtractedTableRow row) {
    final String? firstColumn = row.columnAt(0);

    if (firstColumn != null) {
      final Match? match = RegExp(
        r'^(?:WEEK\s*)?(\d{1,2})$',
        caseSensitive: false,
      ).firstMatch(firstColumn.trim());

      final int? value = int.tryParse(match?.group(1) ?? '');

      if (value != null && value >= 1 && value <= 54) {
        return value;
      }
    }

    final Match? rawMatch = RegExp(
      r'^(?:WEEK\s*)?(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(row.rawText.trim());

    final int? value = int.tryParse(rawMatch?.group(1) ?? '');

    if (value != null && value >= 1 && value <= 54) {
      return value;
    }

    return null;
  }

  String? _driverNumberFromIdentityRow(ExtractedTableRow row) {
    final String? firstColumn = row.columnAt(0);

    if (firstColumn != null) {
      final String? value = ParserUtils.normaliseDriverNumber(firstColumn);

      if (_isPlausibleDriverNumber(value)) {
        return value;
      }
    }

    final Match? labelled = RegExp(
      r'\b(?:DRIVER|DRV)\s*(?:NO|NUMBER)?\s*[:\-]?\s*(\d{2,8})\b',
      caseSensitive: false,
    ).firstMatch(row.rawText);

    final String? labelledValue = ParserUtils.normaliseDriverNumber(
      labelled?.group(1),
    );

    if (_isPlausibleDriverNumber(labelledValue)) {
      return labelledValue;
    }

    return null;
  }

  bool _isPlausibleDriverNumber(String? value) {
    if (value == null) {
      return false;
    }

    return value.length >= 2 && value.length <= 8;
  }

  List<_BaseRosterDayCell> _extractDayCells(ExtractedTableRow row) {
    final List<String> pipeColumns = row.rawText.contains('|')
        ? row.rawText
              .split('|')
              .map((String value) => value.trim())
              .toList(growable: false)
        : const <String>[];

    if (pipeColumns.length >= 25) {
      final List<String> dutyColumns = pipeColumns.sublist(1);
      final List<_BaseRosterDayCell> cells = <_BaseRosterDayCell>[];

      for (int day = 0; day < 6; day++) {
        final int start = day * 4;

        cells.add(
          _BaseRosterDayCell.fromFourColumns(
            dutyColumns.sublist(start, start + 4),
          ),
        );
      }

      return cells;
    }

    final List<String> columns = List<String>.from(row.columns);

    if (columns.isNotEmpty && _weekNumber(row) != null) {
      columns.removeAt(0);
    }

    if (columns.length >= 24) {
      final List<_BaseRosterDayCell> cells = <_BaseRosterDayCell>[];

      for (int day = 0; day < 6; day++) {
        final int start = day * 4;

        cells.add(
          _BaseRosterDayCell.fromFourColumns(columns.sublist(start, start + 4)),
        );
      }

      return cells;
    }

    if (columns.length == 6) {
      return columns
          .map(_BaseRosterDayCell.fromCombinedText)
          .toList(growable: false);
    }

    return const <_BaseRosterDayCell>[];
  }

  Duty? _buildDuty({
    required DateTime date,
    required String driverNumber,
    required int pageNumber,
    required _BaseRosterDayCell cell,
  }) {
    final String upper = cell.rawText.toUpperCase();

    final bool explicitlyRest = RegExp(
      r'\b(?:RD|REST|REST DAY|OFF)\b',
    ).hasMatch(upper);

    final bool hasDutyInformation =
        cell.bookOn != null ||
        cell.bookOff != null ||
        cell.turnNumber != null ||
        explicitlyRest;

    if (!hasDutyInformation) {
      return null;
    }

    final DutyType dutyType =
        explicitlyRest && cell.bookOn == null && cell.bookOff == null
        ? DutyType.restDay
        : DutyType.working;

    final int calculatedMinutes = cell.bookOn != null && cell.bookOff != null
        ? ParserUtils.calculateDutyMinutes(cell.bookOn, cell.bookOff)
        : 0;

    return Duty(
      date: date,
      source: RosterSource.baseRoster,
      dutyType: dutyType,
      turnNumber: cell.turnNumber,
      bookOn: cell.bookOn,
      bookOff: cell.bookOff,
      rosteredMinutes:
          cell.rosteredMinutes ??
          (calculatedMinutes > 0 ? calculatedMinutes : null),
      driverNumber: driverNumber,
      pageNumber: pageNumber,
      rawText: cell.rawText,
    );
  }
}

class _BaseRosterWeek {
  const _BaseRosterWeek({
    required this.printedWeekNumber,
    required this.driverNumber,
    required this.pageNumber,
    required this.dayCells,
  });

  final int printedWeekNumber;
  final String driverNumber;
  final int pageNumber;
  final List<_BaseRosterDayCell> dayCells;
}

class _BaseRosterDayCell {
  const _BaseRosterDayCell({
    required this.rawText,
    this.bookOn,
    this.bookOff,
    this.rosteredMinutes,
    this.turnNumber,
  });

  factory _BaseRosterDayCell.fromFourColumns(List<String> columns) {
    final String bookOnColumn = columns.isNotEmpty ? columns[0] : '';
    final String bookOffColumn = columns.length > 1 ? columns[1] : '';
    final String hoursColumn = columns.length > 2 ? columns[2] : '';
    final String turnColumn = columns.length > 3 ? columns[3] : '';

    return _BaseRosterDayCell(
      rawText: columns.join(' ').trim(),
      bookOn: ParserUtils.normaliseTime(bookOnColumn),
      bookOff: ParserUtils.normaliseTime(bookOffColumn),
      rosteredMinutes: ParserUtils.parseRosteredMinutes(hoursColumn),
      turnNumber: ParserUtils.normaliseTurnNumber(turnColumn),
    );
  }

  factory _BaseRosterDayCell.fromCombinedText(String value) {
    final List<String> times = ParserUtils.extractTimes(value);
    final String? bookOn = times.isNotEmpty ? times[0] : null;
    final String? bookOff = times.length > 1 ? times[1] : null;

    String? turnNumber;

    final Match? labelledTurn = RegExp(
      r'\b(?:WO|W0|WQ|TURN|DUTY)\s*[-:]?\s*(\d{2,4})\b',
      caseSensitive: false,
    ).firstMatch(value);

    if (labelledTurn != null) {
      turnNumber = ParserUtils.normaliseTurnNumber(labelledTurn.group(0));
    } else {
      final List<String> tokens = value
          .split(RegExp(r'\s+'))
          .where((String token) => token.isNotEmpty)
          .toList(growable: false);

      if (tokens.length >= 4) {
        turnNumber = ParserUtils.normaliseTurnNumber(tokens.last);
      }
    }

    return _BaseRosterDayCell(
      rawText: value.trim(),
      bookOn: bookOn,
      bookOff: bookOff,
      turnNumber: turnNumber,
    );
  }

  final String rawText;
  final String? bookOn;
  final String? bookOff;
  final int? rosteredMinutes;
  final String? turnNumber;
}
