enum AnnualLeaveBlockPeriodType {
  spring,
  summerFirstWeek,
  summerSecondWeek,
  winter,
}

enum AnnualLeaveBlockChangeType { manual, agreedMove, mutualSwap }

class AnnualLeaveBlockOverride {
  const AnnualLeaveBlockOverride({
    required this.id,
    required this.leaveYear,
    required this.periodType,
    required this.overrideStartDate,
    required this.overrideEndDate,
    required this.changeType,
    this.originalStartDate,
    this.originalEndDate,
    this.swapDriverNumber,
    this.swapReference,
    this.notes,
  });

  final String id;
  final int leaveYear;
  final AnnualLeaveBlockPeriodType periodType;

  final DateTime? originalStartDate;
  final DateTime? originalEndDate;

  final DateTime overrideStartDate;
  final DateTime overrideEndDate;

  final AnnualLeaveBlockChangeType changeType;

  final String? swapDriverNumber;
  final String? swapReference;
  final String? notes;

  factory AnnualLeaveBlockOverride.fromMap(Map<String, dynamic> row) {
    return AnnualLeaveBlockOverride(
      id: (row['id'] ?? '').toString(),
      leaveYear: _asInt(row['leave_year']) ?? DateTime.now().year,
      periodType: _periodType(row['period_type']),
      originalStartDate: _date(row['original_start_date']),
      originalEndDate: _date(row['original_end_date']),
      overrideStartDate:
          _date(row['override_start_date']) ??
          DateTime(DateTime.now().year, 1, 1),
      overrideEndDate:
          _date(row['override_end_date']) ??
          DateTime(DateTime.now().year, 1, 1),
      changeType: _changeType(row['change_type']),
      swapDriverNumber: _nullableString(row['swap_driver_number']),
      swapReference: _nullableString(row['swap_reference']),
      notes: _nullableString(row['notes']),
    );
  }

  static AnnualLeaveBlockPeriodType _periodType(Object? value) {
    switch (value?.toString()) {
      case 'spring':
        return AnnualLeaveBlockPeriodType.spring;
      case 'summer_first_week':
        return AnnualLeaveBlockPeriodType.summerFirstWeek;
      case 'summer_second_week':
        return AnnualLeaveBlockPeriodType.summerSecondWeek;
      case 'winter':
        return AnnualLeaveBlockPeriodType.winter;
      default:
        return AnnualLeaveBlockPeriodType.spring;
    }
  }

  static AnnualLeaveBlockChangeType _changeType(Object? value) {
    switch (value?.toString()) {
      case 'agreed_move':
        return AnnualLeaveBlockChangeType.agreedMove;
      case 'mutual_swap':
        return AnnualLeaveBlockChangeType.mutualSwap;
      default:
        return AnnualLeaveBlockChangeType.manual;
    }
  }

  static DateTime? _date(Object? value) {
    final String cleaned = value?.toString().trim() ?? '';
    return cleaned.isEmpty ? null : DateTime.tryParse(cleaned);
  }

  static String? _nullableString(Object? value) {
    final String cleaned = value?.toString().trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }
}
