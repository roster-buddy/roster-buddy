import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/smart_scan/'
    'smart_scan_page_text_reconstructor.dart';
import 'package:roster_buddy/features/smart_scan/smart_scan_result.dart';

void main() {
  group('SmartScanPageTextReconstructor', () {
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
