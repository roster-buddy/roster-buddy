import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/parser/daily_amendment_parser.dart';

void main() {
  final parser = DailyAmendmentParser(
    documentType: DocumentType.sevenDayAmendment,
  );
  test(
    'wrapped printed headings do not turn payroll or codes into times',
    () async {
      final result = await parser.parse(
        pageText: const [
          '''
Daily Roster Report
Report for Saturday 07/11/26 in All Links
Pay Depot Amend
Name Turn Book Book Rostered Mileage
No. Ind / Count On Off Hours
A Tester 1104 WOD ALLOC 9001 04:23 13:08 8.45 Amended Turn
B Example 3731 WOD TW TW 05:00 13:45 8.45
C Sample 1378 WOD D3 D3 15:41 00:25 8.44
D Demo 1910 WOD ALD
E Other 1890 WOD ALD 08:45
''',
        ],
      );
      expect(result.canImport, isTrue);
      expect(result.duties, hasLength(5));
      final working = result.duties.first;
      expect(working.payrollNumber, '1104');
      expect(working.turnNumber, '9001');
      expect(working.bookOn, '04:23');
      expect(working.bookOff, '13:08');
      expect(result.duties[1].bookOn, '05:00');
      expect(result.duties[2].turnNumber, isNull);
      expect(result.duties[2].bookOn, '15:41');
      for (final d in result.duties.skip(3)) {
        expect(d.dutyType, DutyType.annualLeave);
        expect(d.bookOn, isNull);
        expect(d.bookOff, isNull);
        expect(d.turnNumber, isNull);
      }
    },
  );
  test('report headings cannot be imported as driver records', () async {
    final result = await parser.parse(
      pageText: const ['Report for Saturday 07/11/26 in All Links'],
    );
    expect(result.duties, isEmpty);
    expect(result.canImport, isFalse);
  });
  test('an incomplete working row blocks the whole import', () async {
    final result = await parser.parse(
      pageText: const [
        '''
Report for Thursday 05/11/26 in All Links
A Tester 1104 WOD ALLOC 213 16:53 01:11 8.45
B Example 3731 WOD TW TW 05:00
''',
      ],
    );
    expect(result.canImport, isFalse);
    expect(result.hasBlockingWarnings, isTrue);
  });
  test('the report date wins over dates on neighbouring sheets', () async {
    final result = await parser.parse(
      pageText: const [
        '''
01/11/26
Report for Thursday 05/11/26 in All Links
A Tester 1910 WOD ALLOC 213 16:53 01:11 8.45
''',
      ],
    );
    expect(result.duties.single.date, DateTime(2026, 11, 5));
    expect(result.duties.single.turnNumber, '213');
  });
}
