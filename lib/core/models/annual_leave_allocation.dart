enum AnnualLeavePeriodType { spring, summerFirstWeek, summerSecondWeek, winter }

enum AnnualLeaveAllocationSource {
  officialRoster,
  agreedMove,
  mutualSwap,
  manualCorrection,
}

class AnnualLeavePeriod {
  const AnnualLeavePeriod({
    required this.type,
    required this.startDate,
    required this.endDate,
  });

  final AnnualLeavePeriodType type;
  final DateTime startDate;
  final DateTime endDate;

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    return !day.isBefore(start) && !day.isAfter(end);
  }

  int get numberOfDays {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    return end.difference(start).inDays + 1;
  }
}

class AnnualLeaveAllocation {
  const AnnualLeaveAllocation({
    required this.leaveYear,
    required this.depot,
    required this.driverNumber,
    required this.surname,
    required this.blockNumber,
    required this.periods,
    this.source = AnnualLeaveAllocationSource.officialRoster,
    this.originalBlockNumber,
    this.otherDriverNumber,
    this.otherDriverSurname,
    this.swapReference,
    this.isConfirmed = true,
    this.pageNumber,
  });

  final int leaveYear;
  final String depot;

  /// Driver number printed in the annual leave roster cell.
  final String driverNumber;
  final String surname;

  /// Permanent annual-leave block allocated to the driver.
  ///
  /// The block may move horizontally within each year's printed table,
  /// but the driver's block number itself does not change.
  final int blockNumber;

  /// Official or overridden leave periods for this allocation.
  final List<AnnualLeavePeriod> periods;

  final AnnualLeaveAllocationSource source;

  /// Used when a swap or agreed move replaces the official allocation.
  final int? originalBlockNumber;

  /// Other driver involved in a mutual swap, when applicable.
  final String? otherDriverNumber;
  final String? otherDriverSurname;

  /// Optional reference, confirmation number or note for the swap.
  final String? swapReference;

  /// An unconfirmed swap must not replace the current calendar dates.
  final bool isConfirmed;

  /// One-based page number within the uploaded document.
  final int? pageNumber;

  AnnualLeavePeriod? periodFor(AnnualLeavePeriodType type) {
    for (final period in periods) {
      if (period.type == type) {
        return period;
      }
    }

    return null;
  }

  AnnualLeavePeriod? periodContaining(DateTime date) {
    for (final period in periods) {
      if (period.contains(date)) {
        return period;
      }
    }

    return null;
  }

  bool get isOfficial => source == AnnualLeaveAllocationSource.officialRoster;

  bool get isSwap =>
      source == AnnualLeaveAllocationSource.agreedMove ||
      source == AnnualLeaveAllocationSource.mutualSwap;

  String get uniqueKey {
    return [
      leaveYear,
      depot.trim().toUpperCase(),
      driverNumber.trim(),
      blockNumber,
      source.name,
    ].join('|');
  }

  AnnualLeaveAllocation copyWith({
    int? leaveYear,
    String? depot,
    String? driverNumber,
    String? surname,
    int? blockNumber,
    List<AnnualLeavePeriod>? periods,
    AnnualLeaveAllocationSource? source,
    int? originalBlockNumber,
    String? otherDriverNumber,
    String? otherDriverSurname,
    String? swapReference,
    bool? isConfirmed,
    int? pageNumber,
  }) {
    return AnnualLeaveAllocation(
      leaveYear: leaveYear ?? this.leaveYear,
      depot: depot ?? this.depot,
      driverNumber: driverNumber ?? this.driverNumber,
      surname: surname ?? this.surname,
      blockNumber: blockNumber ?? this.blockNumber,
      periods: periods ?? this.periods,
      source: source ?? this.source,
      originalBlockNumber: originalBlockNumber ?? this.originalBlockNumber,
      otherDriverNumber: otherDriverNumber ?? this.otherDriverNumber,
      otherDriverSurname: otherDriverSurname ?? this.otherDriverSurname,
      swapReference: swapReference ?? this.swapReference,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      pageNumber: pageNumber ?? this.pageNumber,
    );
  }
}
