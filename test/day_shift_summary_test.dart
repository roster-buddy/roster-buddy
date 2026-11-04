import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/duty.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/features/authentication/home_screen.dart';

void main() {
  testWidgets('Edit times opens numeric input with Finish selected first',
      (tester) async {
    final today = DateTime.now();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: DayShiftSummary(
        date: today,
        annualLeave: false,
        duty: Duty(date: today, source: RosterSource.sevenDay,
          dutyType: DutyType.working, turnNumber: '215',
          bookOn: '17:11', bookOff: '01:31'),
        onChanged: () {},
      ),
    )));
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.text('Edit times'));
    await tester.pump();
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[1].focusNode!.hasFocus, isTrue);
    expect(fields[1].controller!.text, '0131');
    expect(fields[1].controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4));
    expect(fields[1].keyboardType, TextInputType.number);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(fields[0].focusNode!.hasFocus, isTrue);
    await tester.tap(find.byTooltip('Cancel time edit'));
    await tester.pump();
    expect(find.text('Edit times'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });
  testWidgets('status cards match rest, leave and review calendar colours',
      (tester) async {
    for (final entry in [
      (DutyType.restDay, const Color(0xFFB88700), 'Rest day'),
      (DutyType.annualLeave, const Color(0xFFD64545), 'Annual leave'),
      (DutyType.unknown, const Color(0xFF1769AA), 'Review duty'),
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DayShiftSummary(
        key: ValueKey(entry.$1),
        date: DateTime(2026, 11, 24), annualLeave: false,
        duty: Duty(date: DateTime(2026, 11, 24),
          source: RosterSource.sevenDay, dutyType: entry.$1,
          remarks: entry.$1 == DutyType.unknown ? 'Turn could not be identified' : null),
        onChanged: () {},
      ))));
      final card = tester.widget<Container>(find.byKey(const ValueKey('day-status-card')));
      final decoration = card.decoration! as BoxDecoration;
      expect((decoration.border! as Border).left.color, entry.$2);
      expect(find.text(entry.$3), findsOneWidget);
      if (entry.$1 == DutyType.annualLeave) {
        expect(find.byIcon(Icons.flight_takeoff), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      }
      if (entry.$1 == DutyType.unknown) {
        expect(find.text('Needs review'), findsOneWidget);
        expect(find.text('Turn could not be identified'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('missing roster stays neutral and leave hides underlying work',
      (tester) async {
    final date = DateTime(2026, 11, 7);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DayShiftSummary(
      key: const ValueKey('missing'), date: date, annualLeave: false,
      duty: null, onChanged: () {},
    ))));
    expect(find.text('No roster information'), findsOneWidget);
    expect(find.text('Needs review'), findsNothing);
    final card = tester.widget<Container>(find.byKey(const ValueKey('day-status-card')));
    expect(((card.decoration! as BoxDecoration).border! as Border).left.color,
      const Color(0xFF52667A));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DayShiftSummary(
      key: const ValueKey('leave'), date: date, annualLeave: true,
      duty: Duty(date: date, source: RosterSource.sevenDay,
        dutyType: DutyType.working, bookOn: '11:00', bookOff: '12:00'),
      onChanged: () {},
    ))));
    expect(find.text('Annual leave'), findsOneWidget);
    expect(find.byIcon(Icons.flight_takeoff), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

}
