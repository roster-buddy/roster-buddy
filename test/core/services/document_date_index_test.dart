import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/parse_result.dart';
import 'package:roster_buddy/core/services/document_date_index.dart';

void main() {
  test('dated sheet is indexed even without a personal shift and survives review copies', () {
    final dates = DocumentDateIndex.fromText([
      'Report for Thursday 05/11/26 in All Links',
      'Report for Thursday 05/11/2026 in All Links',
      'Report for 31/02/2026',
    ]);
    final result = ParseResult(documentType: DocumentType.sevenDayAmendment, identifiedDates: dates);
    expect(DocumentDateIndex.forResult(result.copyWith(ownRecordCount: 0)), ['2026-11-05']);
  });
  test('unknown dates are not guessed', () {
    expect(DocumentDateIndex.fromText(['7 DAY SHEET']), isEmpty);
    expect(DocumentDateIndex.forResult(null), isEmpty);
  });
}
