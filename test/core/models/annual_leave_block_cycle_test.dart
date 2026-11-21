import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/annual_leave_block_cycle.dart';

void main() {
  group('AnnualLeaveBlockCycle', () {
    test('advances week by five positions', () {
      expect(AnnualLeaveBlockCycle.advanceWeekIndex(1), 6);
      expect(AnnualLeaveBlockCycle.advanceWeekIndex(6), 11);
    });

    test('wraps after week 13', () {
      expect(AnnualLeaveBlockCycle.advanceWeekIndex(11), 3);
      expect(AnnualLeaveBlockCycle.advanceWeekIndex(13), 5);
      expect(AnnualLeaveBlockCycle.advanceWeekIndex(9), 1);
    });

    test('full cycle eventually returns to original week', () {
      int week = 1;

      for (int year = 0; year < 13; year++) {
        week = AnnualLeaveBlockCycle.advanceWeekIndex(week);
      }

      expect(week, 1);
    });

    test('projects directly from a saved year across missing years', () {
      const anchor = AnnualLeaveBlockCycle(
        leaveYear: 2027,
        weekIndex: 9,
        source: 'manual',
      );
      expect(anchor.weekIndexForYear(2027), 9);
      expect(anchor.weekIndexForYear(2028), 1);
      expect(anchor.weekIndexForYear(2029), 6);
      expect(anchor.weekIndexForYear(2030), 11);
      expect(anchor.weekIndexForYear(2031), 3);
    });

    test('rejects values outside 1 to 13', () {
      expect(
        () => AnnualLeaveBlockCycle.advanceWeekIndex(0),
        throwsArgumentError,
      );

      expect(
        () => AnnualLeaveBlockCycle.advanceWeekIndex(14),
        throwsArgumentError,
      );
    });
  });
}
