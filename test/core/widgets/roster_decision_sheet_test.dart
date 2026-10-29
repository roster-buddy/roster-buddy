import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/widgets/roster_decision_sheet.dart';

void main() {
  testWidgets('approval uses bottom sheet and preserves email callback', (tester) async {
    bool? choice;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        choice = await showRosterDecisionSheet<bool>(
          context: context,
          builder: (sheetContext) => RosterDecisionSheet(
            title: const Text('Annual leave confirmed?'),
            content: const Text('Approved by Rosters / DTCM?'),
            actions: [
              CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, false), child: const Text('No')),
              CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, true), child: const Text('Yes')),
            ],
          ),
        );
      }, child: const Text('Open'))),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(choice, isFalse);
  });
}
