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
      expect(result.duties[2].dutyType, DutyType.unavailable);
      expect(result.duties[2].amendmentCode, 'D3');
      expect(result.duties[2].bookOn, isNull);
      expect(result.duties[2].bookOff, isNull);
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
  test('damaged D3 row is light duties with no book-on or book-off', () async {
    final result = await parser.parse(pageText: const [
      'Report for Thursday 12/11/26 in All Links\n'
      'NAJ Macpherson 3075 WOD D3 D3= 2041904 “13:22 8.28\n'
      'RMF Peers 3524 WOD ALLOC 204 04:56 12:58 8.02'
    ]);
    expect(result.hasBlockingWarnings, isFalse);
    expect(result.duties, hasLength(2));
    final macpherson = result.duties.singleWhere(
      (duty) => duty.payrollNumber == '3075',
    );
    expect(macpherson.amendmentCode, 'D3');
    expect(macpherson.dutyType, DutyType.unavailable);
    expect(macpherson.bookOn, isNull);
    expect(macpherson.bookOff, isNull);
    expect(macpherson.turnNumber, isNull);
    expect(macpherson.rosteredMinutes, isNull);
    final peers = result.duties.singleWhere(
      (duty) => duty.payrollNumber == '3524',
    );
    expect(peers.bookOn, '04:56');
    expect(peers.bookOff, '12:58');
  });

  test('even severely damaged D3 clock stays light duties', () async {
    final result = await parser.parse(pageText: const [
      'Report for Thursday 12/11/26 in All Links\n'
      'NAJ Macpherson 3075 WOD D3 D3= 2041999 “13:22 8.28\n'
      'RMF Peers 3524 WOD ALLOC 204 04:56 12:58 8.02'
    ]);
    expect(result.hasBlockingWarnings, isFalse);
    expect(result.duties, hasLength(2));
    final d3 = result.duties.singleWhere(
      (duty) => duty.payrollNumber == '3075',
    );
    expect(d3.dutyType, DutyType.unavailable);
    expect(d3.amendmentCode, 'D3');
    expect(d3.bookOn, isNull);
    expect(d3.bookOff, isNull);
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
  test('Sunday turns retain one digit and overnight finish times', () async {
    final result = await parser.parse(
      pageText: const [
        'Report for Sunday 08/11/26 in All Links\n'
            'A Example 1718 WOD ALLOC 2 07:44 13:38 Amended Turn\n'
            'B Example 1108 WOD 9 17:59 00:12\n'
            'C Example 1587 WOD 9001 07:19 16:04\n'
            '- vacancy - WOD 6 15:34 23:40 8.06 Amended Turn\n'
            'D Example 0184 WOD [22] ND\n'
            'E Example 1378 WOD ZS ZS',
      ],
    );
    expect(result.canImport, isTrue);
    expect(result.duties, hasLength(5));
    expect(result.duties.map((d) => d.turnNumber), [
      '2',
      '9',
      '9001',
      null,
      null,
    ]);
    expect(result.duties[1].bookOff, '00:12');
    expect(result.duties[1].rosteredMinutes, 373);
    expect(result.duties.last.dutyType, DutyType.unavailable);
  });
  test('Sunday ZS OCR lookalikes remain unavailable duties', () async {
    final result = await parser.parse(
      pageText: const [
        'Report for Sunday 08/11/26 in All Links\n'
            'A Example 1890 WOD 2S 2s\n'
            'B Example 2175 WOD 28 28\n'
            'C Example 1104 WOD Z8 Z8\n'
            'D Example 1719 WOD IS IS',
      ],
    );
    expect(result.canImport, isTrue);
    expect(result.duties, hasLength(4));
    for (final duty in result.duties) {
      expect(duty.dutyType, DutyType.unavailable);
      expect(duty.amendmentCode, 'ZS');
    }
  });
  test('payroll-first Sunday rows remain safe without an OCR name', () async {
    final result = await parser.parse(
      pageText: const [
        'Report for Sunday 08/11/26 in All Links\n'
            '1378 WOD ZS ZS\n'
            '3280 WOD ZS ZS',
      ],
    );
    expect(result.canImport, isTrue);
    expect(result.duties, hasLength(2));
    expect(result.duties.map((d) => d.payrollNumber), ['1378', '3280']);
    expect(result.duties.every((d) => d.driverName == null), isTrue);
    expect(result.duties.every((d) => d.dutyType == DutyType.unavailable), isTrue);
  });
  test('payroll is canonical when OCR supplies two versions of one row', () async {
    final result = await parser.parse(
      pageText: const [
        'Report for Wednesday 28/10/26 in All Links\n'
            'A White 0049 WOD RDW 215 17:11 01:31 8.45 Amended Turn\n'
            '0049 WOD RDW 215 17:11 01:31 Amended Turn',
      ],
    );
    expect(result.canImport, isTrue);
    expect(result.duties, hasLength(1));
    expect(result.duties.single.payrollNumber, '0049');
    expect(result.duties.single.turnNumber, '215');
    expect(result.duties.single.bookOn, '17:11');
    expect(result.duties.single.bookOff, '01:31');
  });
  test('different names preserve a genuine last-four payroll collision', () async {
    final result = await parser.parse(
      pageText: const [
        'Report for Wednesday 28/10/26 in All Links\n'
            'A White 0049 WOD RDW 215 17:11 01:31 Amended Turn\n'
            'B Other 0049 WOD ALLOC 216 18:00 02:00 Amended Turn',
      ],
    );
    expect(result.canImport, isTrue);
    expect(result.duties, hasLength(2));
    expect(result.duties.map((d) => d.driverName), ['A White', 'B Other']);
    expect(result.duties.map((d) => d.turnNumber), ['215', '216']);
  });
  test('a clean payroll row rescues a corrupt OCR version of the same row', () async {
    final result = await parser.parse(
      pageText: const [
        'Report for Monday 09/11/26 in All Links\n'
            'R Brown 3686 WOD TW TH+: 125001420245 8.45\n'
            'D Mount 1957 wWOD 210/51.3:159% 23:10); 9.11\n'
            'D Mount 1957 WOD 210 13:59 23:10 9.11',
      ],
    );
    expect(result.canImport, isTrue);
    expect(result.hasBlockingWarnings, isFalse);
    expect(result.duties, hasLength(2));
    final brown = result.duties.singleWhere((d) => d.payrollNumber == '3686');
    expect(brown.bookOn, '12:00');
    expect(brown.bookOff, '20:45');
    final mount = result.duties.singleWhere((d) => d.payrollNumber == '1957');
    expect(mount.turnNumber, '210');
    expect(mount.bookOn, '13:59');
    expect(mount.bookOff, '23:10');
  });
  test('Saturday leave hours and split NDNA rows import automatically', () async {
    final result = await parser.parse(
      pageText: const [
        'Report for Saturday 07/11/26 in All Links\n'
            'Moore 1910 WOD ALD ALD 08:45\n'
            '1190 WOD Exchanged N DNA',
      ],
    );
    expect(result.canImport, isTrue);
    expect(result.duties, hasLength(2));
    expect(result.duties.first.payrollNumber, '1910');
    expect(result.duties.first.dutyType, DutyType.annualLeave);
    expect(result.duties.first.bookOn, isNull);
    expect(result.duties.last.payrollNumber, '1190');
    expect(result.duties.last.amendmentCode, 'NDNA');
    expect(result.duties.last.dutyType, DutyType.unavailable);
  });
  test('damaged Macpherson D3 row imports as light duties without clocks', () async {
    final result = await DailyAmendmentParser(
      documentType: DocumentType.fortyEightHourAmendment,
    ).parse(pageText: const ['''
Report for Thursday 12/11/26 in All Links
NAJ Macpherson 3075 WOD D3 D3= 2041904 “13:22 8.28
B Moore 1910 WOD RDW 208 08:11 17:10 8.59
''']);
    expect(result.canImport, isTrue);
    expect(result.hasBlockingWarnings, isFalse);
    expect(result.duties, hasLength(2));
    final d3 = result.duties.singleWhere((d) => d.payrollNumber == '3075');
    expect(d3.date, DateTime(2026, 11, 12));
    expect(d3.dutyType, DutyType.unavailable);
    expect(d3.amendmentCode, 'D3');
    expect(d3.remarks, 'Light Duties — Not attending');
    expect(d3.turnNumber, isNull);
    expect(d3.bookOn, isNull);
    expect(d3.bookOff, isNull);
    expect(d3.rosteredMinutes, isNull);
    final moore = result.duties.singleWhere((d) => d.payrollNumber == '1910');
    expect(moore.bookOn, '08:11');
    expect(moore.bookOff, '17:10');
  });

  test('clean D3 printed times are also ignored', () async {
    final result = await DailyAmendmentParser(
      documentType: DocumentType.fortyEightHourAmendment,
    ).parse(pageText: const ['''
Report for Thursday 12/11/26 in All Links
NAJ Macpherson 3075 WOD D3 D3 04:54 13:22 8.28\n''']);
    expect(result.canImport, isTrue);
    final duty = result.duties.single;
    expect(duty.dutyType, DutyType.unavailable);
    expect(duty.amendmentCode, 'D3');
    expect(duty.bookOn, isNull);
    expect(duty.bookOff, isNull);
  });


}
