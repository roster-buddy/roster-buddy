import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/smart_scan/'
    'smart_scan_page_text_reconstructor.dart';
import 'package:roster_buddy/features/smart_scan/smart_scan_result.dart';

void main() {
  group('SmartScanPageTextReconstructor', () {
    test('base grid retains blank Sunday and separate driver identity', () {
      SmartScanTextLine line(String text, double x, double y) =>
          SmartScanTextLine(
            text: text,
            left: x,
            top: y,
            right: x + 50,
            bottom: y + 10,
          );
      final result = SmartScanResult(
        fullText: '',
        lines: [
          for (final entry in [
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
          ].asMap().entries)
            line(entry.value, 200 + entry.key * 100, 10),
          line('1', 10, 40),
          line('No Duty', 200, 40),
          line('15:1100:5609:45211', 400, 40),
          line('3535', 10, 55),
          line('Liverpool,Lich,Ruge', 400, 55),
        ],
      );
      final rows = SmartScanPageTextReconstructor.reconstructBaseRoster(result)
          .split('\n');
      expect(rows[0].split('|').map((s) => s.trim()).toList(), [
        '1',
        '',
        'No Duty',
        '',
        '15:1100:5609:45211',
        '',
        '',
        '',
      ]);
      expect(rows[1].split('|').first.trim(), '3535');
    });

    test('base grid accepts imperfect headings and ignores duty numbers', () {
      SmartScanTextLine line(String text, double x, double y) =>
          SmartScanTextLine(
            text: text,
            left: x,
            top: y,
            right: x + 50,
            bottom: y + 10,
          );
      final result = SmartScanResult(fullText: '', lines: [
        line('[Monday', 200, 10),
        line('Tuesday', 300, 10),
        line('Wednsday', 400, 10),
        line('Thursday', 500, 10),
        line('Friday', 600, 10),
        line('(Saturday', 700, 10),
        line('1', 10, 40),
        line('15:1100:5609:45211', 400, 40),
        line('3535', 10, 55),
        line('51', 410, 70),
      ]);

      final rows = SmartScanPageTextReconstructor.reconstructBaseRoster(
        result,
      ).split('\n');

      expect(rows, hasLength(2));
      expect(rows.first.split('|').first.trim(), '1');
      expect(rows.last.split('|').first.trim(), '3535');
    });

    test('base grid derives columns when weekday headings are merged', () {
      SmartScanTextLine line(
        String text,
        double x,
        double y, {
        double width = 40,
      }) => SmartScanTextLine(
        text: text,
        left: x,
        top: y,
        right: x + width,
        bottom: y + 10,
      );
      final result = SmartScanResult(fullText: '', lines: [
        line('Monday Tuesday Wednesday Thursday Friday Saturday', 80, 10,
            width: 660),
        line('35', 4, 40, width: 18),
        line('07:4413:3805:542', 50, 40, width: 100),
        line('15:0023:4508:45Sp', 190, 40, width: 115),
        line('No Duty', 480, 40, width: 70),
        line('14:1523:0008:45Sp', 770, 40, width: 120),
        line('13:3022:1508:45Sp', 930, 40, width: 120),
        line('3535', 4, 55, width: 35),
        line('Walsall', 50, 55, width: 60),
        line('(1)', 190, 55, width: 20),
      ]);

      final rows = SmartScanPageTextReconstructor.reconstructBaseRoster(
        result,
      ).split('\n');

      expect(rows, hasLength(2));
      expect(rows.first.split('|').first.trim(), '35');
      expect(rows.last.split('|').first.trim(), '3535');
      expect(rows.first, contains('No Duty'));
    });

    test('reconstructs rows from top-to-bottom and left-to-right', () {
      const SmartScanResult result = SmartScanResult(
        fullText: 'Fallback text',
        lines: <SmartScanTextLine>[
          SmartScanTextLine(
            text: '13:45',
            left: 220,
            top: 100,
            right: 270,
            bottom: 120,
          ),
          SmartScanTextLine(
            text: 'MOORE',
            left: 10,
            top: 100,
            right: 70,
            bottom: 120,
          ),
          SmartScanTextLine(
            text: '31/07/2026',
            left: 10,
            top: 30,
            right: 110,
            bottom: 50,
          ),
          SmartScanTextLine(
            text: '05:30',
            left: 150,
            top: 100,
            right: 200,
            bottom: 120,
          ),
        ],
      );

      expect(
        SmartScanPageTextReconstructor.reconstruct(result),
        '31/07/2026\nMOORE  05:30  13:45',
      );
    });

    test('groups lines whose vertical positions are within tolerance', () {
      const SmartScanResult result = SmartScanResult(
        fullText: '',
        lines: <SmartScanTextLine>[
          SmartScanTextLine(
            text: 'PAY NO',
            left: 100,
            top: 52,
            right: 160,
            bottom: 72,
          ),
          SmartScanTextLine(
            text: 'NAME',
            left: 10,
            top: 48,
            right: 70,
            bottom: 68,
          ),
          SmartScanTextLine(
            text: 'TURN',
            left: 200,
            top: 55,
            right: 250,
            bottom: 75,
          ),
        ],
      );

      expect(
        SmartScanPageTextReconstructor.reconstruct(result),
        'NAME  PAY NO  TURN',
      );
    });

    test('falls back to fullText when no usable OCR lines remain', () {
      const SmartScanResult result = SmartScanResult(
        fullText: 'Original ML Kit text',
        lines: <SmartScanTextLine>[
          SmartScanTextLine(
            text: '   ',
            left: 10,
            top: 10,
            right: 20,
            bottom: 20,
          ),
        ],
      );

      expect(
        SmartScanPageTextReconstructor.reconstruct(result),
        'Original ML Kit text',
      );
    });

    test('preserves PDF page order and removes empty pages', () {
      const List<SmartScanResult> results = <SmartScanResult>[
        SmartScanResult(fullText: 'PAGE ONE', lines: <SmartScanTextLine>[]),
        SmartScanResult(fullText: '   ', lines: <SmartScanTextLine>[]),
        SmartScanResult(fullText: 'PAGE THREE', lines: <SmartScanTextLine>[]),
      ];

      expect(SmartScanPageTextReconstructor.reconstructPages(results), <String>[
        'PAGE ONE',
        'PAGE THREE',
      ]);
    });

    test('does not mutate the original OCR line order', () {
      const List<SmartScanTextLine> originalLines = <SmartScanTextLine>[
        SmartScanTextLine(
          text: 'RIGHT',
          left: 100,
          top: 20,
          right: 150,
          bottom: 40,
        ),
        SmartScanTextLine(
          text: 'LEFT',
          left: 10,
          top: 20,
          right: 60,
          bottom: 40,
        ),
      ];

      const SmartScanResult result = SmartScanResult(
        fullText: '',
        lines: originalLines,
      );

      SmartScanPageTextReconstructor.reconstruct(result);

      expect(result.lines.first.text, 'RIGHT');
      expect(result.lines.last.text, 'LEFT');
    });
  });
}
