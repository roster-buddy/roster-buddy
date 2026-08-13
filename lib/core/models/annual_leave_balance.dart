class AnnualLeaveBalance {
  const AnnualLeaveBalance({
    required this.leaveYear,
    required this.entitlementDays,
    required this.startingBalanceDays,
    required this.bonusDays,
    required this.carryOverDays,
    required this.lieuDays,
    required this.committedDays,
  });

  final int leaveYear;

  /// Normal yearly floating entitlement.
  ///
  /// WMT default is 14.
  final int entitlementDays;

  /// Balance available when Roster Buddy begins tracking the leave year.
  ///
  /// This allows somebody starting Roster Buddy part way through the year
  /// to enter their actual remaining floating entitlement.
  final int startingBalanceDays;

  /// Extra leave awarded during this specific leave year.
  final int bonusDays;

  /// Unused floating leave carried into this leave year.
  final int carryOverDays;

  /// Additional days in lieu available during this leave year.
  final int lieuDays;

  /// Requested, abeyance or granted floating days already committed.
  final int committedDays;

  int get totalAvailableDays =>
      startingBalanceDays + bonusDays + carryOverDays + lieuDays;

  int get remainingDays {
    final int value = totalAvailableDays - committedDays;
    return value < 0 ? 0 : value;
  }

  factory AnnualLeaveBalance.fromMap(
    Map<String, dynamic> row, {
    required int committedDays,
  }) {
    return AnnualLeaveBalance(
      leaveYear: _asInt(row['leave_year']) ?? DateTime.now().year,
      entitlementDays: _asInt(row['entitlement_days']) ?? 14,
      startingBalanceDays:
          _asInt(row['starting_balance_days']) ??
          _asInt(row['entitlement_days']) ??
          14,
      bonusDays: _asInt(row['bonus_days']) ?? 0,
      carryOverDays: _asInt(row['carry_over_days']) ?? 0,
      lieuDays: _asInt(row['lieu_days']) ?? 0,
      committedDays: committedDays,
    );
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
