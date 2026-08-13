import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/duty.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/core/services/duty_resolver.dart';

void main() {
  profileMatchingTests();
  rangeResolutionTests();
  group('DutyResolver.resolve', () {
    final date = DateTime(2026, 8, 13);

    Duty duty({
      required RosterSource source,
      String? turnNumber,
      DutyType dutyType = DutyType.working,
    }) {
      return Duty(
        date: date,
        source: source,
        dutyType: dutyType,
        turnNumber: turnNumber,
        bookOn: '12:00',
        bookOff: '20:00',
        payrollNumber: '123456',
      );
    }

    test('returns null when there are no duties', () {
      final resolver = DutyResolver();

      expect(resolver.resolve(const <Duty>[]), isNull);
    });

    test('48-Hour overrides 7-Day, 10-Day and Base Roster', () {
      final resolver = DutyResolver();

      final result = resolver.resolve([
        duty(source: RosterSource.baseRoster, turnNumber: '201'),
        duty(source: RosterSource.tenDay, turnNumber: '202'),
        duty(source: RosterSource.sevenDay, turnNumber: '203'),
        duty(source: RosterSource.fortyEightHour, turnNumber: '204'),
      ]);

      expect(result, isNotNull);
      expect(result!.source, RosterSource.fortyEightHour);
      expect(result.turnNumber, '204');
    });

    test('7-Day overrides 10-Day and Base Roster', () {
      final resolver = DutyResolver();

      final result = resolver.resolve([
        duty(source: RosterSource.baseRoster, turnNumber: '201'),
        duty(source: RosterSource.tenDay, turnNumber: '202'),
        duty(source: RosterSource.sevenDay, turnNumber: '203'),
      ]);

      expect(result, isNotNull);
      expect(result!.source, RosterSource.sevenDay);
      expect(result.turnNumber, '203');
    });

    test('10-Day overrides Base Roster', () {
      final resolver = DutyResolver();

      final result = resolver.resolve([
        duty(source: RosterSource.baseRoster, turnNumber: '201'),
        duty(source: RosterSource.tenDay, turnNumber: '202'),
      ]);

      expect(result, isNotNull);
      expect(result!.source, RosterSource.tenDay);
      expect(result.turnNumber, '202');
    });

    test('Manual duty overrides parsed roster sources', () {
      final resolver = DutyResolver();

      final result = resolver.resolve([
        duty(source: RosterSource.baseRoster, turnNumber: '201'),
        duty(source: RosterSource.tenDay, turnNumber: '202'),
        duty(source: RosterSource.sevenDay, turnNumber: '203'),
        duty(source: RosterSource.fortyEightHour, turnNumber: '204'),
        duty(source: RosterSource.manual, turnNumber: '999'),
      ]);

      expect(result, isNotNull);
      expect(result!.source, RosterSource.manual);
      expect(result.turnNumber, '999');
    });

    test('Annual Leave overrides parsed roster sources', () {
      final resolver = DutyResolver();

      final result = resolver.resolve([
        duty(source: RosterSource.baseRoster, turnNumber: '201'),
        duty(source: RosterSource.tenDay, turnNumber: '202'),
        duty(source: RosterSource.sevenDay, turnNumber: '203'),
        duty(source: RosterSource.fortyEightHour, turnNumber: '204'),
        duty(source: RosterSource.annualLeave, dutyType: DutyType.annualLeave),
      ]);

      expect(result, isNotNull);
      expect(result!.source, RosterSource.annualLeave);
      expect(result.dutyType, DutyType.annualLeave);
    });
  });
}

