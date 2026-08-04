import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/core/parser/daily_amendment_parser.dart';

void main() {
  group('DailyAmendmentParser header-aware parsing', () {
    test('parses a mapped 10-Day amendment row', () async {
      final parser = DailyAmendmentParser(
        documentType: DocumentType.tenDayAmendment,
      );

      const pageText = '''
10-DAY AMENDMENT
DATE 31/07/2026

NAME  | PAY NO | DEPOT | AMEND | TURN | BOOK ON | BOOK OFF | ROSTERED HOURS | MILEAGE | REMARKS
MOORE | 123456 | BHM   | DI    | 202  | 05:30   | 13:45    | 08:15          | 12      | Driver instructor
''';

      final result = await parser.parse(pageText: const [pageText]);

      expect(result.hasBlockingWarnings, isFalse);
      expect(result.duties, hasLength(1));

      final duty = result.duties.single;

      expect(duty.date, DateTime(2026, 7, 31));
      expect(duty.source, RosterSource.tenDay);
      expect(duty.payrollNumber, '123456');
      expect(duty.driverName, 'MOORE');
      expect(duty.depot, 'BHM');
      expect(duty.amendmentCode, 'DI');
      expect(duty.turnNumber, '202');
      expect(duty.bookOn, '05:30');
      expect(duty.bookOff, '13:45');
      expect(duty.rosteredMinutes, 495);
      expect(duty.mileage, '12');
      expect(duty.dutyType, DutyType.working);
      expect(duty.remarks?.toLowerCase(), contains('driver instructor'));
    });

    test('parses training code without requiring a turn number', () async {
      final parser = DailyAmendmentParser(
        documentType: DocumentType.sevenDayAmendment,
      );

      const pageText = '''
7-DAY AMENDMENT
01/08/2026

DRIVER NAME | PAYROLL NUMBER | LOCATION | CODE | START TIME | FINISH TIME | NOTES
MOORE       | 123456         | BHM      | TS   | 09:00      | 16:00       | Safety briefing
''';

      final result = await parser.parse(pageText: const [pageText]);

      expect(result.hasBlockingWarnings, isFalse);
      expect(result.duties, hasLength(1));

      final duty = result.duties.single;

      expect(duty.payrollNumber, '123456');
      expect(duty.driverName, 'MOORE');
      expect(duty.depot, 'BHM');
      expect(duty.turnNumber, isNull);
      expect(duty.amendmentCode, 'TS');
      expect(duty.bookOn, '09:00');
      expect(duty.bookOff, '16:00');
      expect(duty.rosteredMinutes, 420);
      expect(duty.dutyType, DutyType.training);
      expect(duty.source, RosterSource.sevenDay);
      expect(duty.remarks, contains('Safety Brief/STUD/CA'));
      expect(duty.remarks, contains('Safety briefing'));
    });

    test('treats an unlabelled Sunday daily sheet as 48-Hour', () {
      final parser = DailyAmendmentParser(
        documentType: DocumentType.fortyEightHourAmendment,
      );

      const pageText = '''
SUNDAY 02/08/2026
NAME | PAY NO | DEPOT | TURN | BOOK ON | BOOK OFF
MOORE | 123456 | BHM | 204 | 06:00 | 14:00
''';

      expect(parser.canParse(const [pageText]), isTrue);
    });

    test('does not treat the date or turn number as payroll number', () async {
      final parser = DailyAmendmentParser(
        documentType: DocumentType.fortyEightHourAmendment,
      );

      const pageText = '''
48-HOUR AMENDMENT
03/08/2026

NAME | PAY NO | DEPOT | TURN | BOOK ON | BOOK OFF
MOORE |         | BHM | 202  | 05:30   | 13:30
''';

      final result = await parser.parse(pageText: const [pageText]);

      expect(result.duties, isEmpty);
      expect(result.hasBlockingWarnings, isTrue);
    });

    test('keeps separate rows for different payroll numbers', () async {
      final parser = DailyAmendmentParser(
        documentType: DocumentType.tenDayAmendment,
      );

      const pageText = '''
10 DAY AMENDMENT
04/08/2026

NAME  | PAY NO | DEPOT | AMEND | TURN | BOOK ON | BOOK OFF
MOORE | 123456 | BHM   | SP    | 201  | 05:00   | 13:00
JONES | 654321 | BHM   | DI    | 202  | 06:00   | 14:00
''';

      final result = await parser.parse(pageText: const [pageText]);

      expect(result.hasBlockingWarnings, isFalse);
      expect(result.duties, hasLength(2));
      expect(result.duties.map((duty) => duty.payrollNumber).toSet(), {
        '123456',
        '654321',
      });
    });

    test(
      'parses multiple PDF pages in order with correct page numbers',
      () async {
        final parser = DailyAmendmentParser(
          documentType: DocumentType.sevenDayAmendment,
        );

        const String pageOne = '''
7-DAY AMENDMENT
05/08/2026

NAME | PAY NO | DEPOT | AMEND | TURN | BOOK ON | BOOK OFF
MOORE | 123456 | BHM | DI | 201 | 05:30 | 13:30
''';

        const String pageTwo = '''
7-DAY AMENDMENT
06/08/2026

NAME | PAY NO | DEPOT | AMEND | TURN | BOOK ON | BOOK OFF
JONES | 654321 | BHM | SP | 202 | 06:00 | 14:00
''';

        final result = await parser.parse(
          pageText: const <String>[pageOne, pageTwo],
        );

        expect(result.hasBlockingWarnings, isFalse);
        expect(result.pagesProcessed, 2);
        expect(result.duties, hasLength(2));

        final firstDuty = result.duties[0];
        final secondDuty = result.duties[1];

        expect(firstDuty.date, DateTime(2026, 8, 5));
        expect(firstDuty.payrollNumber, '123456');
        expect(firstDuty.turnNumber, '201');
        expect(firstDuty.pageNumber, 1);

        expect(secondDuty.date, DateTime(2026, 8, 6));
        expect(secondDuty.payrollNumber, '654321');
        expect(secondDuty.turnNumber, '202');
        expect(secondDuty.pageNumber, 2);
      },
    );
  });
}
