import '../models/annual_leave_allocation.dart';
import '../models/document_type.dart';
import '../models/parse_result.dart';
import '../models/parse_warning.dart';
import 'base_parser.dart';
import 'parser_utils.dart';
import 'table_extractor.dart';

class AnnualLeaveRosterParser implements BaseParser {
  const AnnualLeaveRosterParser({
    this.tableExtractor = const TableExtractor(),
    this.defaultDepot,
    this.defaultLeaveYear,
  });

  final TableExtractor tableExtractor;
  final String? defaultDepot;
  final int? defaultLeaveYear;

  @override
  DocumentType get supportedType => DocumentType.annualLeaveRoster;

  @override
  bool canParse(List<String> pageText) {
    final String text = pageText.join('\n').toUpperCase();

    final bool hasAnnualLeave =
        text.contains('ANNUAL LEAVE') ||
        text.contains('ANNUAL HOLIDAY') ||
        text.contains('LEAVE ROSTER');

    final bool hasBlocks =
        text.contains('BLOCK') &&
        RegExp(r'\b(?:SPRING|SUMMER|WINTER)\b').hasMatch(text);

    return hasAnnualLeave || hasBlocks;
  }

  @override
  Future<ParseResult> parse({required List<String> pageText}) async {
    final List<ParseWarning> warnings = <ParseWarning>[];

    if (pageText.isEmpty ||
        pageText.every((String page) => page.trim().isEmpty)) {
      return ParseResult(
        documentType: DocumentType.annualLeaveRoster,
        pagesProcessed: pageText.length,
        warnings: const <ParseWarning>[
          ParseWarning(
            message: 'The Annual Leave Roster contains no readable text.',
            severity: ParseWarningSeverity.blocking,
          ),
        ],
      );
    }

    final ExtractedTable table = tableExtractor.extract(pageText);
    final int? leaveYear = _detectLeaveYear(pageText);
    final String depot = _detectDepot(pageText);

    if (leaveYear == null) {
      warnings.add(
        const ParseWarning(
          message:
              'The annual-leave year could not be identified from the roster.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    final List<_AnnualLeaveBlock> blocks = _extractBlocks(table);

    if (blocks.isEmpty) {
      warnings.add(
        const ParseWarning(
          message:
              'No annual-leave block columns and seasonal date bands were detected.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    if (warnings.any((ParseWarning warning) => warning.preventsImport)) {
      return ParseResult(
        documentType: DocumentType.annualLeaveRoster,
        pagesProcessed: pageText.length,
        warnings: warnings,
      );
    }

    final List<AnnualLeaveAllocation> allocations = _extractAllocations(
      table: table,
      blocks: blocks,
      leaveYear: leaveYear!,
      depot: depot,
    );

    if (allocations.isEmpty) {
      warnings.add(
        const ParseWarning(
          message:
              'No driver allocations were detected beneath the annual-leave block columns.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    return ParseResult(
      documentType: DocumentType.annualLeaveRoster,
      annualLeaveAllocations: allocations,
      pagesProcessed: pageText.length,
      recordsDetected: allocations.length,
      warnings: warnings,
    );
  }

  int? _detectLeaveYear(List<String> pages) {
    if (defaultLeaveYear != null) {
      return defaultLeaveYear;
    }

    final String text = pages.join('\n');

    final Match? labelledYear = RegExp(
      r'\b(?:LEAVE\s+YEAR|ANNUAL\s+LEAVE)\s*[:\-]?\s*(20\d{2})\b',
      caseSensitive: false,
    ).firstMatch(text);

    final int? labelledValue = int.tryParse(labelledYear?.group(1) ?? '');

    if (labelledValue != null) {
      return labelledValue;
    }

    final Iterable<Match> years = RegExp(r'\b20\d{2}\b').allMatches(text);

    for (final Match match in years) {
      final int? year = int.tryParse(match.group(0) ?? '');

      if (year != null && year >= 2020 && year <= 2200) {
        return year;
      }
    }

    return null;
  }

  String _detectDepot(List<String> pages) {
    final String configuredDepot = defaultDepot?.trim() ?? '';

    if (configuredDepot.isNotEmpty) {
      return configuredDepot;
    }

    final String text = pages.join('\n');

    final Match? labelledDepot = RegExp(
      r'\bDEPOT\s*[:\-]\s*([A-Z][A-Z0-9 \-]{1,40})',
      caseSensitive: false,
    ).firstMatch(text);

    final String detected = ParserUtils.normaliseWhitespace(
      labelledDepot?.group(1) ?? '',
    );

    return detected.isEmpty ? 'Unknown' : detected;
  }

  List<_AnnualLeaveBlock> _extractBlocks(ExtractedTable table) {
    final List<_AnnualLeaveBlock> blocks = <_AnnualLeaveBlock>[];

    for (final int pageNumber in List<int>.generate(
      table.pageCount,
      (int index) => index + 1,
    )) {
      final List<ExtractedTableRow> rows = table.rowsForPage(pageNumber);
      final int headerIndex = rows.indexWhere(_isBlockHeader);

      if (headerIndex < 0) {
        continue;
      }

      final ExtractedTableRow header = rows[headerIndex];
      final List<int?> blockNumbers = header.columns
          .skip(1)
          .map(_parseBlockNumber)
          .toList(growable: false);

      if (blockNumbers.whereType<int>().isEmpty) {
        continue;
      }

      final Map<int, Map<AnnualLeavePeriodType, AnnualLeavePeriod>> periods =
          <int, Map<AnnualLeavePeriodType, AnnualLeavePeriod>>{};

      for (int rowIndex = headerIndex + 1; rowIndex < rows.length; rowIndex++) {
        final ExtractedTableRow row = rows[rowIndex];
        final AnnualLeavePeriodType? periodType = _periodType(row.columnAt(0));

        if (periodType == null) {
          continue;
        }

        for (
          int columnIndex = 1;
          columnIndex < row.columns.length &&
              columnIndex <= blockNumbers.length;
          columnIndex++
        ) {
          final int? blockNumber = blockNumbers[columnIndex - 1];

          if (blockNumber == null) {
            continue;
          }

          final _DateRange? range = _parseDateRange(row.columnAt(columnIndex));

          if (range == null) {
            continue;
          }

          periods.putIfAbsent(
            blockNumber,
            () => <AnnualLeavePeriodType, AnnualLeavePeriod>{},
          )[periodType] = AnnualLeavePeriod(
            type: periodType,
            startDate: range.startDate,
            endDate: range.endDate,
          );
        }
      }

      for (int index = 0; index < blockNumbers.length; index++) {
        final int? blockNumber = blockNumbers[index];

        if (blockNumber == null) {
          continue;
        }

        final List<AnnualLeavePeriod> blockPeriods =
            periods[blockNumber]?.values.toList(growable: false) ??
            const <AnnualLeavePeriod>[];

        if (blockPeriods.isEmpty) {
          continue;
        }

        blocks.add(
          _AnnualLeaveBlock(
            blockNumber: blockNumber,
            pageNumber: pageNumber,
            columnIndex: index + 1,
            periods: blockPeriods,
          ),
        );
      }
    }

    return blocks;
  }

  List<AnnualLeaveAllocation> _extractAllocations({
    required ExtractedTable table,
    required List<_AnnualLeaveBlock> blocks,
    required int leaveYear,
    required String depot,
  }) {
    final List<AnnualLeaveAllocation> allocations = <AnnualLeaveAllocation>[];
    final Set<String> seenKeys = <String>{};

    for (final _AnnualLeaveBlock block in blocks) {
      final List<ExtractedTableRow> pageRows = table.rowsForPage(
        block.pageNumber,
      );

      final int headerIndex = pageRows.indexWhere(_isBlockHeader);

      if (headerIndex < 0) {
        continue;
      }

      for (
        int rowIndex = headerIndex + 1;
        rowIndex < pageRows.length;
        rowIndex++
      ) {
        final ExtractedTableRow row = pageRows[rowIndex];

        if (_periodType(row.columnAt(0)) != null) {
          continue;
        }

        final String? cell = row.columnAt(block.columnIndex);
        final _DriverIdentity? identity = _parseDriverIdentity(cell);

        if (identity == null) {
          continue;
        }

        final AnnualLeaveAllocation allocation = AnnualLeaveAllocation(
          leaveYear: leaveYear,
          depot: depot,
          driverNumber: identity.driverNumber,
          surname: identity.surname,
          blockNumber: block.blockNumber,
          periods: block.periods,
          pageNumber: block.pageNumber,
        );

        if (seenKeys.add(allocation.uniqueKey)) {
          allocations.add(allocation);
        }
      }
    }

    allocations.sort((
      AnnualLeaveAllocation first,
      AnnualLeaveAllocation second,
    ) {
      final int blockComparison = first.blockNumber.compareTo(
        second.blockNumber,
      );

      if (blockComparison != 0) {
        return blockComparison;
      }

      return first.driverNumber.compareTo(second.driverNumber);
    });

    return allocations;
  }

  bool _isBlockHeader(ExtractedTableRow row) {
    if (row.columns.length < 2) {
      return false;
    }

    final String first = row.columns.first.trim().toUpperCase();

    if (!first.contains('BLOCK')) {
      return false;
    }

    return row.columns
        .skip(1)
        .map(_parseBlockNumber)
        .whereType<int>()
        .isNotEmpty;
  }

  int? _parseBlockNumber(String? value) {
    if (value == null) {
      return null;
    }

    final Match? match = RegExp(
      r'\b(?:BLOCK\s*)?(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(value);

    final int? blockNumber = int.tryParse(match?.group(1) ?? '');

    if (blockNumber == null || blockNumber < 1 || blockNumber > 99) {
      return null;
    }

    return blockNumber;
  }

  AnnualLeavePeriodType? _periodType(String? value) {
    if (value == null) {
      return null;
    }

    final String text = value.trim().toUpperCase();

    if (text.contains('SPRING')) {
      return AnnualLeavePeriodType.spring;
    }

    if (text.contains('SUMMER')) {
      final bool secondWeek =
          text.contains('SECOND') ||
          text.contains('2ND') ||
          RegExp(r'\bSUMMER\s*2\b').hasMatch(text);

      return secondWeek
          ? AnnualLeavePeriodType.summerSecondWeek
          : AnnualLeavePeriodType.summerFirstWeek;
    }

    if (text.contains('WINTER')) {
      return AnnualLeavePeriodType.winter;
    }

    return null;
  }

  _DateRange? _parseDateRange(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final List<DateTime> dates = ParserUtils.extractDates(value);

    if (dates.length >= 2) {
      return _DateRange(startDate: dates[0], endDate: dates[1]);
    }

    final Match? compactRange = RegExp(
      r'\b(\d{1,2})[\/\-.](\d{1,2})'
      r'\s*(?:TO|UNTIL|THRU|THROUGH|\-|–|—)\s*'
      r'(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b',
      caseSensitive: false,
    ).firstMatch(value);

    if (compactRange == null) {
      return null;
    }

    final int? startDay = int.tryParse(compactRange.group(1) ?? '');
    final int? startMonth = int.tryParse(compactRange.group(2) ?? '');
    final int? endDay = int.tryParse(compactRange.group(3) ?? '');
    final int? endMonth = int.tryParse(compactRange.group(4) ?? '');
    int? year = int.tryParse(compactRange.group(5) ?? '');

    if (startDay == null ||
        startMonth == null ||
        endDay == null ||
        endMonth == null ||
        year == null) {
      return null;
    }

    if (year < 100) {
      year += year >= 70 ? 1900 : 2000;
    }

    final DateTime? startDate = ParserUtils.safeDate(
      year,
      startMonth,
      startDay,
    );

    final DateTime? endDate = ParserUtils.safeDate(year, endMonth, endDay);

    if (startDate == null || endDate == null || endDate.isBefore(startDate)) {
      return null;
    }

    return _DateRange(startDate: startDate, endDate: endDate);
  }

  _DriverIdentity? _parseDriverIdentity(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final String cleaned = ParserUtils.normaliseWhitespace(value);

    final Match? match = RegExp(
      r'^\s*(\d{2,8})\s+([A-Z][A-Z\-\x27 ]{1,60})\s*$',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (match == null) {
      return null;
    }

    final String driverNumber =
        ParserUtils.normaliseDriverNumber(match.group(1)) ?? '';

    final String surname = ParserUtils.normaliseWhitespace(
      match.group(2) ?? '',
    );

    if (driverNumber.isEmpty || surname.isEmpty) {
      return null;
    }

    return _DriverIdentity(
      driverNumber: driverNumber,
      surname: surname.toUpperCase(),
    );
  }
}

class _AnnualLeaveBlock {
  const _AnnualLeaveBlock({
    required this.blockNumber,
    required this.pageNumber,
    required this.columnIndex,
    required this.periods,
  });

  final int blockNumber;
  final int pageNumber;
  final int columnIndex;
  final List<AnnualLeavePeriod> periods;
}

class _DriverIdentity {
  const _DriverIdentity({required this.driverNumber, required this.surname});

  final String driverNumber;
  final String surname;
}

class _DateRange {
  const _DateRange({required this.startDate, required this.endDate});

  final DateTime startDate;
  final DateTime endDate;
}
