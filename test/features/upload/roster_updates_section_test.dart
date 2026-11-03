import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/services/roster_update_service.dart';
import 'package:roster_buddy/features/upload/roster_updates_section.dart';
import 'package:roster_buddy/features/upload/roster_update_card.dart';

void main() {
  final notices = [
    RosterUpdateNotice('2026-11-05', DateTime.utc(2026,11,2,10), '7D', '16:53', '01:11', '213', documentId: 'one'),
    RosterUpdateNotice('2026-11-06', DateTime.utc(2026,11,2,11), '48HR', '17:11', '01:31', '215', documentId: 'two'),
  ];
  testWidgets('opening the group views the snapshot together and clears the section', (tester) async {
    var unread = List<RosterUpdateNotice>.from(notices);
    var viewed = <RosterUpdateNotice>[];
    String? opened;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, update) =>
      Scaffold(body: RosterUpdatesSection(notices: unread,
        onViewed: (snapshot) async { viewed = snapshot; update(() => unread = []); },
        onOpenDocument: (notice) => opened = notice.documentId)))));
    expect(find.byType(RosterUpdateCard), findsNothing);
    await tester.tap(find.text('Roster updates'));
    await tester.pumpAndSettle();
    expect(viewed, notices);
    expect(find.byType(RosterUpdateCard), findsNWidgets(2));
    await tester.tap(find.text('Open uploaded document').first);
    expect(opened, 'one');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Roster updates'), findsNothing);
  });
  testWidgets('failed read-state save offers retry and retains the updates', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      RosterUpdatesSection(notices: notices, onViewed: (_) async {
        calls++;
        if (calls == 1) throw StateError('offline');
      }, onOpenDocument: (_) {}))));
    await tester.tap(find.text('Roster updates'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(RosterUpdateCard), findsNWidgets(2));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Retry'), findsNothing);
  });
}
