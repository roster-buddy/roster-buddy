import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/upload/day_document_links.dart';

void main() {
  testWidgets('day popup opens a shared sheet in one tap without another confirmation', (tester) async {
    var opened = 0;
    DateTime? requested;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DayDocumentLinks(
      date: DateTime(2026, 11, 5),
      loadDocuments: (date) async {
        requested = date;
        return [{'id': 'sheet', 'detected_type': '7_day_amendment', 'original_filename': 'roster.jpg', 'storage_path': 'shared/roster.jpg'}];
      },
      openDocument: (_) async { opened++; },
    )))));
    await tester.pumpAndSettle();
    expect(requested, DateTime(2026, 11, 5));
    expect(find.text('7-day sheet'), findsOneWidget);
    await tester.tap(find.text('7-day sheet'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Open document'), findsNothing);
  });
}
