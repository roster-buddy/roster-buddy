import 'dart:typed_data';
import 'package:roster_buddy/core/parser/daily_amendment_parser.dart';
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
  SmartScanResult(
    fullText: '48-HOUR AMENDMENT\nDATE 03/08/2026\n'
        'Alex Example 1910 WOD 204 04:25 12:58',
    lines: [],
  ),
];

Future<void> chooseType(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

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
        driverName: 'Alex Example',
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
    expect(find.widgetWithText(FilledButton, '48-Hour Amendment'), findsOneWidget);
    await chooseType(tester, '48-Hour Amendment');
    expect(find.text('1 records found'), findsOneWidget);
    expect(find.textContaining('records to review'), findsNothing);
    expect(confirmed, isNull);
    await tester.tap(find.text('Import records'));
    await tester.pumpAndSettle();
    expect(confirmed!.result, same(parsed));
    expect(scans, 1);
    expect(parses, 1);
  });

  testWidgets('selecting Base Roster opens depot publication setup immediately', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ScanReviewPage(
        upload: upload,
        readDocument: (_) async => pages,
        parseDocument: (_, _, _) async {
          fail('Parsing must wait for the official commencement date');
        },
      ),
    ));
    await tester.pumpAndSettle();
    await chooseType(tester, 'Base Roster');
    expect(
      find.widgetWithText(FilledButton, 'Publish Base Roster'),
      findsOneWidget,
    );
    expect(find.text('Select commencement Sunday'), findsOneWidget);
    expect(find.text('Your printed week number'), findsNothing);
    expect(find.text('Mutual permanent swap'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Base Roster'), findsOneWidget);
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
    await chooseType(tester, '48-Hour Amendment');
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
    expect(find.widgetWithText(FilledButton, '48-Hour Amendment'), findsOneWidget);
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
    expect(find.widgetWithText(FilledButton, '48-Hour Amendment'), findsNothing);
    expect(find.text('Import records'), findsNothing);
  });
  testWidgets('unreadable rows require an explicit exclusion choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScanReviewPage(
          upload: upload,
          readDocument: (_) async => pages,
          parseDocument: (_, type, activation) async => parsed.copyWith(
            warnings: const [
              ParseWarning(
                message:
                    'A roster row could not be read safely on page 1: unreadable',
                severity: ParseWarningSeverity.blocking,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await chooseType(tester, '48-Hour Amendment');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Import records'),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Import records'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('missing own shift can be entered and checked before import', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScanReviewPage(
          upload: upload,
          readDocument: (_) async => pages,
          parseDocument: (_, type, activation) async => parsed.copyWith(
            duties: parsed.duties
                .map((d) => d.copyWith(payrollNumber: '1104'))
                .toList(),
            payrollNumber: '21910',
            ownRecordCount: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await chooseType(tester, '48-Hour Amendment');
    await tester.ensureVisible(find.text('Add missing shift'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add missing shift'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '05/11/2026');
    await tester.enterText(fields.at(1), '21910');
    await tester.enterText(fields.at(2), 'TW');
    await tester.enterText(fields.at(3), '1653');
    await tester.tap(find.text('Use these values'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('1 records match your calendar.'),
      -100,
    );
    expect(find.text('1 records match your calendar.'), findsOneWidget);
  });

  testWidgets('clean sheet waits for manual type choice then applies exactly once', (tester) async {
    ReviewedDocument? confirmed;
    var parses = 0;
    const text = 'Report for Saturday 28/11/26 in All Links\nS Rees 0184 WOD ND';
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(child: const Text('Start'), onPressed: () async {
        confirmed = await Navigator.of(context).push<ReviewedDocument>(
          MaterialPageRoute(builder: (_) => ScanReviewPage(
            upload: upload,
            readDocument: (_) async => const [SmartScanResult(
              fullText: text, lines: [], documentHeading: '7DAY')],
            parseDocument: (read, type, activation) async {
              parses++;
              return DailyAmendmentParser(documentType: type).parse(pageText: [text]);
            },
          )));
      })))));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
    expect(parses, 0);
    await chooseType(tester, '7-Day Amendment');
    expect(confirmed, isNotNull);
    expect(confirmed!.result.allRowsRead, isTrue);
    expect(confirmed!.type, DocumentType.sevenDayAmendment);
    expect(parses, 1);
  });

  testWidgets('uncertain rows remain on review after automatic checks', (tester) async {
    const text = '7DAY\nReport for Saturday 28/11/26 in All Links\n'
        'S Rees 0184 WOD unreadable';
    await tester.pumpWidget(MaterialApp(home: ScanReviewPage(
      upload: upload,
      readDocument: (_) async => const [SmartScanResult(fullText: text, lines: [])],
      parseDocument: (_, type, activation) =>
          DailyAmendmentParser(documentType: type).parse(pageText: [text]),
    )));
    await tester.pumpAndSettle();
    await chooseType(tester, '7-Day Amendment');
    expect(find.text('Tap to correct this row'), findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import records')).onPressed, isNull);
  });

  test('unresolved row suggestions keep the printed turn and shift times', () {
    final parser = DailyAmendmentParser(
      documentType: DocumentType.sevenDayAmendment,
    );
    final row = parser.reviewRow(
      'R Driver 3686 WOD TW TW 05:00 13:45 8.45',
      pageText: 'Report for Saturday 21/11/26 in All Links',
      date: DateTime(2026, 11, 20),
      pageNumber: 2,
    )!;
    expect(row.date, DateTime(2026, 11, 21));
    expect(row.payrollNumber, '3686');
    expect(row.turnNumber, 'TW');
    expect(row.bookOn, '05:00');
    expect(row.bookOff, '13:45');
    expect(row.pageNumber, 2);
  });

  testWidgets('count mismatch shows only unresolved rows', (tester) async {
    const text = '7DAY\nReport for Saturday 28/11/26 in All Links\n'
        'S Rees 0184 WOD ND\nD Guest 3685 WOD NDNA';
    final partial = await DailyAmendmentParser(
      documentType: DocumentType.sevenDayAmendment,
    ).parse(pageText: [text]);
    await tester.pumpWidget(MaterialApp(home: ScanReviewPage(
      upload: upload,
      readDocument: (_) async => const [
        SmartScanResult(fullText: text, lines: []),
      ],
      parseDocument: (_, type, activation) async => partial.copyWith(
        duties: [partial.duties.first],
      ),
    )));
    await tester.pumpAndSettle();
    await chooseType(tester, '7-Day Amendment');
    expect(find.textContaining('1 rows need correction'), findsOneWidget);
    expect(find.textContaining('D Guest 3685 WOD NDNA'), findsOneWidget);
    expect(find.textContaining('S Rees · Payroll 0184'), findsNothing);
  });
}

