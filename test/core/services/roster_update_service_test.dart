import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/services/roster_update_service.dart';

void main() {
  Map<String, dynamic> row(String payroll, String at, {String source = '7_day'}) => {
    'payroll_number': payroll, 'created_at': at, 'source': source,
    'duty_date': '2026-11-05', 'book_on': '16:53:00',
    'book_off': '01:11:00', 'turn_number': '213',
  };
  test('notices include only own unseen amendment rows and keep the newest duplicate', () {
    final notices = RosterUpdateService.fromRows([
      row('2319', '2026-11-02T10:00:00Z'),
      row('52319', '2026-11-02T11:00:00Z'),
      row('2320', '2026-11-02T12:00:00Z'),
      row('2319', '2026-11-01T10:00:00Z'),
      row('2319', '2026-11-02T12:00:00Z', source: 'base_roster'),
    ], payrollNumber: '52319', since: DateTime.utc(2026, 11, 2));
    expect(notices, hasLength(1));
    expect(notices.single.receivedAt, DateTime.utc(2026, 11, 2, 11));
    expect(notices.single.detail, '7D 1653–0111 T213');
  });
  test('seen or invalid identifiers do not create another alert', () {
    final notices = RosterUpdateService.fromRows([
      row('2319', '2026-11-02T11:00:00Z'),
      row('319', '2026-11-02T12:00:00Z'),
    ], payrollNumber: '52319', since: DateTime.utc(2026, 11, 2, 11));
    expect(notices, isEmpty);
  });
  test('every amendment source warns for work on recorded leave and retains its document link', () {
    final rows = [
      for (final source in ['10_day', '7_day', '48_hour'])
        {...row('2319', '2026-11-02T12:00:00Z', source: source),
          'duty_type': 'working', 'document_id': 'sheet-$source'},
    ];
    final notices = RosterUpdateService.fromRows(rows, payrollNumber: '52319',
      since: DateTime.utc(2026, 11, 2), annualLeaveDates: {'2026-11-05'});
    expect(notices, hasLength(3));
    expect(notices.every((n) => n.needsInvestigation && n.documentId != null), isTrue);
  });
  test('a leave-coded sheet or a day without recorded leave does not raise a conflict', () {
    final leave = {...row('2319', '2026-11-02T12:00:00Z'), 'duty_type': 'annual_leave'};
    expect(RosterUpdateService.fromRows([leave], payrollNumber: '52319',
      since: DateTime.utc(2026, 11, 2), annualLeaveDates: {'2026-11-05'}).single.needsInvestigation, isFalse);
    expect(RosterUpdateService.fromRows([{...leave, 'duty_type': 'working'}], payrollNumber: '52319',
      since: DateTime.utc(2026, 11, 2)).single.needsInvestigation, isFalse);
  });

  test('allocating a conflict retains the sheet type, turn and overnight hours', () {
    final notice = RosterUpdateNotice('2026-11-05', DateTime.utc(2026, 11, 2), '7D',
      '16:53', '01:11', '213', dutyType: 'training');
    final duty = notice.rosteredDuty!;
    expect(duty.date, DateTime(2026, 11, 5));
    expect(duty.dutyType, DutyType.training);
    expect(duty.turnNumber, '213');
    expect(duty.bookOn, '16:53');
    expect(duty.bookOff, '01:11');
    expect(duty.rosteredMinutes, 498);
    expect(RosterUpdateNotice('2026-11-05', DateTime.utc(2026, 11, 2), '7D',
      '—', '01:11', '213').rosteredDuty, isNull);
  });

  test('notice keeps the code label and server change kind', () {
    final notices = RosterUpdateService.fromRows([{
      ...row('2319', '2026-11-02T12:00:00Z'),
      'document_id': 'sheet', 'duty_type': 'training', 'amendment_code': 'TS',
    }], payrollNumber: '52319', since: DateTime.utc(2026, 11, 2),
      eventKinds: {'sheet|2026-11-05': 'changed'});
    expect(notices.single.title, 'Safety brief updated on 5/11/26');
    expect(notices.single.detail, '7D 1653–0111 T213');
  });

}
