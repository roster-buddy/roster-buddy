enum JobCardPlanType { ltp, stp, vstp, unknown }

enum JobCardDayType {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

class JobCard {
  const JobCard({
    required this.turnNumber,
    required this.originalTurnCode,
    required this.dayCode,
    required this.planType,
    required this.validFrom,
    required this.validTo,
    required this.bookOn,
    required this.bookOff,
    required this.rosteredMinutes,
    required this.rawText,
    this.instructions = const [],
    this.pageNumber,
  });

  /// Numeric turn used when matching against a roster duty.
  ///
  /// Example:
  /// WO201 becomes 201.
  final String turnNumber;

  /// Original complete turn code printed on the card.
  ///
  /// Example:
  /// WO201.
  final String originalTurnCode;

  /// Printed applicability code.
  ///
  /// Examples:
  /// SX, SO, SUN, MO, MSX, MTX, ThFO.
  final String dayCode;

  final JobCardPlanType planType;

  final DateTime validFrom;
  final DateTime validTo;

  /// Times are retained in 24-hour HH:mm format.
  final String bookOn;
  final String bookOff;

  final int rosteredMinutes;

  /// Complete OCR text for the card.
  final String rawText;

  /// Parsed working instructions, train movements, breaks and other details.
  final List<String> instructions;

  /// One-based page number within the uploaded PDF.
  final int? pageNumber;

  bool isValidOn(DateTime date) {
    final normalisedDate = DateTime(date.year, date.month, date.day);
    final normalisedFrom = DateTime(
      validFrom.year,
      validFrom.month,
      validFrom.day,
    );
    final normalisedTo = DateTime(validTo.year, validTo.month, validTo.day);

    return !normalisedDate.isBefore(normalisedFrom) &&
        !normalisedDate.isAfter(normalisedTo) &&
        appliesOnWeekday(date.weekday);
  }

  bool appliesOnWeekday(int weekday) {
    final days = applicableDays;
    return days.contains(weekday);
  }

  /// Returns Dart weekday numbers:
  ///
  /// Monday = 1
  /// Tuesday = 2
  /// Wednesday = 3
  /// Thursday = 4
  /// Friday = 5
  /// Saturday = 6
  /// Sunday = 7
  Set<int> get applicableDays {
    final code = _normaliseDayCode(dayCode);

    if (code == 'SUN' || code == 'SU') {
      return const {DateTime.sunday};
    }

    if (code == 'SO' || code == 'SAO') {
      return const {DateTime.saturday};
    }

    if (code == 'SX') {
      return const {
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
      };
    }

    final onlyIndex = code.indexOf('O');
    if (onlyIndex > 0) {
      final dayPart = code.substring(0, onlyIndex);
      return _parseDayLetters(dayPart);
    }

    final exceptIndex = code.indexOf('X');
    if (exceptIndex >= 0) {
      final excludedPart = code.substring(0, exceptIndex);
      final excluded = _parseDayLetters(excludedPart);

      return {
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
      }..removeAll(excluded);
    }

    final explicitDays = _parseDayLetters(code);
    if (explicitDays.isNotEmpty) {
      return explicitDays;
    }

    return const {};
  }

  /// Higher values indicate a more specific card.
  ///
  /// This helps select between cards such as:
  /// WO201 SX
  /// WO201 MTX
  /// WO201 ThFO
  int get daySpecificity {
    final code = _normaliseDayCode(dayCode);

    if (code.contains('O') && code != 'SO') {
      return 30;
    }

    if (code.contains('X') && code != 'SX') {
      return 20;
    }

    if (code == 'SUN' || code == 'SU' || code == 'SO') {
      return 15;
    }

    if (code == 'SX') {
      return 10;
    }

    return 0;
  }

  int get planPriority {
    switch (planType) {
      case JobCardPlanType.vstp:
        return 3;
      case JobCardPlanType.stp:
        return 2;
      case JobCardPlanType.ltp:
        return 1;
      case JobCardPlanType.unknown:
        return 0;
    }
  }

  String get uniqueKey {
    return [
      turnNumber,
      dayCode.toUpperCase(),
      validFrom.toIso8601String(),
      validTo.toIso8601String(),
      planType.name,
    ].join('|');
  }

  static String _normaliseDayCode(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('TH', 'Th')
        .toUpperCase();
  }

  static Set<int> _parseDayLetters(String value) {
    final days = <int>{};
    var index = 0;

    while (index < value.length) {
      if (index + 1 < value.length &&
          value.substring(index, index + 2).toUpperCase() == 'TH') {
        days.add(DateTime.thursday);
        index += 2;
        continue;
      }

      switch (value[index].toUpperCase()) {
        case 'M':
          days.add(DateTime.monday);
          break;
        case 'T':
          days.add(DateTime.tuesday);
          break;
        case 'W':
          days.add(DateTime.wednesday);
          break;
        case 'F':
          days.add(DateTime.friday);
          break;
        case 'S':
          days.add(DateTime.saturday);
          break;
      }

      index++;
    }

    return days;
  }
}
