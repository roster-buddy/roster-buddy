class AnnualLeaveBlockCycle {
  const AnnualLeaveBlockCycle({
    required this.leaveYear,
    required this.weekIndex,
    required this.source,
    int? columnIndex,
  }) : columnIndex = columnIndex ?? weekIndex;

  final int leaveYear;
  final int weekIndex;
  final int columnIndex;
  final String source;

  /// Advances the block week by five positions within the 1-13 cycle.
  ///
  /// Examples:
  /// 1 -> 6
  /// 6 -> 11
  /// 11 -> 3
  int get nextYearWeekIndex => advanceWeekIndex(columnIndex);

  AnnualLeaveBlockCycle projectToYear(int year) => AnnualLeaveBlockCycle(
    leaveYear: year,
    weekIndex: weekIndex,
    columnIndex: advanceWeekIndex(columnIndex, years: year - leaveYear),
    source: 'calculated',
  );

  static int advanceWeekIndex(int currentWeekIndex, {int years = 1}) {
    if (currentWeekIndex < 1 || currentWeekIndex > 13) {
      throw ArgumentError.value(
        currentWeekIndex,
        'currentWeekIndex',
        'Block week must be between 1 and 13.',
      );
    }

    return ((currentWeekIndex - 1 + 5 * years) % 13) + 1;
  }

  /// Wolverhampton's 2027 roster starts at Group 8. The printed group
  /// numbers advance left to right and wrap after 13.
  int get wolverhamptonColumn {
    final label = advanceWeekIndex(weekIndex, years: leaveYear - 2027);
    return (label - 8) % 13 + 1;
  }

  ({DateTime spring, DateTime summerFirst, DateTime summerSecond,
    DateTime winter}) get wolverhamptonBlockStarts {
    final januaryFirst = DateTime(leaveYear, 1, 1);
    final firstMonday = 1 + (DateTime.monday - januaryFirst.weekday) % 7;
    final columnOffset = wolverhamptonColumn - 1;
    DateTime week(int offset) => DateTime(leaveYear, 1, firstMonday + 7 * offset);

    return (
      spring: week(columnOffset),
      summerFirst: week(13 + 2 * columnOffset),
      summerSecond: week(14 + 2 * columnOffset),
      winter: week(39 + columnOffset),
    );
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
