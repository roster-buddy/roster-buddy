import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/core/parser/base_roster_parser.dart';

void main() {
  group('BaseRosterParser', () {
    const String headings =
        'WEEK | SUNDAY | MONDAY | TUESDAY | WEDNESDAY | THURSDAY | FRIDAY';

    const String weekOne =
        '1 | 06:00 | 14:00 | 08:00 | 201 '
        '| RD | | | '
        '| 07:00 | 15:00 | 08:00 | 202 '
        '| 08:00 | 16:00 | 08:00 | 203 '
        '| 09:00 | 17:00 | 08:00 | 204 '
        '| 10:00 | 18:00 | 08:00 | 205';

    const String weekOneIdentity =
        '1234 | EARLY | REST | EARLY | EARLY | EARLY | EARLY';

    const String weekTwo =
        '2 | 12:00 | 20:00 | 08:00 | 211 '
        '| 13:00 | 21:00 | 08:00 | 212 '
        '| RD | | | '
        '| 14:00 | 22:00 | 08:00 | 213 '
        '| 15:00 | 23:00 | 08:00 | 214 '
        '| 16:00 | 00:00 | 08:00 | 215';

    const String weekTwoIdentity =
        '5678 | LATE | LATE | REST | LATE | LATE | LATE';

    test('recognises a Base Roster grid', () {
      const BaseRosterParser parser = BaseRosterParser();

      expect(
        parser.canParse(<String>['$headings\n$weekOne\n$weekOneIdentity']),
        isTrue,
      );
    });

    test(
      'extracts Sunday to Friday and advances one roster row per week',
      () async {
        final BaseRosterParser parser = BaseRosterParser(
          commencementDate: DateTime(2026, 5, 3),
          rosterNumber: '1234',
        );

        final result = await parser.parse(
          pageText: <String>[
            '$headings\n'
                '$weekOne\n'
                '$weekOneIdentity\n'
                '$weekTwo\n'
                '$weekTwoIdentity',
          ],
        );

        expect(result.documentType, DocumentType.baseRoster);
        expect(result.driverFound, isTrue);
        expect(result.driverNumber, '1234');
        expect(result.weeksDetected, 2);
        expect(result.hasBlockingWarnings, isFalse);
        expect(result.duties, hasLength(12));

        final sundayWeekOne = result.duties.firstWhere(
          (duty) => duty.date == DateTime(2026, 5, 3),
        );

        expect(sundayWeekOne.source, RosterSource.baseRoster);
        expect(sundayWeekOne.dutyType, DutyType.working);
        expect(sundayWeekOne.turnNumber, '201');
        expect(sundayWeekOne.bookOn, '06:00');
        expect(sundayWeekOne.bookOff, '14:00');
        expect(sundayWeekOne.rosteredMinutes, 480);
        expect(sundayWeekOne.driverNumber, '1234');

        final mondayWeekOne = result.duties.firstWhere(
          (duty) => duty.date == DateTime(2026, 5, 4),
        );

        expect(mondayWeekOne.dutyType, DutyType.restDay);

        final sundayWeekTwo = result.duties.firstWhere(
          (duty) => duty.date == DateTime(2026, 5, 10),
        );

        expect(sundayWeekTwo.turnNumber, '211');
        expect(sundayWeekTwo.bookOn, '12:00');
        expect(sundayWeekTwo.bookOff, '20:00');
      },
    );

    test('blocks import when the roster number is not found', () async {
      final BaseRosterParser parser = BaseRosterParser(
        commencementDate: DateTime(2026, 5, 3),
        rosterNumber: '9999',
      );

      final result = await parser.parse(
        pageText: <String>['$headings\n$weekOne\n$weekOneIdentity'],
      );

      expect(result.driverFound, isFalse);
      expect(result.duties, isEmpty);
      expect(result.hasBlockingWarnings, isTrue);
      expect(
        result.warnings.any(
          (warning) => warning.message.contains('9999 was not found'),
        ),
        isTrue,
      );
    });

    test('blocks import when commencement date is not Sunday', () async {
      final BaseRosterParser parser = BaseRosterParser(
        commencementDate: DateTime(2026, 5, 4),
        rosterNumber: '1234',
      );

      final result = await parser.parse(
        pageText: <String>['$headings\n$weekOne\n$weekOneIdentity'],
      );

      expect(result.duties, isEmpty);
      expect(result.hasBlockingWarnings, isTrue);
      expect(
        result.warnings.any(
          (warning) => warning.message.contains('must be a Sunday'),
        ),
        isTrue,
      );
    });
  });
}
