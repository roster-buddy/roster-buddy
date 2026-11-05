import '../../core/models/document_type.dart';
import '../../core/models/parse_result.dart';

class ScanUploadSummary {
  ScanUploadSummary._();

  static String title(ParseResult? result, String fallback) {
    if (result == null) return fallback;
    final type = switch (result.documentType) {
      DocumentType.tenDayAmendment => '10 Day Sheet',
      DocumentType.sevenDayAmendment => '7 Day Sheet',
      DocumentType.fortyEightHourAmendment => '48 Hour Sheet',
      _ => fallback,
    };
    final dates = result.identifiedDates.toSet().toList()..sort();
    if (dates.isEmpty) return type;
    String date(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';
    return '${date(dates.first)}${dates.length > 1 ? '–${date(dates.last)}' : ''} $type';
  }

  static String message(ParseResult? result, int inserted, String fallback) {
    if (result?.allRowsRead == true &&
        inserted == result!.calculatedRecordCount) {
      return 'All $inserted rows read and applied';
    }
    return fallback;
  }
}
