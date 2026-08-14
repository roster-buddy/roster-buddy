import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/annual_leave_block_override.dart';
import 'package:roster_buddy/core/models/duty.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/core/services/duty_resolver.dart';

void main() {
  profileMatchingTests();
  rangeResolutionTests();
  blockAnnualLeaveTests();
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

void blockAnnualLeaveTests() {
  group('DutyResolver block annual leave', () {
    AnnualLeaveBlockOverride override({
      required AnnualLeaveBlockChangeType changeType,
      DateTime? originalStart,
      DateTime? originalEnd,
      DateTime? overrideStart,
      DateTime? overrideEnd,
    }) {
      return AnnualLeaveBlockOverride(
        id: 'test-override',
        leaveYear: 2026,
        periodType: AnnualLeaveBlockPeriodType.spring,
        originalStartDate: originalStart,
        originalEndDate: originalEnd,
        overrideStartDate: overrideStart ?? DateTime(2026, 4, 6),
        overrideEndDate: overrideEnd ?? DateTime(2026, 4, 11),
        changeType: changeType,
      );
    }

    test('manual block allocation creates block annual leave duty', () {
      final AnnualLeaveBlockOverride manual = override(
        changeType: AnnualLeaveBlockChangeType.manual,
      );

      final Duty duty = DutyResolver.blockOverrideDutyForTest(
        override: manual,
        date: DateTime(2026, 4, 8),
      );

      expect(duty.source, RosterSource.annualLeave);
      expect(duty.dutyType, DutyType.annualLeave);
      expect(duty.date, DateTime(2026, 4, 8));
      expect(duty.remarks, contains('Spring block annual leave'));
      expect(duty.remarks, contains('Manual block leave'));
    });

    test('official allocation suppresses stale manual baseline', () {
      final AnnualLeaveBlockOverride manual = override(
        changeType: AnnualLeaveBlockChangeType.manual,
      );

      final List<AnnualLeaveBlockOverride> effective =
          DutyResolver.effectiveBlockOverridesForTest(
            overrides: <AnnualLeaveBlockOverride>[manual],
            officialPeriodKeys: <String>{
              '2026:${AnnualLeaveBlockPeriodType.spring.name}',
            },
          );

      expect(effective, isEmpty);
    });

    test(
      'manual baseline remains active when no official allocation exists',
      () {
        final AnnualLeaveBlockOverride manual = override(
          changeType: AnnualLeaveBlockChangeType.manual,
        );

        final List<AnnualLeaveBlockOverride> effective =
            DutyResolver.effectiveBlockOverridesForTest(
              overrides: <AnnualLeaveBlockOverride>[manual],
              officialPeriodKeys: const <String>{},
            );

        expect(effective, hasLength(1));
        expect(effective.single.changeType, AnnualLeaveBlockChangeType.manual);
      },
    );

    test('agreed move still overrides an official allocation', () {
      final AnnualLeaveBlockOverride moved = override(
        changeType: AnnualLeaveBlockChangeType.agreedMove,
        originalStart: DateTime(2026, 4, 6),
        originalEnd: DateTime(2026, 4, 11),
        overrideStart: DateTime(2026, 5, 4),
        overrideEnd: DateTime(2026, 5, 9),
      );

      final List<AnnualLeaveBlockOverride> effective =
          DutyResolver.effectiveBlockOverridesForTest(
            overrides: <AnnualLeaveBlockOverride>[moved],
            officialPeriodKeys: <String>{
              '2026:${AnnualLeaveBlockPeriodType.spring.name}',
            },
          );

      expect(effective, hasLength(1));
      expect(
        effective.single.changeType,
        AnnualLeaveBlockChangeType.agreedMove,
      );

      final Duty duty = DutyResolver.blockOverrideDutyForTest(
        override: effective.single,
        date: DateTime(2026, 5, 6),
      );

      expect(duty.source, RosterSource.annualLeave);
      expect(duty.dutyType, DutyType.annualLeave);
      expect(duty.remarks, contains('Moved block annual leave'));
    });

    test('mutual swap still overrides an official allocation', () {
      final AnnualLeaveBlockOverride swapped = AnnualLeaveBlockOverride(
        id: 'test-swap',
        leaveYear: 2026,
        periodType: AnnualLeaveBlockPeriodType.summerFirstWeek,
        originalStartDate: DateTime(2026, 6, 8),
        originalEndDate: DateTime(2026, 6, 13),
        overrideStartDate: DateTime(2026, 7, 6),
        overrideEndDate: DateTime(2026, 7, 11),
        changeType: AnnualLeaveBlockChangeType.mutualSwap,
        swapDriverNumber: '999',
      );

      final List<AnnualLeaveBlockOverride> effective =
          DutyResolver.effectiveBlockOverridesForTest(
            overrides: <AnnualLeaveBlockOverride>[swapped],
            officialPeriodKeys: <String>{
              '2026:${AnnualLeaveBlockPeriodType.summerFirstWeek.name}',
            },
          );

      expect(effective, hasLength(1));
      expect(
        effective.single.changeType,
        AnnualLeaveBlockChangeType.mutualSwap,
      );

      final Duty duty = DutyResolver.blockOverrideDutyForTest(
        override: effective.single,
        date: DateTime(2026, 7, 8),
      );

      expect(duty.source, RosterSource.annualLeave);
      expect(duty.dutyType, DutyType.annualLeave);
      expect(duty.remarks, contains('Mutual swap block annual leave'));
    });
  });
}

void profileMatchingTests() {
  group('DutyResolver.matchesProfile', () {
    test('matches a daily amendment by payroll number', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': '10_day',
          'payroll_number': '123456',
          'driver_number': null,
        },
        payrollNumber: '123456',
        rosterNumber: '999',
      );

      expect(matches, isTrue);
    });

    test('matches a 7-Day amendment by payroll number', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': '7_day',
          'payroll_number': '123456',
          'driver_number': null,
        },
        payrollNumber: '123456',
        rosterNumber: '999',
      );

      expect(matches, isTrue);
    });

    test('matches a 48-Hour amendment by payroll number', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': '48_hour',
          'payroll_number': '123456',
          'driver_number': null,
        },
        payrollNumber: '123456',
        rosterNumber: '999',
      );

      expect(matches, isTrue);
    });

    test('matches a Base Roster duty by roster number', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': 'base_roster',
          'payroll_number': null,
          'driver_number': '999',
        },
        payrollNumber: '123456',
        rosterNumber: '999',
      );

      expect(matches, isTrue);
    });

    test('does not use roster number to match an amendment', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': '10_day',
          'payroll_number': '999',
          'driver_number': '999',
        },
        payrollNumber: '123456',
        rosterNumber: '999',
      );

      expect(matches, isFalse);
    });

    test('does not use payroll number to match a Base Roster duty', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': 'base_roster',
          'payroll_number': '123456',
          'driver_number': '123456',
        },
        payrollNumber: '123456',
        rosterNumber: '999',
      );

      expect(matches, isFalse);
    });

    test('does not match another drivers amendment row', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': '10_day',
          'payroll_number': '654321',
          'driver_number': null,
        },
        payrollNumber: '123456',
        rosterNumber: '999',
      );

      expect(matches, isFalse);
    });

    test('does not match another drivers Base Roster row', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': 'base_roster',
          'payroll_number': null,
          'driver_number': '888',
        },
        payrollNumber: '123456',
        rosterNumber: '999',
      );

      expect(matches, isFalse);
    });

    test('normalises surrounding spaces before payroll matching', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': '48_hour',
          'payroll_number': ' 123456 ',
          'driver_number': null,
        },
        payrollNumber: '123456',
        rosterNumber: '999',
      );

      expect(matches, isTrue);
    });

    test('normalises surrounding spaces before roster matching', () {
      final matches = DutyResolver.matchesProfile(
        row: {
          'source': 'base_roster',
          'payroll_number': null,
          'driver_number': ' 999 ',
        },
        payrollNumber: '123456',
        rosterNumber: '999',
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
