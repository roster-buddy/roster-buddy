import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/duty.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/core/services/hidden_18_service.dart';

void main() {
  const Hidden18Service service = Hidden18Service();

  Duty workingDuty({
    required DateTime date,
    String bookOn = '08:00',
    String bookOff = '16:00',
    int? rosteredMinutes,
    DutyType dutyType = DutyType.working,
  }) {
    return Duty(
      date: date,
      source: RosterSource.manual,
      dutyType: dutyType,
      bookOn: bookOn,
      bookOff: bookOff,
      rosteredMinutes: rosteredMinutes,
    );
  }

  Duty nonWorkingDuty({required DateTime date, required DutyType dutyType}) {
    return Duty(
      date: date,
      source: RosterSource.annualLeave,
      dutyType: dutyType,
    );
  }

  group('Hidden18Service', () {
    test('warns when a duty exceeds 12 hours', () {
      final Hidden18Result result = service.evaluate(<Duty>[
        workingDuty(date: DateTime(2026, 8, 1), rosteredMinutes: 12 * 60 + 1),
      ]);

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.shiftLength,
        ),
        isTrue,
      );
    });

    test('does not warn for a duty exactly 12 hours', () {
      final Hidden18Result result = service.evaluate(<Duty>[
        workingDuty(date: DateTime(2026, 8, 1), rosteredMinutes: 12 * 60),
      ]);

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.shiftLength,
        ),
        isFalse,
      );
    });

    test('warns when rest between duties is less than 12 hours', () {
      final Hidden18Result result = service.evaluate(<Duty>[
        workingDuty(
          date: DateTime(2026, 8, 1),
          bookOn: '12:00',
          bookOff: '23:00',
        ),
        workingDuty(
          date: DateTime(2026, 8, 2),
          bookOn: '10:00',
          bookOff: '18:00',
        ),
      ]);

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.minimumRest,
        ),
        isTrue,
      );
    });

    test('does not warn when rest is exactly 12 hours', () {
      final Hidden18Result result = service.evaluate(<Duty>[
        workingDuty(
          date: DateTime(2026, 8, 1),
          bookOn: '12:00',
          bookOff: '23:00',
        ),
        workingDuty(
          date: DateTime(2026, 8, 2),
          bookOn: '11:00',
          bookOff: '19:00',
        ),
      ]);

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.minimumRest,
        ),
        isFalse,
      );
    });

    test('handles overnight duties when calculating rest', () {
      final Hidden18Result result = service.evaluate(<Duty>[
        workingDuty(
          date: DateTime(2026, 8, 1),
          bookOn: '18:00',
          bookOff: '02:00',
        ),
        workingDuty(
          date: DateTime(2026, 8, 2),
          bookOn: '12:00',
          bookOff: '20:00',
        ),
      ]);

      final Hidden18Warning warning = result.warnings.firstWhere(
        (Hidden18Warning item) => item.type == Hidden18WarningType.minimumRest,
      );

      expect(warning.minutes, 10 * 60);
    });

    test('warns when more than 72 hours are worked in seven days', () {
      final DateTime start = DateTime(2026, 8, 2);

      final List<Duty> duties = List<Duty>.generate(
        7,
        (int index) => workingDuty(
          date: start.add(Duration(days: index)),
          rosteredMinutes: 10 * 60 + 30,
        ),
      );

      final Hidden18Result result = service.evaluate(duties);

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.rollingSevenDays,
        ),
        isTrue,
      );

      expect(result.rollingSevenDayMinutes, 73 * 60 + 30);
    });

    test('does not warn at exactly 72 hours in seven days', () {
      final DateTime start = DateTime(2026, 8, 2);

      final List<Duty> duties = <Duty>[
        for (int index = 0; index < 6; index++)
          workingDuty(
            date: start.add(Duration(days: index)),
            rosteredMinutes: 12 * 60,
          ),
      ];

      final Hidden18Result result = service.evaluate(duties);

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.rollingSevenDays,
        ),
        isFalse,
      );

      expect(result.rollingSevenDayMinutes, 72 * 60);
    });

    test('warns on the 14th consecutive working day', () {
      final DateTime start = DateTime(2026, 8, 1);

      final Hidden18Result result = service.evaluate(
        List<Duty>.generate(
          14,
          (int index) => workingDuty(
            date: start.add(Duration(days: index)),
            rosteredMinutes: 60,
          ),
        ),
      );

      final Hidden18Warning warning = result.warnings.firstWhere(
        (Hidden18Warning item) =>
            item.type == Hidden18WarningType.consecutiveDays,
      );

      expect(warning.date, DateTime(2026, 8, 14));
    });

    test('granted annual leave resets consecutive working days', () {
      final DateTime start = DateTime(2026, 8, 1);

      final List<Duty> duties = <Duty>[
        for (int index = 0; index < 10; index++)
          workingDuty(
            date: start.add(Duration(days: index)),
            rosteredMinutes: 60,
          ),

        // Represents either granted floating ALD or block AW after resolution.
        nonWorkingDuty(
          date: DateTime(2026, 8, 11),
          dutyType: DutyType.annualLeave,
        ),

        for (int index = 11; index < 20; index++)
          workingDuty(
            date: start.add(Duration(days: index)),
            rosteredMinutes: 60,
          ),
      ];

      final Hidden18Result result = service.evaluate(duties);

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.consecutiveDays,
        ),
        isFalse,
      );

      expect(result.consecutiveDaysWorked, 9);
    });

    test('sickness resets consecutive working days', () {
      final DateTime start = DateTime(2026, 8, 1);

      final List<Duty> duties = <Duty>[
        for (int index = 0; index < 8; index++)
          workingDuty(
            date: start.add(Duration(days: index)),
            rosteredMinutes: 60,
          ),
        nonWorkingDuty(date: DateTime(2026, 8, 9), dutyType: DutyType.sick),
        for (int index = 9; index < 18; index++)
          workingDuty(
            date: start.add(Duration(days: index)),
            rosteredMinutes: 60,
          ),
      ];

      final Hidden18Result result = service.evaluate(duties);

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.consecutiveDays,
        ),
        isFalse,
      );

      expect(result.consecutiveDaysWorked, 9);
    });

    test('a worked Sunday counts as a consecutive working day', () {
      // 2 August 2026 is a Sunday.
      final DateTime start = DateTime(2026, 8, 2);

      final Hidden18Result result = service.evaluate(
        List<Duty>.generate(
          14,
          (int index) => workingDuty(
            date: start.add(Duration(days: index)),
            rosteredMinutes: 60,
          ),
        ),
      );

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.consecutiveDays,
        ),
        isTrue,
      );
    });

    test('training and medical count as working days', () {
      final DateTime start = DateTime(2026, 8, 1);

      final List<Duty> duties = <Duty>[
        for (int index = 0; index < 12; index++)
          workingDuty(
            date: start.add(Duration(days: index)),
            rosteredMinutes: 60,
          ),
        workingDuty(
          date: DateTime(2026, 8, 13),
          rosteredMinutes: 60,
          dutyType: DutyType.training,
        ),
        workingDuty(
          date: DateTime(2026, 8, 14),
          rosteredMinutes: 60,
          dutyType: DutyType.medical,
        ),
      ];

      final Hidden18Result result = service.evaluate(duties);

      expect(
        result.warnings.any(
          (Hidden18Warning warning) =>
              warning.type == Hidden18WarningType.consecutiveDays,
        ),
        isTrue,
      );
    });
  });
}
