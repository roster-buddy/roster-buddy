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
  SmartScanResult(fullText: '48-HOUR AMENDMENT\nDATE 03/08/2026', lines: []),
];

Future<void> chooseType(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<DocumentType>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
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
    expect(find.text('48-Hour Amendment'), findsNothing);
    await chooseType(tester, '48-Hour Amendment');
    await tester.tap(find.text('Check and apply'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('03/08/2026').first, 150);
    await tester.pumpAndSettle();
    expect(find.textContaining('03/08/2026'), findsWidgets);
    expect(find.textContaining('21910'), findsOneWidget);
    expect(find.textContaining('Alex Example · Payroll 21910'), findsOneWidget);
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
    await chooseType(tester, '48-Hour Amendment');
    await tester.tap(find.text('Check and apply'));
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
    expect(find.text('48-Hour Amendment'), findsNothing);
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
            find.widgetWithText(FilledButton, 'Check and apply'),
          )
          .onPressed,
      isNull,
    );
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
    await tester.tap(find.text('Check and apply'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('Check and apply'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add missing shift'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add missing shift'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '05/11/2026');
    await tester.enterText(fields.at(1), '21910');
    await tester.enterText(fields.at(2), '213');
    await tester.enterText(fields.at(3), '16:53');
    await tester.enterText(fields.at(4), '01:11');
    await tester.tap(find.text('Use these values'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('1 records match your calendar.'),
      -100,
    );
    expect(find.text('1 records match your calendar.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('05/11/2026').first,
      100,
    );
    expect(find.textContaining('16:53–01:11'), findsOneWidget);
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
    await tester.tap(find.text('Check and apply'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('Check and apply'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to correct this row'), findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import records')).onPressed, isNull);
  });
}
