import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/parser/daily_amendment_parser.dart';

void main() {
  test('ND and NDNA import without clocks and ignore bracketed RDW counts', () async {
    final result = await DailyAmendmentParser(
      documentType: DocumentType.sevenDayAmendment,
    ).parse(pageText: [
      'Report for Saturday 07/11/26 in All Links\n'
      'S Rees 0184 WOD [35] ND\n'
      'D Guest 3685 WOD NDNA\n'
      'A Passmore 4365 WOD NDNA\n'
      'D Pearson 2152 WOD NDNA\n'
      'B Moore 1910 WOD [52] ALLOC 208 08:11 17:10 8.59',
    ]);
    expect(result.canImport, isTrue);
    expect(result.duties.length, 5);
    final nd = result.duties.first;
    expect(nd.payrollNumber, '0184');
    expect(nd.amendmentCode, 'ND');
    expect(nd.dutyType, DutyType.restDay);
    expect(nd.bookOn, isNull);
    expect(nd.turnNumber, isNull);
    expect(result.duties[1].amendmentCode, 'NDNA');
    expect(result.duties[1].dutyType, DutyType.unavailable);
    expect(result.duties.last.turnNumber, '208');
  });
}
