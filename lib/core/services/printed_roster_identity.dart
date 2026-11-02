import '../models/duty.dart';

class PrintedRosterIdentity {
  const PrintedRosterIdentity._();

  static List<Duty> linkOwnRows(
    List<Duty> duties,
    Map<String, dynamic> profile,
  ) {
    final payroll = (profile['payroll_number'] ?? '').toString().trim();
    bool matches(Duty d) => payrollMatches(d.payrollNumber, payroll);

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

  // Preserve leading zeros; payroll identifiers are strings, not quantities.
  static String? payrollKey(String? value) {
    final digits = value?.trim() ?? '';
    if (!RegExp(r'^\d{4,}$').hasMatch(digits)) return null;
    return digits.substring(digits.length - 4);
  }

  static bool payrollMatches(String? first, String? second) {
    final key = payrollKey(first);
    return key != null && key == payrollKey(second);
  }
}
