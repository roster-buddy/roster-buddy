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
    'short printed pay number links only with matching surname and depot',
    () {
      final linked = PrintedRosterIdentity.linkOwnRows([row()], profile).single;
      expect(linked.payrollNumber, '52319');
      expect(linked.driverNumber, '4321');
      expect(linked.remarks, contains('2319'));
    },
  );
  test('surname, depot and identifier mismatches do not link', () {
    for (final duty in [
      row(name: 'A Else'),
      row(depot: 'BHM'),
      row(payroll: '2419'),
      row(payroll: '319'),
    ]) {
      expect(
        PrintedRosterIdentity.linkOwnRows([duty], profile).single.payrollNumber,
        duty.payrollNumber,
      );
    }
  });
  test('ambiguous same-day rows do not link automatically', () {
    final linked = PrintedRosterIdentity.linkOwnRows([row(), row()], profile);
    expect(linked.every((d) => d.payrollNumber == '2319'), isTrue);
  });
}
