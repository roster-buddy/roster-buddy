import 'parser_utils.dart';

class ExtractedTableRow {
  const ExtractedTableRow({
    required this.pageNumber,
    required this.lineNumber,
    required this.rawText,
    required this.columns,
    this.isLikelyHeader = false,
  });

  /// One-based page number.
  final int pageNumber;

  /// One-based line number within the OCR page.
  final int lineNumber;

  final String rawText;
  final List<String> columns;
  final bool isLikelyHeader;

  bool get isEmpty => columns.every((column) => column.trim().isEmpty);

  String? columnAt(int index) {
    if (index < 0 || index >= columns.length) {
      return null;
    }

    final value = columns[index].trim();
    return value.isEmpty ? null : value;
  }

  bool containsText(String value) {
    final target = value.trim().toUpperCase();

    return columns.any((column) => column.toUpperCase().contains(target));
  }
}

class ExtractedTable {
  const ExtractedTable({required this.rows, required this.pageCount});

  final List<ExtractedTableRow> rows;
  final int pageCount;

  List<ExtractedTableRow> get dataRows =>
      rows.where((row) => !row.isLikelyHeader && !row.isEmpty).toList();

  List<ExtractedTableRow> rowsForPage(int pageNumber) {
    return rows.where((row) => row.pageNumber == pageNumber).toList();
  }

  ExtractedTableRow? firstHeaderContaining(String value) {
    for (final row in rows) {
      if (row.isLikelyHeader && row.containsText(value)) {
        return row;
      }
    }

    return null;
  }
}

class TableExtractor {
  const TableExtractor();

  ExtractedTable extract(List<String> pageText) {
    final rows = <ExtractedTableRow>[];

    for (var pageIndex = 0; pageIndex < pageText.length; pageIndex++) {
      final rawLines = pageText[pageIndex].split(RegExp(r'\r?\n'));

      for (var lineIndex = 0; lineIndex < rawLines.length; lineIndex++) {
        final rawLine = rawLines[lineIndex];
        final cleanedLine = ParserUtils.normaliseWhitespace(rawLine);

        if (cleanedLine.isEmpty) {
          continue;
        }

        final columns = _splitColumns(rawLine);

        rows.add(
          ExtractedTableRow(
            pageNumber: pageIndex + 1,
            lineNumber: lineIndex + 1,
            rawText: cleanedLine,
            columns: columns,
            isLikelyHeader: _looksLikeHeader(columns),
          ),
        );
      }
    }

    return ExtractedTable(rows: rows, pageCount: pageText.length);
  }

  List<String> _splitColumns(String rawLine) {
    final trimmed = rawLine.trim();

    if (trimmed.isEmpty) {
      return const [];
    }

    List<String> columns;

    if (trimmed.contains('|')) {
      columns = trimmed.split('|');
    } else if (trimmed.contains('\t')) {
      columns = trimmed.split(RegExp(r'\t+'));
    } else {
      columns = trimmed.split(RegExp(r'\s{2,}'));
    }

    final cleaned = columns
        .map(ParserUtils.normaliseWhitespace)
        .where((column) => column.isNotEmpty)
        .toList();

    if (cleaned.length > 1) {
      return cleaned;
    }

    return [ParserUtils.normaliseWhitespace(trimmed)];
  }

  bool _looksLikeHeader(List<String> columns) {
    if (columns.isEmpty) {
      return false;
    }

    final text = columns.join(' ').toUpperCase();

    const headerTerms = <String>[
      'NAME',
      'PAY NO',
      'PAYROLL',
      'DEPOT',
      'AMEND',
      'TURN',
      'BOOK ON',
      'BOOK OFF',
      'ROSTERED HOURS',
      'MILEAGE',
      'REMARKS',
      'DRIVER NO',
      'DRIVER NUMBER',
      'WEEK',
      'SUNDAY',
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'ANNUAL LEAVE',
      'BLOCK',
    ];

    var matches = 0;

    for (final term in headerTerms) {
      if (text.contains(term)) {
        matches++;
      }
    }

    return matches >= 2;
  }
}
