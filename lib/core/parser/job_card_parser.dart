import '../models/document_type.dart';
import '../models/job_card.dart';
import '../models/parse_result.dart';
import '../models/parse_warning.dart';
import 'base_parser.dart';
import 'job_card_page_splitter.dart';
import 'parser_utils.dart';

class JobCardParser implements BaseParser {
  const JobCardParser({this.pageSplitter = const JobCardPageSplitter()});

  final JobCardPageSplitter pageSplitter;

  static final RegExp _turnCodePattern = RegExp(
    r'\bW[O0Q]\s*[-:]?\s*(\d{2,4})\b',
    caseSensitive: false,
  );

  static final RegExp _dayCodeLabelPattern = RegExp(
    r'\b(?:DAY(?:\s+CODE)?|DAYS?|APPLIES)\s*[:\-]?\s*'
    r'(SUN|SU|SO|SAO|SX|(?:M|T|W|TH|F|S)+(?:O|X)?)\b',
    caseSensitive: false,
  );

  static final RegExp _standaloneDayCodePattern = RegExp(
    r'\b(SUN|SU|SO|SAO|SX|(?:M|T|W|TH|F|S)+(?:O|X))\b',
    caseSensitive: false,
  );

  static final RegExp _validityRangePattern = RegExp(
    r'(?:VALID(?:ITY)?|FROM)\s*[:\-]?\s*'
    r'(\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4})'
    r'\s*(?:TO|UNTIL|\-|–)\s*'
    r'(\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4})',
    caseSensitive: false,
  );

  @override
  DocumentType get supportedType => DocumentType.jobCard;

  @override
  bool canParse(List<String> pageText) {
    if (pageText.isEmpty) {
      return false;
    }

    final String combined = pageText.join('\n').toUpperCase();

    return combined.contains('JOB CARD') ||
        _turnCodePattern.hasMatch(combined) ||
        (combined.contains('BOOK ON') &&
            combined.contains('BOOK OFF') &&
            combined.contains('VALID'));
  }

  @override
  Future<ParseResult> parse({required List<String> pageText}) async {
    final List<JobCard> cards = <JobCard>[];
    final List<ParseWarning> warnings = <ParseWarning>[];
    final Set<String> seenKeys = <String>{};

    for (int pageIndex = 0; pageIndex < pageText.length; pageIndex++) {
      final int pageNumber = pageIndex + 1;
      final String page = pageText[pageIndex].trim();

      if (page.isEmpty) {
        continue;
      }

      final List<String> sections = pageSplitter.split(page);

      for (final String section in sections) {
        final JobCard? card = _parseCard(section, pageNumber: pageNumber);

        if (card == null) {
          continue;
        }

        if (seenKeys.add(card.uniqueKey)) {
          cards.add(card);
        }
      }

      if (sections.isNotEmpty &&
          !cards.any((JobCard card) => card.pageNumber == pageNumber)) {
        warnings.add(
          ParseWarning(
            message:
                'No complete Job Card could be extracted from page $pageNumber.',
            pageNumber: pageNumber,
            severity: ParseWarningSeverity.information,
          ),
        );
      }
    }

    if (cards.isEmpty) {
      warnings.add(
        const ParseWarning(
          message:
              'No complete Job Cards containing a turn number, day code, '
              'validity dates and book-on/book-off times were detected.',
          severity: ParseWarningSeverity.blocking,
        ),
      );
    }

    return ParseResult(
      documentType: DocumentType.jobCard,
      jobCards: cards,
      pagesProcessed: pageText.length,
      recordsDetected: cards.length,
      warnings: warnings,
    );
  }

