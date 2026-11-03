import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/duty_code.dart';
import 'package:roster_buddy/core/services/roster_notification_text.dart';

void main() {
  test('compact allocated shift includes date, source, clocks and turn', () {
    expect(RosterNotificationText.title('2026-10-07', null, 'working', 'allocated'),
      'Shift allocated on 7/10/26');
    expect(RosterNotificationText.detail('7D', '11:00', '12:00', '215'), '7D 1100–1200 T215');
    expect(RosterNotificationText.detail('48HR', '23:30', '04:15', ''), '48HR 2330–0415');
  });
  test('all existing code meanings are available without a generic shift label', () {
    for (final code in DutyCodeLibrary.codes) {
      expect(RosterNotificationText.label(code.code, 'unknown'),
        code.code == 'TS' ? 'Safety brief' : code.preferredMeaning);
    }
    expect(RosterNotificationText.title('2026-10-07', 'MP', 'medical', 'changed'),
      'Medical updated on 7/10/26');
    expect(RosterNotificationText.title('2026-10-07', 'ALD', 'annual_leave', 'allocated'),
      'Annual leave allocated on 7/10/26');
    expect(RosterNotificationText.detail('7D', '—', '—', ''), '7D');
  });
  test('leave conflicts stay explicit and incomplete clocks are not shown as times', () {
    expect(RosterNotificationText.title('2026-10-07', 'TS', 'training', 'leave_conflict'),
      'Annual leave conflict on 7/10/26');
    expect(RosterNotificationText.detail('10D', '—', '12:00', '215'), '10D T215');
  });
}
