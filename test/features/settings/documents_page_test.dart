import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/settings/documents_page.dart';

void main() {
  testWidgets('documents open from a bottom sheet using a signed file URL', (tester) async {
    String? requestedPath;
    Uri? opened;
    await tester.pumpWidget(MaterialApp(home: DocumentsPage(
      loadPage: (_) async => [{
        'id': 'one', 'original_filename': 'Roster.pdf', 'storage_path': 'owner/roster.pdf',
        'created_at': '2026-10-30T16:00:00Z', 'detected_type': 'base_roster', 'processing_status': 'processed',
      }],
      signedUrl: (path) async { requestedPath = path; return 'https://example.test/signed-file'; },
      openDocument: (uri) async { opened = uri; return true; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roster.pdf'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Uploaded 30/10/2026'), findsOneWidget);
    expect(requestedPath, 'owner/roster.pdf');
    await tester.tap(find.text('Open document'));
    await tester.pumpAndSettle();
    expect(opened, Uri.parse('https://example.test/signed-file'));
  });

  testWidgets('failed document loading can be retried', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: DocumentsPage(loadPage: (_) async {
      calls++;
      if (calls == 1) throw StateError('Fixture network failure');
      return [];
    })));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.textContaining('No uploaded documents yet'), findsOneWidget);
  });
}
