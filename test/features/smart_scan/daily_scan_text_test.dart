import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/parser/daily_amendment_parser.dart';
import 'package:roster_buddy/features/smart_scan/daily_scan_text.dart';
import 'package:roster_buddy/features/smart_scan/smart_scan_result.dart';
import 'package:roster_buddy/features/smart_scan/smart_scan_page_text_reconstructor.dart';

void main() {
  const type = DocumentType.sevenDayAmendment;
  const heading = '7DAY Report for Monday 09/11/26 in All Links';
  SmartScanTextLine line(String text, double x, double y) =>
      SmartScanTextLine(text: text, left: x, top: y, right: x + 180, bottom: y + 10);
  SmartScanResult skewed(String native, {bool firstComplete = false}) => SmartScanResult(
    fullText: native, lines: [
      line(heading, 0, 20),
      line(firstComplete ? 'B Moore 1910 WOD 208 08:11 17:10 8.59' : 'B Moore 1910 WOD', 0, 100),
      if (!firstComplete) line('208 08:11 17:10 8.59', 300, 117),
      line('D Derry 2001 WOD ALLOC 211', 0, 140),
      line('15:11 01:01 8.45 Amended Turn', 300, 157),
    ]);
  test('preserves native table rows when slanted word positions split times', () async {
    final page = skewed('$heading\nB Moore 1910 WOD 208 08:11 17:10 8.59\n'
      'D Derry 2001 WOD ALLOC 211 15:11 01:01 8.45 Amended Turn');
    final parser = DailyAmendmentParser(documentType: type);
    final broken = await parser.parse(pageText: [SmartScanPageTextReconstructor.reconstruct(page)]);
    // The second row may already be recoverable, but the first row loses its clocks.
    expect(broken.canImport, isFalse);
    final chosen = await DailyScanText.bestPages([page], type);
    final result = await parser.parse(pageText: chosen);
    expect(chosen.single, page.fullText);
    expect(result.canImport, isTrue);
    expect(result.duties.length, 2);
    expect(result.duties.first.bookOn, '08:11');
    expect(result.duties.first.bookOff, '17:10');
    expect(result.duties.last.bookOff, '01:01');
  });
  test('does not switch to text that drops a named payroll row', () async {
    final page = skewed('$heading\nB Moore 1910 WOD 208 08:11 17:10 8.59');
    final chosen = await DailyScanText.bestPages([page], type);
    final result = await DailyAmendmentParser(
      documentType: type,
    ).parse(pageText: chosen);
    expect(result.duties.map((d) => d.payrollNumber).toSet(), {'1910', '2001'});
  });
  test('uses native rows when they add safe duties without reducing warnings', () async {
    final page = SmartScanResult(
      fullText: '$heading\n'
          'B Moore 1910 WOD 208 08:11 17:10 8.59\n'
          'D Derry 2001 WOD ZS ZS',
      lines: [
        line(heading, 0, 20),
        line('B Moore 1910 WOD 208 08:11 17:10 8.59', 0, 100),
        line('D 2001 WOD ZS ZS', 0, 140),
      ],
    );
    final chosen = await DailyScanText.bestPages([page], type);
    expect(chosen.single, page.fullText);
    final result = await DailyAmendmentParser(
      documentType: type,
    ).parse(pageText: chosen);
    expect(result.duties, hasLength(2));
    expect(result.duties.last.driverName, 'D Derry');
  });
  test('does not replace an already-read shift with conflicting times', () async {
    final page = skewed('$heading\nB Moore 1910 WOD 208 09:11 17:10 8.59\n'
      'D Derry 2001 WOD ALLOC 211 15:11 01:01 8.45 Amended Turn', firstComplete: true);
    // Add an unparseable turn fragment so the coordinate result remains blocked.
    final conflicted = SmartScanResult(fullText: page.fullText, lines: [
      ...page.lines.where((l) => !l.text.startsWith('15:11')),
      line('211 15:11 01:01 8.45', 300, 157),
    ]);
    final chosen = await DailyScanText.bestPages([conflicted], type);
    final result = await DailyAmendmentParser(
      documentType: type,
    ).parse(pageText: chosen);
    final existing = result.duties.firstWhere((d) => d.payrollNumber == '1910');
    expect(existing.bookOn, '08:11');
    expect(existing.bookOff, '17:10');
  });
  test('combines safe rows split between both OCR readings', () async {
    final page = SmartScanResult(
      fullText: '$heading\nA Jesson 3280 WOD ZS ZS',
      lines: [
        line(heading, 0, 20),
        line('1378 WOD ZS ZS', 180, 100),
      ],
    );
    final chosen = await DailyScanText.bestPages([page], type);
    final result = await DailyAmendmentParser(
      documentType: type,
    ).parse(pageText: chosen);
    expect(result.duties, hasLength(2));
    expect(result.duties.map((d) => d.payrollNumber).toSet(), {'3280', '1378'});
  });

  test('keeps a complete payroll-only row instead of a phantom extra duty', () async {
    final page = SmartScanResult(
      fullText: '$heading\n'
          'B Moore 1910 WOD 9001 04:25 13:10 8.45\n'
          '0049 WOD RDW 215 17:11 01:31 8.45 Amended Turn',
      lines: [
        line(heading, 0, 20),
        line('B Moore 1910 WOD 9001 04:25 13:10 8.45', 0, 100),
        // The positioned reading has dropped White and manufactured a
        // different parseable row. It must not beat the complete payroll row.
        line('A Phantom 7777 WOD 215 17:11 01:31 8.45', 0, 140),
      ],
    );
    final chosen = await DailyScanText.bestPages([page], type);
    final result = await DailyAmendmentParser(
      documentType: type,
    ).parse(pageText: chosen);
    expect(chosen.single, page.fullText);
    expect(result.duties.map((d) => d.payrollNumber).toSet(), {'1910', '0049'});
    final white = result.duties.singleWhere((d) => d.payrollNumber == '0049');
    expect(white.turnNumber, '215');
    expect(white.bookOn, '17:11');
    expect(white.bookOff, '01:31');
  });

  test('keeps the dated cloud reading when positional OCR drops the heading', () async {
    const saturdayHeading =
        '7DAY Report for Saturday 14/11/26 in All Links';
    final page = SmartScanResult(
      fullText: '$saturdayHeading\n'
          'N Cotton 5380 WOD ALLOC 601 04:23 13:08 8.45 Amended Turn\n'
          'H Purewal 1867 WOD ALLOC 9001 04:23 13:08 8.45',
      lines: [
        // The local positional OCR has lost the report heading and distorted
        // the first row, matching the failure mode from the photographed
        // Saturday sheet.
        line('Cotton | 1867 WOD ALLOC 9001 04:23 13:08 8.45', 0, 100),
        line('8 Morris 3100 WOD ALLOC 602 04:52 12:07 8.45', 0, 140),
      ],
    );

    final chosen = await DailyScanText.bestPages([page], type);
    final result = await DailyAmendmentParser(
      documentType: type,
    ).parse(pageText: chosen);

    expect(chosen.single, page.fullText);
    expect(result.identifiedDates, [DateTime(2026, 11, 14)]);
    expect(result.duties.map((d) => d.payrollNumber).toSet(), {
      '5380',
      '1867',
      // Safely recovered from the undated positional OCR reading.
      '3100',
    });
    expect(result.canImport, isTrue);
  });
}
