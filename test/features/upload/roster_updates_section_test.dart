import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/services/roster_update_service.dart';
import 'package:roster_buddy/features/upload/roster_updates_section.dart';

void main() {
  final notices = [
    RosterUpdateNotice('2026-11-05', DateTime.utc(2026,11,2,10), '7D', '16:53', '01:11', '213', documentId: 'one'),
    RosterUpdateNotice('2026-11-06', DateTime.utc(2026,11,2,11), '48HR', '17:11', '01:31', '215', documentId: 'two'),
  ];
  testWidgets('updates display inline and only opened details are cleared', (tester) async {
    var unread = List<RosterUpdateNotice>.from(notices);
    var viewed = <RosterUpdateNotice>[];
    String? opened;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, update) =>
      Scaffold(body: RosterUpdatesSection(notices: unread,
        onViewed: (snapshot) async {
          viewed = snapshot;
          update(() => unread.removeWhere((n) => snapshot.contains(n)));
        },
        onOpenDocument: (notice) => opened = notice.documentId)))));
    expect(find.text(notices.first.title), findsOneWidget);
    expect(find.text(notices.last.title), findsOneWidget);
    expect(viewed, isEmpty);
    await tester.tap(find.text(notices.last.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open uploaded document'));
    expect(opened, 'two');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(viewed, [notices.last]);
    expect(find.text(notices.first.title), findsOneWidget);
    expect(find.text(notices.last.title), findsNothing);
  });
  testWidgets('clear all excludes investigation items', (tester) async {
    final conflict = RosterUpdateNotice('2026-11-07', DateTime.utc(2026,11,2,12),
      '7D', '12:00', '20:00', '216', needsInvestigation: true);
    var viewed = <RosterUpdateNotice>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      RosterUpdatesSection(notices: [...notices, conflict],
        onViewed: (snapshot) async => viewed = snapshot,
        onOpenDocument: (_) {}))));
    await tester.tap(find.text('Clear all roster updates'));
    await tester.pumpAndSettle();
    expect(viewed, notices);
    expect(viewed, isNot(contains(conflict)));
  });
  testWidgets('failed clear retains updates and offers retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      RosterUpdatesSection(notices: notices, onViewed: (_) async {
        calls++;
        if (calls == 1) throw StateError('offline');
      }, onOpenDocument: (_) {}))));
    await tester.tap(find.text('Clear all roster updates'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text(notices.first.title), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Retry'), findsNothing);
  });
}
