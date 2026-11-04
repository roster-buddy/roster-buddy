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
}
