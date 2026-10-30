import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/parser/document_classifier.dart';

void main() {
  const classifier = DocumentClassifier();
  test('Wolverhampton depot does not turn a Base Roster into a Job Card', () {
    expect(classifier.classify(['WOLVERHAMPTON BASE ROSTER\nWEEK SUN MON TUE WED THU FRI SAT']), DocumentType.baseRoster);
    expect(classifier.classify(['WOLVERHAMPTON notice']), DocumentType.unknown);
  });
  test('amendment heading takes priority over annual leave in a row', () {
    for (final entry in {
      '10-DAY': DocumentType.tenDayAmendment,
      '7 DAY': DocumentType.sevenDayAmendment,
      '48-HOUR': DocumentType.fortyEightHourAmendment,
    }.entries) {
      expect(classifier.classify(['${entry.key} AMENDMENT\nMOORE WOLVERHAMPTON ANNUAL LEAVE']), entry.value);
    }
  });
  test('recognises both explicit and turn/day Job Card layouts', () {
    expect(classifier.classify(['JOB CARD\nWO201\nDAY CODE SX']), DocumentType.jobCard);
    expect(classifier.classify(['WO301\nDAY CODE SO\nBOOK ON 08:00']), DocumentType.jobCard);
    expect(classifier.classify(['W0201\nDAY: SX\nANNUAL LEAVE cover']), DocumentType.jobCard);
  });
  test('Sunday duties are 48-Hour while a Sunday Job Card remains a card', () {
    expect(classifier.classify(['SUNDAY DUTIES\nWOLVERHAMPTON']), DocumentType.fortyEightHourAmendment);
    expect(classifier.classify(['JOB CARD WO201\nDAY CODE SUN']), DocumentType.jobCard);
  });
  test('annual leave and unreadable input keep distinct types', () {
    expect(classifier.classify(['ANNUAL LEAVE ROSTER 2027']), DocumentType.annualLeaveRoster);
    expect(classifier.classify([]), DocumentType.unknown);
    expect(classifier.classify(['   ']), DocumentType.unknown);
  });
}
