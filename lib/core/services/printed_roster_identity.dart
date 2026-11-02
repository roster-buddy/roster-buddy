import '../models/duty.dart';

class PrintedRosterIdentity {
  const PrintedRosterIdentity._();

  static List<Duty> linkOwnRows(
    List<Duty> duties,
    Map<String, dynamic> profile,
  ) {
    final payroll = (profile['payroll_number'] ?? '').toString().trim();
    final name = (profile['display_name'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final surname = name.split(RegExp(r'\s+')).last;
    final depot = _depot((profile['depot'] ?? '').toString());
    bool matches(Duty d) {
      final printed = d.payrollNumber ?? '';
      final names = (d.driverName ?? '')
          .toUpperCase()
          .replaceAll(RegExp(r"[^A-Z -]"), '')
          .split(RegExp(r'\s+'));
      return printed.length == 4 &&
          payroll.length > 4 &&
          payroll.endsWith(printed) &&
          surname.isNotEmpty &&
          names.contains(surname) &&
          depot.isNotEmpty &&
          _depot(d.depot ?? '') == depot;
    }

    return duties
        .map((d) {
          if (!matches(d)) return d;
          final duplicates = duties
              .where((other) => other.date == d.date && matches(other))
              .length;
          if (duplicates != 1) return d;
          return d.copyWith(
            payrollNumber: payroll,
            driverNumber: profile['driver_number']?.toString(),
            remarks: [
              if (d.remarks != null) d.remarks!,
              'Printed pay number: ${d.payrollNumber}',
            ].join(' · '),
          );
        })
        .toList(growable: false);
  }

  static String _depot(String value) {
    final v = value.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
    return v == 'WOD' || v == 'WOLVERHAMPTON' ? 'WOLVERHAMPTON' : v;
  }
}
