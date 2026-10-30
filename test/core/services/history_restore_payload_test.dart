import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/duty.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/core/services/duty_history_service.dart';

void main() {
  test('pending cancellation preserves selected overnight shift and prior leave', () {
    final date = DateTime(2026, 11, 25);
    final selected = Duty(date: date, source: RosterSource.sevenDay,
      dutyType: DutyType.working, turnNumber: '204', bookOn: '22:15', bookOff: '06:30',
      rosteredMinutes: 495);
    final leave = Duty(date: date, source: RosterSource.annualLeave,
      dutyType: DutyType.annualLeave);
    final payload = DutyHistoryService.restorationPayload(selected, leave);
    expect(payload['duty_date'], '2026-11-25');
    expect(payload['duty_type'], 'working');
    expect(payload['turn_number'], '204');
    expect(payload['book_on'], '22:15');
    expect(payload['book_off'], '06:30');
    expect(payload['rostered_minutes'], 495);
    expect(payload['original_duty_type'], 'annual_leave');
    expect(payload['original_source'], 'annualLeave');
    expect(payload.containsKey('user_id'), isFalse);
  });
}
