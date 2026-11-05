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

  test('NONA OCR alias becomes NDNA without changing names or timed rows', () async {
    final result = await DailyAmendmentParser(
      documentType: DocumentType.sevenDayAmendment,
    ).parse(pageText: [
      'Report for Saturday 07/11/26 in All Links\n'
      'D Guest 3685 WOD NONA\n'
      'A Passmore 4365 WOD [35] NONA\n'
      'Nona Smith 2152 WOD ND\n'
      'B Moore 1910 WOD NONA 208 08:11 17:10 8.59',
    ]);
    expect(result.canImport, isTrue);
    expect(result.duties.length, 4);
    for (final duty in result.duties.take(2)) {
      expect(duty.amendmentCode, 'NDNA');
      expect(duty.dutyType, DutyType.unavailable);
      expect(duty.bookOn, isNull);
      expect(duty.rawText, contains('NONA'));
    }
    expect(result.duties[2].driverName, 'Nona Smith');
    expect(result.duties[2].amendmentCode, 'ND');
    expect(result.duties.last.dutyType, DutyType.working);
    expect(result.duties.last.bookOn, '08:11');
    expect(result.duties.last.bookOff, '17:10');
  });
}
