import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/duty.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/parse_result.dart';
import 'package:roster_buddy/core/models/parse_warning.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/features/smart_scan/scan_review_page.dart';
import 'package:roster_buddy/features/smart_scan/smart_scan_result.dart';
import 'package:roster_buddy/features/upload/upload_service.dart';

const pages = [
  SmartScanResult(fullText: '48-HOUR AMENDMENT\nDATE 03/08/2026', lines: []),
];

void main() {
  final upload = PickedUpload(
    bytes: Uint8List.fromList([1]),
    fileName: 'camera.jpg',
  );
  final parsed = ParseResult(
    documentType: DocumentType.fortyEightHourAmendment,
    duties: [
      Duty(
        date: DateTime(2026, 8, 3),
        source: RosterSource.fortyEightHour,
        dutyType: DutyType.working,
        turnNumber: '204',
        payrollNumber: '21910',
        bookOn: '04:25',
        bookOff: '12:58',
      ),
    ],
  );

  testWidgets('reviews dates and payroll before returning the exact import', (
    tester,
  ) async {
    ReviewedDocument? confirmed;
    var scans = 0;
    var parses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                confirmed = await Navigator.of(context).push<ReviewedDocument>(
                  MaterialPageRoute(
                    builder: (_) => ScanReviewPage(
                      upload: upload,
                      readDocument: (_) async {
                        scans++;
                        return pages;
                      },
                      parseDocument: (read, type, activation) async {
                        parses++;
                        expect(read, same(pages));
                        expect(type, DocumentType.fortyEightHourAmendment);
                        return parsed;
                      },
                    ),
                  ),
                );
              },
              child: const Text('Upload'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
    expect(find.text('48-Hour Amendment'), findsOneWidget);
    await tester.tap(find.text('Review records'));
    await tester.pumpAndSettle();
    expect(find.textContaining('03/08/2026'), findsWidgets);
    expect(find.textContaining('21910'), findsOneWidget);
    expect(confirmed, isNull);
    await tester.tap(find.text('Import records'));
    await tester.pumpAndSettle();
    expect(confirmed!.result, same(parsed));
    expect(scans, 1);
    expect(parses, 1);
  });

  testWidgets('blocking parser warnings prevent import', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScanReviewPage(
          upload: upload,
          readDocument: (_) async => pages,
          parseDocument: (_, type, activation) async => parsed.copyWith(
            warnings: const [
              ParseWarning(
                message: 'Date is ambiguous',
                severity: ParseWarningSeverity.blocking,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review records'));
    await tester.pumpAndSettle();
    expect(find.text('Date is ambiguous'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Import records'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('failed recognition can retry without importing or parsing', (
    tester,
  ) async {
    var scans = 0;
    var parses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ScanReviewPage(
          upload: upload,
          readDocument: (_) async {
            if (++scans == 1) throw StateError('Fixture read failure');
            return pages;
          },
          parseDocument: (_, type, activation) async {
            parses++;
            return parsed;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry scan'), findsOneWidget);
    await tester.tap(find.text('Retry scan'));
    await tester.pumpAndSettle();
    expect(find.text('48-Hour Amendment'), findsOneWidget);
    expect(scans, 2);
    expect(parses, 0);
  });

  testWidgets('empty scan cannot proceed to a calendar import', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScanReviewPage(
          upload: upload,
          readDocument: (_) async => const [
            SmartScanResult(fullText: '', lines: []),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No readable text'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review records'),
          )
          .onPressed,
      isNull,
    );
  });
}