  JobCard? _parseCard(String text, {required int pageNumber}) {
    final RegExpMatch? turnMatch = _turnCodePattern.firstMatch(text);

    if (turnMatch == null) {
      return null;
    }

    final String? turnNumber = ParserUtils.normaliseTurnNumber(
      turnMatch.group(0),
    );

    if (turnNumber == null || turnNumber.isEmpty) {
      return null;
    }

    final String originalTurnCode = 'WO$turnNumber';
    final String? dayCode = _extractDayCode(text);
    final List<DateTime> validityDates = _extractValidityDates(text);
    final List<String> times = _extractBookOnAndOff(text);

    if (dayCode == null || validityDates.length < 2 || times.length < 2) {
      return null;
    }

    final DateTime validFrom = validityDates.first;
    final DateTime validTo = validityDates[1];

    if (validTo.isBefore(validFrom)) {
      return null;
    }

    final String bookOn = times.first;
    final String bookOff = times[1];

    final int rosteredMinutes =
        _extractRosteredMinutes(text) ??
        ParserUtils.calculateDutyMinutes(bookOn, bookOff);

    return JobCard(
      turnNumber: turnNumber,
      originalTurnCode: originalTurnCode,
      dayCode: dayCode,
      planType: _extractPlanType(text),
      validFrom: validFrom,
      validTo: validTo,
      bookOn: bookOn,
      bookOff: bookOff,
      rosteredMinutes: rosteredMinutes,
      rawText: text,
      instructions: _extractInstructions(text),
      pageNumber: pageNumber,
    );
  }

  String? _extractDayCode(String text) {
    final RegExpMatch? labelled = _dayCodeLabelPattern.firstMatch(text);

    if (labelled != null) {
      return _normaliseDayCode(labelled.group(1));
    }

    final RegExpMatch? standalone = _standaloneDayCodePattern.firstMatch(text);

    if (standalone != null) {
      return _normaliseDayCode(standalone.group(1));
    }

    return null;
  }

  List<DateTime> _extractValidityDates(String text) {
    final RegExpMatch? range = _validityRangePattern.firstMatch(text);

    if (range != null) {
      final DateTime? first = ParserUtils.parseDate(range.group(1));
      final DateTime? second = ParserUtils.parseDate(range.group(2));

      if (first != null && second != null) {
        return <DateTime>[first, second];
      }
    }

    final List<DateTime> dates = ParserUtils.extractDates(text);

    if (dates.length >= 2) {
      return dates.take(2).toList(growable: false);
    }

    return const <DateTime>[];
  }

  List<String> _extractBookOnAndOff(String text) {
    final RegExp bookOnPattern = RegExp(
      r'BOOK\s*ON\s*[:\-]?\s*([0-2]?\d[:.]?[0-5]\d)',
      caseSensitive: false,
    );

    final RegExp bookOffPattern = RegExp(
      r'BOOK\s*OFF\s*[:\-]?\s*([0-2]?\d[:.]?[0-5]\d)',
      caseSensitive: false,
    );

    final String? labelledBookOn = ParserUtils.normaliseTime(
      bookOnPattern.firstMatch(text)?.group(1),
    );

    final String? labelledBookOff = ParserUtils.normaliseTime(
      bookOffPattern.firstMatch(text)?.group(1),
    );

    if (labelledBookOn != null && labelledBookOff != null) {
      return <String>[labelledBookOn, labelledBookOff];
    }

    final List<String> extracted = ParserUtils.extractTimes(text);

    if (extracted.length >= 2) {
      return extracted.take(2).toList(growable: false);
    }

    return const <String>[];
  }

  int? _extractRosteredMinutes(String text) {
    final RegExp pattern = RegExp(
      r'(?:ROSTERED\s*(?:HOURS?|TIME)|DUTY\s*LENGTH)'
      r'\s*[:\-]?\s*(\d{1,2}[:.]\d{2})',
      caseSensitive: false,
    );

    return ParserUtils.parseRosteredMinutes(pattern.firstMatch(text)?.group(1));
  }

  JobCardPlanType _extractPlanType(String text) {
    final String upper = text.toUpperCase();

    if (upper.contains('VSTP')) {
      return JobCardPlanType.vstp;
    }

    if (upper.contains('STP')) {
      return JobCardPlanType.stp;
    }

    if (upper.contains('LTP')) {
      return JobCardPlanType.ltp;
    }

    return JobCardPlanType.unknown;
  }

  List<String> _extractInstructions(String text) {
    final List<String> lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);

    return lines
        .where((String line) {
          final String upper = line.toUpperCase();

          return !_turnCodePattern.hasMatch(line) &&
              !upper.startsWith('BOOK ON') &&
              !upper.startsWith('BOOK OFF') &&
              !upper.startsWith('VALID') &&
              !upper.startsWith('DAY CODE') &&
              upper != 'JOB CARD' &&
              upper != 'LTP' &&
              upper != 'STP' &&
              upper != 'VSTP';
        })
        .toList(growable: false);
  }

  String? _normaliseDayCode(String? value) {
    final String cleaned =
        value?.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase() ?? '';

    if (cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }
}
