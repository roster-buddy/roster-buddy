import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/parse_warning.dart';
import 'package:roster_buddy/core/parser/daily_amendment_parser.dart';
import 'package:roster_buddy/features/smart_scan/scan_import_policy.dart';
import 'package:roster_buddy/features/smart_scan/smart_scan_result.dart';
import 'package:roster_buddy/features/upload/scan_upload_summary.dart';

void main() {
  const text = '7DAY\nReport for Saturday 28/11/26 in All Links\n'
      'S Rees 0184 WOD ND\nD Guest 3685 WOD NDNA';
  const page = SmartScanResult(fullText: text, lines: []);
  test('only complete clean sheets qualify for automatic import', () async {
    final result = await DailyAmendmentParser(
      documentType: DocumentType.sevenDayAmendment,
    ).parse(pageText: [text]);
    expect(ScanImportPolicy.allRowsRead(result, [page]), isTrue);
    expect(ScanImportPolicy.allRowsRead(result.copyWith(
      duties: [result.duties.first]), [page]), isFalse);
    expect(ScanImportPolicy.allRowsRead(result.copyWith(warnings: const [
      ParseWarning(message: 'Check a row'),
    ]), [page]), isFalse);
    expect(ScanImportPolicy.allRowsRead(result, [
      const SmartScanResult(fullText: text, lines: [], confidence: 40),
    ]), isFalse);
    expect(ScanImportPolicy.allRowsRead(result, [
      const SmartScanResult(fullText: text, lines: [], documentHeading: '48HR'),
    ]), isTrue);
    expect(ScanImportPolicy.allRowsRead(result, [
      const SmartScanResult(fullText: 'Report for Saturday 28/11/26 in All Links\n'
        'S Rees 0184 WOD ND\nD Guest 3685 WOD NDNA', lines: []),
    ]), isTrue);
    expect(
      ScanImportPolicy.allRowsRead(result, [
        const SmartScanResult(
          fullText: text,
          lines: [
            SmartScanTextLine(
              text: 'S Rees 0184 WOD ND',
              left: 0,
              top: 0,
              right: 200,
              bottom: 12,
            ),
            SmartScanTextLine(
              text: 'D Guest 368S WOD NDNA',
              left: 0,
              top: 20,
              right: 220,
              bottom: 32,
            ),
          ],
        ),
      ]),
      isTrue,
      reason:
          'a poorer positioned-word reading must not add a phantom review row',
    );
    expect(ScanImportPolicy.reviewReasons(result, [
      const SmartScanResult(fullText: text, lines: [], confidence: 40),
    ]).join(' '), contains('text recognition is uncertain'));
    expect(ScanImportPolicy.reviewReasons(result.copyWith(
      duties: [result.duties.first]), [page]).join(' '),
      contains('2 payroll rows detected, 1 shift records read'));
    final missingRows = ScanImportPolicy.unmatchedRows(
      result.copyWith(duties: [result.duties.first]),
      [page],
    );
    expect(missingRows, hasLength(1));
    expect(missingRows.single.message, contains('D Guest 3685 WOD NDNA'));
    expect(ScanImportPolicy.allRowsRead(result.copyWith(duties: [
      result.duties.first.copyWith(payrollNumber: '9999'),
      result.duties.last,
    ]), [page]), isFalse);
    final linkedFullPayroll = result.copyWith(duties: [
      result.duties.first,
      result.duties.last.copyWith(payrollNumber: '23685'),
    ]);
    expect(
      ScanImportPolicy.allRowsRead(linkedFullPayroll, [page]),
      isTrue,
      reason: 'a full profile payroll must match its four-digit printed pay number',
    );
    expect(
      ScanImportPolicy.unmatchedRows(linkedFullPayroll, [page]),
      isEmpty,
    );
    const mixedPayrolls = SmartScanResult(
      fullText: 'A One 1001 WOD ND\nB Two 1002 WOD ND\nC Three 1003 WOD ND\n'
          'D Four 1004 WOD ND\nE Five 100005 WOD ND',
      lines: [],
    );
    expect(
      ScanImportPolicy.reviewReasons(result, [mixedPayrolls]).join(' '),
      contains('different length from the rest'),
    );
    expect(ScanUploadSummary.title(result, 'Amendment'), '28/11/26 7 Day Sheet');
    expect(ScanUploadSummary.message(result, 2, 'Reviewed'), 'Reviewed');
    expect(ScanUploadSummary.message(result.copyWith(allRowsRead: true), 2, ''),
      'All 2 rows read and applied');
    expect(ScanUploadSummary.message(result.copyWith(allRowsRead: true), 1, 'Partial'),
      'Partial');
  });
}
