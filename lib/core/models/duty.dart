import 'duty_type.dart';
import 'roster_source.dart';

class Duty {
  const Duty({
    required this.date,
    required this.source,
    required this.dutyType,
    this.turnNumber,
    this.bookOn,
    this.bookOff,
    this.rosteredMinutes,
    this.remarks,
    this.driverNumber,
    this.payrollNumber,
    this.driverName,
    this.depot,
    this.amendmentCode,
    this.mileage,
    this.pageNumber,
    this.rawText,
  });

  final DateTime date;
  final RosterSource source;
  final DutyType dutyType;

  /// Numeric roster turn, such as 201.
  ///
  /// Prefixes such as WO are removed before storage.
  final String? turnNumber;

  /// Times are stored in 24-hour HH:mm format.
  final String? bookOn;
  final String? bookOff;

  final int? rosteredMinutes;
  final String? remarks;

  /// Used by Base Rosters and Annual Leave Rosters.
  final String? driverNumber;

  /// Used by 10-Day, 7-Day and 48-Hour daily sheets.
  final String? payrollNumber;

  /// Driver name as printed on the source document.
  final String? driverName;

  final String? depot;

  /// Amendment or duty code printed on a daily sheet.
  ///
  /// Examples may include DI, TS, ALD, SP, LD or NDNA.
  final String? amendmentCode;

  final String? mileage;

  /// One-based source page number.
  final int? pageNumber;

  /// Original OCR row or cell text retained for review and troubleshooting.
  final String? rawText;

  bool get hasTimes => bookOn != null && bookOff != null;

  bool get hasDriverIdentity =>
      (payrollNumber != null && payrollNumber!.trim().isNotEmpty) ||
      (driverNumber != null && driverNumber!.trim().isNotEmpty);

  /// Identifier used when matching a shared parsed record to an account.
  String? get matchingIdentifier {
    final payroll = payrollNumber?.trim();
    if (payroll != null && payroll.isNotEmpty) {
      return payroll;
    }

    final driver = driverNumber?.trim();
    if (driver != null && driver.isNotEmpty) {
      return driver;
    }

    return null;
  }

  /// Stable record key for duplicate detection.
  String get uniqueKey {
    return [
      _dateKey(date),
      source.name,
      payrollNumber?.trim() ?? '',
      driverNumber?.trim() ?? '',
      turnNumber?.trim() ?? '',
      bookOn?.trim() ?? '',
      bookOff?.trim() ?? '',
      amendmentCode?.trim().toUpperCase() ?? '',
    ].join('|');
  }

  Duty copyWith({
    DateTime? date,
    RosterSource? source,
    DutyType? dutyType,
    String? turnNumber,
    String? bookOn,
    String? bookOff,
    int? rosteredMinutes,
    String? remarks,
    String? driverNumber,
    String? payrollNumber,
    String? driverName,
    String? depot,
    String? amendmentCode,
    String? mileage,
    int? pageNumber,
    String? rawText,
  }) {
    return Duty(
      date: date ?? this.date,
      source: source ?? this.source,
      dutyType: dutyType ?? this.dutyType,
      turnNumber: turnNumber ?? this.turnNumber,
      bookOn: bookOn ?? this.bookOn,
      bookOff: bookOff ?? this.bookOff,
      rosteredMinutes: rosteredMinutes ?? this.rosteredMinutes,
      remarks: remarks ?? this.remarks,
      driverNumber: driverNumber ?? this.driverNumber,
      payrollNumber: payrollNumber ?? this.payrollNumber,
      driverName: driverName ?? this.driverName,
      depot: depot ?? this.depot,
      amendmentCode: amendmentCode ?? this.amendmentCode,
      mileage: mileage ?? this.mileage,
      pageNumber: pageNumber ?? this.pageNumber,
      rawText: rawText ?? this.rawText,
    );
  }

  static String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');

    return '${value.year}-$month-$day';
  }
}
