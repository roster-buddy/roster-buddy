import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/annual_leave_allocation.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/parser/annual_leave_roster_parser.dart';

void main() {
  group('AnnualLeaveRosterParser', () {
    test('recognises an Annual Leave Roster', () {
      const AnnualLeaveRosterParser parser = AnnualLeaveRosterParser();

      expect(
        parser.canParse(const <String>[
          'ANNUAL LEAVE ROSTER 2027\n'
              'BLOCK | 1 | 2\n'
              'SPRING | 01/03/2027 - 07/03/2027 | '
              '08/03/2027 - 14/03/2027\n'
              'WINTER | 01/11/2027 - 07/11/2027 | '
              '08/11/2027 - 14/11/2027',
        ]),
        isTrue,
      );
    });

    test('extracts every driver beneath each block column', () async {
      const AnnualLeaveRosterParser parser = AnnualLeaveRosterParser(
        defaultDepot: 'Birmingham',
      );

      final result = await parser.parse(
        pageText: const <String>[
          'ANNUAL LEAVE ROSTER 2027\n'
              'DEPOT: Birmingham\n'
              'BLOCK | 1 | 2\n'
              'SPRING | 01/03/2027 - 07/03/2027 | '
              '08/03/2027 - 14/03/2027\n'
              'SUMMER 1 | 07/06/2027 - 13/06/2027 | '
              '14/06/2027 - 20/06/2027\n'
              'SUMMER 2 | 06/09/2027 - 12/09/2027 | '
              '13/09/2027 - 19/09/2027\n'
              'WINTER | 01/11/2027 - 07/11/2027 | '
              '08/11/2027 - 14/11/2027\n'
              'DRIVERS | 1234 SMITH | 5678 JONES\n'
              'DRIVERS | 9012 BROWN | 3456 TAYLOR',
        ],
      );

      expect(result.documentType, DocumentType.annualLeaveRoster);
      expect(result.canImport, isTrue);
      expect(result.annualLeaveAllocations, hasLength(4));

      final blockOne = result.annualLeaveAllocations
          .where((allocation) => allocation.blockNumber == 1)
          .toList();

      final blockTwo = result.annualLeaveAllocations
          .where((allocation) => allocation.blockNumber == 2)
          .toList();

      expect(
        blockOne.map((allocation) => allocation.driverNumber),
        containsAll(<String>['1234', '9012']),
      );

      expect(
        blockTwo.map((allocation) => allocation.driverNumber),
        containsAll(<String>['5678', '3456']),
      );

      final smith = result.annualLeaveAllocations.firstWhere(
        (allocation) => allocation.driverNumber == '1234',
      );

      expect(smith.surname, 'SMITH');
      expect(smith.leaveYear, 2027);
      expect(smith.depot, 'Birmingham');
      expect(smith.periods, hasLength(4));

      expect(
        smith.periodFor(AnnualLeavePeriodType.spring)?.startDate,
        DateTime(2027, 3, 1),
      );

      expect(
        smith.periodFor(AnnualLeavePeriodType.summerSecondWeek)?.endDate,
        DateTime(2027, 9, 12),
      );
    });

    test('blocks import when the leave year is missing', () async {
      const AnnualLeaveRosterParser parser = AnnualLeaveRosterParser();

      final result = await parser.parse(
        pageText: const <String>[
          'ANNUAL LEAVE ROSTER\n'
              'BLOCK | 1\n'
              'SPRING | 01/03/2027 - 07/03/2027\n'
              'DRIVERS | 1234 SMITH',
        ],
      );

      // A year is still detected from the seasonal date band.
      expect(result.canImport, isTrue);
      expect(result.annualLeaveAllocations.single.leaveYear, 2027);
    });

    test('blocks import when no block date bands are detected', () async {
      const AnnualLeaveRosterParser parser = AnnualLeaveRosterParser();

      final result = await parser.parse(
        pageText: const <String>[
          'ANNUAL LEAVE ROSTER 2027\n'
              'DRIVER 1234 SMITH',
        ],
      );

      expect(result.canImport, isFalse);
      expect(result.hasBlockingWarnings, isTrue);
    });
  });
}
