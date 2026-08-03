import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/job_card.dart';
import 'package:roster_buddy/core/parser/job_card_parser.dart';

void main() {
  group('JobCardParser', () {
    test('recognises Job Card text', () {
      const JobCardParser parser = JobCardParser();

      expect(
        parser.canParse(<String>[
          'JOB CARD\nWO201\nDAY CODE SX\nBOOK ON 06:00\nBOOK OFF 14:00',
        ]),
        isTrue,
      );
    });

    test('extracts a weekday LTP Job Card', () async {
      const JobCardParser parser = JobCardParser();

      final result = await parser.parse(
        pageText: <String>[
          '''
JOB CARD
WO201
DAY CODE: SX
LTP
VALID FROM 01/05/2026 TO 12/12/2026
BOOK ON 06:00
BOOK OFF 14:00
ROSTERED HOURS 08:00
Prepare train at Birmingham New Street
Work 1A01 to London Euston
Meal break
''',
        ],
      );

      expect(result.documentType, DocumentType.jobCard);
      expect(result.hasBlockingWarnings, isFalse);
      expect(result.jobCards, hasLength(1));

      final JobCard card = result.jobCards.single;

      expect(card.turnNumber, '201');
      expect(card.originalTurnCode, 'WO201');
      expect(card.dayCode, 'SX');
      expect(card.planType, JobCardPlanType.ltp);
      expect(card.validFrom, DateTime(2026, 5, 1));
      expect(card.validTo, DateTime(2026, 12, 12));
      expect(card.bookOn, '06:00');
      expect(card.bookOff, '14:00');
      expect(card.rosteredMinutes, 480);
      expect(card.pageNumber, 1);
      expect(card.appliesOnWeekday(DateTime.monday), isTrue);
      expect(card.appliesOnWeekday(DateTime.saturday), isFalse);
    });

    test('extracts multiple Job Cards from one page', () async {
      const JobCardParser parser = JobCardParser();

      final result = await parser.parse(
        pageText: <String>[
          '''
WO202
DAY CODE SX
LTP
VALID 01/05/2026 TO 12/12/2026
BOOK ON 07:00
BOOK OFF 15:00

WO301
DAY CODE SO
STP
VALID 01/05/2026 TO 12/12/2026
BOOK ON 08:00
BOOK OFF 16:00
''',
        ],
      );

      expect(result.jobCards, hasLength(2));
      expect(result.jobCards[0].turnNumber, '202');
      expect(result.jobCards[0].dayCode, 'SX');
      expect(result.jobCards[1].turnNumber, '301');
      expect(result.jobCards[1].dayCode, 'SO');
      expect(result.jobCards[1].planType, JobCardPlanType.stp);
    });

    test('blocks import when required fields are missing', () async {
      const JobCardParser parser = JobCardParser();

      final result = await parser.parse(
        pageText: <String>['JOB CARD\nWO201\nBOOK ON 06:00\nBOOK OFF 14:00'],
      );

      expect(result.jobCards, isEmpty);
      expect(result.hasBlockingWarnings, isTrue);
    });
  });
}
