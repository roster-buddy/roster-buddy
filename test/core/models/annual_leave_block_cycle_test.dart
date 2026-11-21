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

    test('keeps Group 9 while projecting columns across missing years', () {
      const anchor = AnnualLeaveBlockCycle(
        leaveYear: 2027,
        weekIndex: 9,
        source: 'manual',
      );
      final projections = [
        for (final year in [2028, 2029, 2030, 2031])
          anchor.projectToYear(year),
      ];
      expect(projections.map((cycle) => cycle.weekIndex), [9, 9, 9, 9]);
      expect(projections.map((cycle) => cycle.columnIndex), [1, 6, 11, 3]);
      expect(projections.first.nextYearWeekIndex, 6);
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
