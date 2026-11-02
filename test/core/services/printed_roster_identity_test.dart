import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/duty.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/core/services/printed_roster_identity.dart';

void main() {
  const profile = {
    'payroll_number': '52319',
    'driver_number': '4321',
    'display_name': 'Alex Tester',
    'depot': 'Wolverhampton',
  };
  Duty row({
    String payroll = '2319',
    String name = 'A Tester',
    String depot = 'WOD',
  }) => Duty(
    date: DateTime(2026, 11, 5),
    source: RosterSource.sevenDay,
    dutyType: DutyType.working,
    payrollNumber: payroll,
    driverName: name,
    depot: depot,
    bookOn: '16:53',
    bookOff: '01:11',
  );
  test(
    'short printed pay number links to the full profile payroll',
    () {
      final linked = PrintedRosterIdentity.linkOwnRows([row()], profile).single;
      expect(linked.payrollNumber, '52319');
      expect(linked.driverNumber, '4321');
      expect(linked.remarks, contains('2319'));
    },
  );
  test('different or incomplete payroll numbers do not link', () {
    for (final duty in [
      row(payroll: '2419'),
      row(payroll: '319'),
    ]) {
      expect(
        PrintedRosterIdentity.linkOwnRows([duty], profile).single.payrollNumber,
        duty.payrollNumber,
      );
    }
  });
  test('payroll matching uses the last four digits without OCR name dependency', () {
    expect(PrintedRosterIdentity.payrollMatches('52319', '2319'), isTrue);
    expect(PrintedRosterIdentity.payrollMatches('52319', '12319'), isTrue);
    expect(PrintedRosterIdentity.payrollMatches('10049', '0049'), isTrue);
    expect(PrintedRosterIdentity.payrollMatches('0049', '49'), isFalse);
    expect(PrintedRosterIdentity.payrollMatches(null, null), isFalse);
    expect(PrintedRosterIdentity.payrollMatches('52319', '2318'), isFalse);
    final linked = PrintedRosterIdentity.linkOwnRows([row(name: 'Unreadable', depot: '')], profile).single;
    expect(linked.payrollNumber, '52319');
  });
  test('ambiguous same-day rows do not link automatically', () {
    final linked = PrintedRosterIdentity.linkOwnRows([row(), row()], profile);
    expect(linked.every((d) => d.payrollNumber == '2319'), isTrue);
  });
}
