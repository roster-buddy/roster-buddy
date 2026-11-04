import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/notifications/shift_reminder_preferences.dart';
import 'package:roster_buddy/features/notifications/shift_reminder_link.dart';

void main() {
  testWidgets('multiple lead times can be selected without disabling finish check',
      (tester) async {
    Set<int> selected = {30};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) => SingleChildScrollView(child:
        ShiftReminderPreferences(selected: selected,
          onChanged: (next) => setState(() => selected = next))),
    ))));
    expect(find.byType(FilterChip), findsNWidgets(8));
    await tester.tap(find.text('15 mins'));
    await tester.pump();
    await tester.tap(find.text('2 hours'));
    await tester.pump();
    expect(selected, {15, 30, 120});
    await tester.tap(find.text('30 mins'));
    await tester.pump();
    expect(selected, {15, 120});
    expect(find.text('5 minutes after book-off'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  test('preferences allow no advance reminders and discard invalid values', () {
    expect(readShiftReminderMinutes([]), isEmpty);
    expect(readShiftReminderMinutes([15, 15, 45, 999, '30']), {15, 45});
    expect(readShiftReminderMinutes(null), {30});
  });

  test('notification links retain overnight shift date and reject invalid dates', () {
    expect(shiftReminderDate(Uri.parse('https://example.com/?shift=2026-11-04&bookOff=1')),
      DateTime(2026, 11, 4));
    expect(shiftReminderDate(Uri.parse('https://example.com/?shift=2026-02-31')), isNull);
    expect(shiftReminderDate(Uri.parse('https://example.com/?shift=bad')), isNull);
    expect(canEditShiftTimes(DateTime(2026,11,4), '17:11', '01:31', DateTime(2026,11,5,1,36)), isTrue);
    expect(canEditShiftTimes(DateTime(2026,11,4), '11:00', '19:00', DateTime(2026,11,5)), isFalse);
    expect(canEditShiftTimes(DateTime(2026,11,3), '17:11', '01:31', DateTime(2026,11,5)), isFalse);
  });
}
