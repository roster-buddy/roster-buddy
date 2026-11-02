import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/services/roster_update_service.dart';
import 'package:roster_buddy/features/upload/roster_update_card.dart';
void main() {
  testWidgets('a conflict always offers allocation even when imported clocks need correction', (tester) async {
    var tapped = 0;
    final notice = RosterUpdateNotice('2026-11-05', DateTime(2026,11,2), '7D', '—', '01:11', '213',
      needsInvestigation: true, documentId: 'sheet');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      RosterUpdateCard(notice: notice, onOpenDocument: () {}, onUseShift: () { tapped++; })))));
    await tester.tap(find.text('Use rostered shift'));
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });
}
