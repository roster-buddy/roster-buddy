import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/parser/job_card_page_splitter.dart';

void main() {
  group('JobCardPageSplitter', () {
    const JobCardPageSplitter splitter = JobCardPageSplitter();

    test('returns an empty list for blank OCR text', () {
      expect(splitter.split('   '), isEmpty);
    });

    test('keeps a single Job Card unchanged', () {
      const String page = '''
JOB CARD
WO201
DAY CODE SX
BOOK ON 06:00
BOOK OFF 14:00
''';

      final List<String> result = splitter.split(page);

      expect(result, hasLength(1));
      expect(result.single, contains('WO201'));
      expect(result.single, contains('BOOK OFF 14:00'));
    });

    test('splits multiple Job Cards found on one page', () {
      const String page = '''
WEST MIDLANDS TRAINS JOB CARDS

WO201
DAY CODE SX
BOOK ON 06:00
BOOK OFF 14:00
Prepare train at Birmingham New Street

WO202
DAY CODE SX
BOOK ON 07:00
BOOK OFF 15:00
Work 1A02 to London Euston

WO301
DAY CODE SO
BOOK ON 08:00
BOOK OFF 16:00
Saturday duty
''';

      final List<String> result = splitter.split(page);

      expect(result, hasLength(3));

      expect(result[0], contains('WEST MIDLANDS TRAINS JOB CARDS'));
      expect(result[0], contains('WO201'));
      expect(result[0], isNot(contains('WO202')));

      expect(result[1], contains('WO202'));
      expect(result[1], isNot(contains('WO301')));

      expect(result[2], contains('WO301'));
      expect(result[2], contains('Saturday duty'));
    });

    test('recognises common OCR variants of WO', () {
      const String page = '''
W0201
DAY CODE SX
BOOK ON 06:00
BOOK OFF 14:00

WQ202
DAY CODE SX
BOOK ON 07:00
BOOK OFF 15:00
''';

      final List<String> result = splitter.split(page);

      expect(result, hasLength(2));
      expect(result[0], contains('W0201'));
      expect(result[1], contains('WQ202'));
    });
  });
}
