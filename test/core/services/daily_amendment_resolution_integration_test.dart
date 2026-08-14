import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/duty.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/core/parser/daily_amendment_parser.dart';
import 'package:roster_buddy/core/services/duty_resolver.dart';

void main() {
  group('Daily amendment → profile matching → duty resolution', () {
    const String payrollNumber = '123456';
    const String driverNumber = '999';

    test(
      'parsed 48-Hour amendment for driver overrides 7-Day, 10-Day and Base',
      () async {
        final DateTime date = DateTime(2026, 8, 13);

        final Duty baseDuty = Duty(
          date: date,
          source: RosterSource.baseRoster,
          dutyType: DutyType.working,
          turnNumber: '201',
          bookOn: '05:00',
          bookOff: '13:00',
          driverNumber: driverNumber,
        );

        final tenDayParser = DailyAmendmentParser(
          documentType: DocumentType.tenDayAmendment,
        );

        const String tenDayText = '''
10-DAY AMENDMENT
13/08/2026

NAME | PAY NO | DEPOT | AMEND | TURN | BOOK ON | BOOK OFF
MOORE | 123456 | BHM | DI | 202 | 05:30 | 13:30
''';

        final tenDayResult = await tenDayParser.parse(
          pageText: const <String>[tenDayText],
        );

        expect(tenDayResult.hasBlockingWarnings, isFalse);
        expect(tenDayResult.duties, hasLength(1));

        final sevenDayParser = DailyAmendmentParser(
          documentType: DocumentType.sevenDayAmendment,
        );

        const String sevenDayText = '''
7-DAY AMENDMENT
13/08/2026

NAME | PAY NO | DEPOT | AMEND | TURN | BOOK ON | BOOK OFF
MOORE | 123456 | BHM | DI | 203 | 06:00 | 14:00
''';

        final sevenDayResult = await sevenDayParser.parse(
          pageText: const <String>[sevenDayText],
        );

        expect(sevenDayResult.hasBlockingWarnings, isFalse);
        expect(sevenDayResult.duties, hasLength(1));

        final fortyEightHourParser = DailyAmendmentParser(
          documentType: DocumentType.fortyEightHourAmendment,
        );

        const String fortyEightHourText = '''
48-HOUR AMENDMENT
13/08/2026

NAME | PAY NO | DEPOT | AMEND | TURN | BOOK ON | BOOK OFF
MOORE | 123456 | BHM | DI | 204 | 07:00 | 15:00
''';

        final fortyEightHourResult = await fortyEightHourParser.parse(
          pageText: const <String>[fortyEightHourText],
        );

        expect(fortyEightHourResult.hasBlockingWarnings, isFalse);
        expect(fortyEightHourResult.duties, hasLength(1));

        final List<Duty> parsedDuties = <Duty>[
          tenDayResult.duties.single,
          sevenDayResult.duties.single,
          fortyEightHourResult.duties.single,
        ];

        final List<Duty> matchingDuties = parsedDuties
            .where((Duty duty) {
              return DutyResolver.matchesProfile(
                row: <String, dynamic>{
                  'source': duty.source.name == 'tenDay'
                      ? '10_day'
                      : duty.source.name == 'sevenDay'
                      ? '7_day'
                      : '48_hour',
                  'payroll_number': duty.payrollNumber,
                  'driver_number': duty.driverNumber,
                },
                payrollNumber: payrollNumber,
                rosterNumber: driverNumber,
              );
            })
            .toList(growable: false);

        expect(matchingDuties, hasLength(3));

        final DutyResolver resolver = DutyResolver();

        final Duty? resolved = resolver.resolve(<Duty>[
          baseDuty,
          ...matchingDuties,
        ]);

        expect(resolved, isNotNull);
        expect(resolved!.source, RosterSource.fortyEightHour);
        expect(resolved.turnNumber, '204');
        expect(resolved.payrollNumber, payrollNumber);
        expect(resolved.bookOn, '07:00');
        expect(resolved.bookOff, '15:00');
      },
    );

    test('another driver on the same amendment sheet is excluded', () async {
      final parser = DailyAmendmentParser(
        documentType: DocumentType.fortyEightHourAmendment,
      );

      const String pageText = '''
48-HOUR AMENDMENT
13/08/2026

NAME | PAY NO | DEPOT | TURN | BOOK ON | BOOK OFF
MOORE | 123456 | BHM | 204 | 07:00 | 15:00
JONES | 654321 | BHM | 205 | 08:00 | 16:00
''';

      final result = await parser.parse(pageText: const <String>[pageText]);

      expect(result.hasBlockingWarnings, isFalse);
      expect(result.duties, hasLength(2));

      final List<Duty> matchingDuties = result.duties
          .where((Duty duty) {
            return DutyResolver.matchesProfile(
              row: <String, dynamic>{
                'source': '48_hour',
                'payroll_number': duty.payrollNumber,
                'driver_number': duty.driverNumber,
              },
              payrollNumber: payrollNumber,
              rosterNumber: driverNumber,
            );
          })
          .toList(growable: false);

      expect(matchingDuties, hasLength(1));
      expect(matchingDuties.single.payrollNumber, payrollNumber);
      expect(matchingDuties.single.turnNumber, '204');
    });
  });
}
