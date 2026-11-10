import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/smart_scan/smart_scan_quality.dart';

void main() {
  test('requests a rescue scan when identified roster rows lose book-off times', () {
    const text = '''
D Lawrence 1167 WOD ALLOC 201 04:25 12:53 8.45
N Cotton 5380 WOD ALLOC 9001 04:25 13:10 8.45
N Appleby 2175 WOD RK
A Passmore 4365 WOD ALLOC 203 04:54 13:22 8.45
PJ Pratt 1040 WOD 204 04:56 12:58 8.02
M Winfindale 0979 WOD LD LD 08:11 OTELT 8.59
S Ellison 2335 WOD RL RL 12:30 garbage 8.45
MA Khukon 1378 WOD D3 D3 12:45 garbage 8.45
N Carter 0049 WOD ALLOC 215 17:11
B Morris 1192 WOD ALD
''';
    expect(SmartScanQuality.needsLocalRescue(text), isTrue);
  });

  test('accepts complete working and non-working roster rows', () {
    const text = '''
A One 1001 WOD ALLOC 201 04:25 12:53 8.45
B Two 1002 WOD ZS ZS
C Three 1003 WOD ND
D Four 1004 WOD SF SF
E Five 1005 WOD ALD ALD 08:45
F Six 1006 WOD RL RL 13:00 21:45 8.45
''';
    expect(SmartScanQuality.needsLocalRescue(text), isFalse);
  });

  test('re-reads a base roster whose driver numbers use separate rows', () {
    const text = '''
Sunday Monday Tuesday Wednesday Thursday Friday Saturday
1 No Duty No Duty 15:11 00:56 09:45 211
3535 Liverpool Lichfield Rugeley
2 08:11 17:10 08:59 208 No Duty No Duty
3518 Shrewsbury Redditch
''';

    expect(SmartScanQuality.needsLocalRescue(text), isTrue);
  });
  test('rescues split base roster rows even without No Duty text', () {
    const text = '''
Sunday Monday Tuesday Wednesday Thursday Friday Saturday
1 15:11 00:56 09:45 211 15:15 00:00 08:45 Sp
3535 Liverpool Lichfield Rugeley
2 08:11 17:10 08:59 208 07:00 15:14 08:14 217
3518 Shrewsbury Redditch
''';
    expect(SmartScanQuality.needsLocalRescue(text), isTrue);
  });

  test('does not mistake daily payroll rows for base roster grid', () {
    const text = '''
Tuesday 10 November 2026
1 04:25 12:53 8.45
3535 Liverpool Lichfield
2 13:00 21:45 8.45
3518 Shrewsbury Redditch
''';
    expect(SmartScanQuality.needsLocalRescue(text), isFalse);
  });

}
