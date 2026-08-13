class AnnualLeaveBlockCycle {
  const AnnualLeaveBlockCycle({
    required this.leaveYear,
    required this.weekIndex,
    required this.source,
  });

  final int leaveYear;
  final int weekIndex;
  final String source;

  /// Advances the block week by five positions within the 1-13 cycle.
  ///
  /// Examples:
  /// 1 -> 6
  /// 6 -> 11
  /// 11 -> 3
  int get nextYearWeekIndex => advanceWeekIndex(weekIndex);

  static int advanceWeekIndex(int currentWeekIndex) {
    if (currentWeekIndex < 1 || currentWeekIndex > 13) {
      throw ArgumentError.value(
        currentWeekIndex,
        'currentWeekIndex',
        'Block week must be between 1 and 13.',
      );
    }

    return ((currentWeekIndex - 1 + 5) % 13) + 1;
  }

  factory AnnualLeaveBlockCycle.fromMap(Map<String, dynamic> row) {
    return AnnualLeaveBlockCycle(
      leaveYear: _asInt(row['leave_year']) ?? DateTime.now().year,
      weekIndex: _asInt(row['week_index']) ?? 1,
      source: (row['source'] ?? 'manual').toString(),
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