void profileMatchingTests() {
  group('DutyResolver.matchesProfile', () {
    test('matches a daily amendment by payroll number', () {
      final matches = DutyResolver.matchesProfile(
        row: {'payroll_number': '123456', 'driver_number': null},
        payrollNumber: '123456',
        driverNumber: '999',
      );

      expect(matches, isTrue);
    });

    test('matches a Base Roster duty by driver number', () {
      final matches = DutyResolver.matchesProfile(
        row: {'payroll_number': null, 'driver_number': '999'},
        payrollNumber: '123456',
        driverNumber: '999',
      );

      expect(matches, isTrue);
    });

    test('does not match another drivers amendment row', () {
      final matches = DutyResolver.matchesProfile(
        row: {'payroll_number': '654321', 'driver_number': null},
        payrollNumber: '123456',
        driverNumber: '999',
      );

      expect(matches, isFalse);
    });

    test('does not match another drivers Base Roster row', () {
      final matches = DutyResolver.matchesProfile(
        row: {'payroll_number': null, 'driver_number': '888'},
        payrollNumber: '123456',
        driverNumber: '999',
      );

      expect(matches, isFalse);
    });

    test('normalises surrounding spaces before matching', () {
      final matches = DutyResolver.matchesProfile(
        row: {'payroll_number': ' 123456 ', 'driver_number': null},
        payrollNumber: '123456',
        driverNumber: '999',
      );

      expect(matches, isTrue);
    });
  });
}

void rangeResolutionTests() {
  group('DutyResolver.resolveByDate', () {
    test('resolves the highest-priority duty independently for each date', () {
      final resolver = DutyResolver();

      final result = resolver.resolveByDate([
        Duty(
          date: DateTime(2026, 8, 13),
          source: RosterSource.baseRoster,
          dutyType: DutyType.working,
          turnNumber: '201',
          driverNumber: '999',
        ),
        Duty(
          date: DateTime(2026, 8, 13),
          source: RosterSource.fortyEightHour,
          dutyType: DutyType.working,
          turnNumber: '204',
          payrollNumber: '123456',
        ),
        Duty(
          date: DateTime(2026, 8, 14),
          source: RosterSource.baseRoster,
          dutyType: DutyType.working,
          turnNumber: '205',
          driverNumber: '999',
        ),
        Duty(
          date: DateTime(2026, 8, 14),
          source: RosterSource.sevenDay,
          dutyType: DutyType.training,
          turnNumber: '206',
          payrollNumber: '123456',
        ),
      ]);

      expect(result, hasLength(2));

      expect(result['2026-08-13']?.source, RosterSource.fortyEightHour);
      expect(result['2026-08-13']?.turnNumber, '204');

      expect(result['2026-08-14']?.source, RosterSource.sevenDay);
      expect(result['2026-08-14']?.turnNumber, '206');
    });

    test('manual and Annual Leave still override parsed roster duties', () {
      final resolver = DutyResolver();

      final result = resolver.resolveByDate([
        Duty(
          date: DateTime(2026, 8, 15),
          source: RosterSource.fortyEightHour,
          dutyType: DutyType.working,
          turnNumber: '207',
          payrollNumber: '123456',
        ),
        Duty(
          date: DateTime(2026, 8, 15),
          source: RosterSource.annualLeave,
          dutyType: DutyType.annualLeave,
          driverNumber: '999',
        ),
        Duty(
          date: DateTime(2026, 8, 16),
          source: RosterSource.fortyEightHour,
          dutyType: DutyType.working,
          turnNumber: '208',
          payrollNumber: '123456',
        ),
        Duty(
          date: DateTime(2026, 8, 16),
          source: RosterSource.manual,
          dutyType: DutyType.restDay,
        ),
      ]);

      expect(result['2026-08-15']?.source, RosterSource.annualLeave);
      expect(result['2026-08-15']?.dutyType, DutyType.annualLeave);

      expect(result['2026-08-16']?.source, RosterSource.manual);
      expect(result['2026-08-16']?.dutyType, DutyType.restDay);
    });

    test('returns an empty map for no duties', () {
      final resolver = DutyResolver();

      expect(resolver.resolveByDate(const <Duty>[]), isEmpty);
    });
  });
}
