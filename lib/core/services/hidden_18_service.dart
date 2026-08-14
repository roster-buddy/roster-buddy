import '../models/duty.dart';
import '../models/duty_type.dart';

enum Hidden18WarningType {
  shiftLength,
  minimumRest,
  rollingSevenDays,
  consecutiveDays,
}

class Hidden18Warning {
  const Hidden18Warning({
    required this.type,
    required this.date,
    required this.message,
    this.relatedDate,
    this.minutes,
  });

  final Hidden18WarningType type;
  final DateTime date;
  final DateTime? relatedDate;
  final String message;
  final int? minutes;
}

class Hidden18Result {
  const Hidden18Result({
    required this.warnings,
    required this.consecutiveDaysWorked,
    required this.rollingSevenDayMinutes,
  });

  final List<Hidden18Warning> warnings;

  /// Number of consecutive working days ending on the latest date evaluated.
  final int consecutiveDaysWorked;

  /// Greatest amount of working time found in any rolling seven-day window.
  final int rollingSevenDayMinutes;

  bool get hasWarnings => warnings.isNotEmpty;
}

class Hidden18Service {
  const Hidden18Service();

  static const int maximumShiftMinutes = 12 * 60;
  static const int minimumRestMinutes = 12 * 60;
  static const int maximumRollingSevenDayMinutes = 72 * 60;
  static const int maximumConsecutiveWorkingDays = 13;

  Hidden18Result evaluate(Iterable<Duty> duties) {
    final List<Duty> ordered = duties.toList()
      ..sort((Duty first, Duty second) => first.date.compareTo(second.date));

    if (ordered.isEmpty) {
      return const Hidden18Result(
        warnings: <Hidden18Warning>[],
        consecutiveDaysWorked: 0,
        rollingSevenDayMinutes: 0,
      );
    }

    final Map<String, Duty> dutiesByDate = <String, Duty>{
      for (final Duty duty in ordered) _dateKey(duty.date): duty,
    };

    final List<Hidden18Warning> warnings = <Hidden18Warning>[];

    _checkShiftLengths(duties: ordered, warnings: warnings);

    _checkMinimumRest(duties: ordered, warnings: warnings);

    final int greatestRollingMinutes = _checkRollingSevenDays(
      dutiesByDate: dutiesByDate,
      warnings: warnings,
    );

    final int finalConsecutiveDays = _checkConsecutiveDays(
      dutiesByDate: dutiesByDate,
      warnings: warnings,
    );

    warnings.sort((Hidden18Warning first, Hidden18Warning second) {
      final int dateComparison = first.date.compareTo(second.date);

      if (dateComparison != 0) {
        return dateComparison;
      }

      return first.type.index.compareTo(second.type.index);
    });

    return Hidden18Result(
      warnings: List<Hidden18Warning>.unmodifiable(warnings),
      consecutiveDaysWorked: finalConsecutiveDays,
      rollingSevenDayMinutes: greatestRollingMinutes,
    );
  }

  static void _checkShiftLengths({
    required List<Duty> duties,
    required List<Hidden18Warning> warnings,
  }) {
    for (final Duty duty in duties) {
      if (!duty.dutyType.countsAsWorking) {
        continue;
      }

      final int? workedMinutes = _workedMinutes(duty);

      if (workedMinutes == null || workedMinutes <= maximumShiftMinutes) {
        continue;
      }

      warnings.add(
        Hidden18Warning(
          type: Hidden18WarningType.shiftLength,
          date: _dateOnly(duty.date),
          minutes: workedMinutes,
          message:
              'Duty is ${_formatMinutes(workedMinutes)}. '
              'Hidden 18 maximum is 12 hours.',
        ),
      );
    }
  }

  static void _checkMinimumRest({
    required List<Duty> duties,
    required List<Hidden18Warning> warnings,
  }) {
    final List<Duty> workingDuties =
        duties
            .where((Duty duty) => duty.dutyType.countsAsWorking)
            .where((Duty duty) => _dutyStart(duty) != null)
            .where((Duty duty) => _dutyEnd(duty) != null)
            .toList()
          ..sort((Duty first, Duty second) {
            return _dutyStart(first)!.compareTo(_dutyStart(second)!);
          });

    for (int index = 1; index < workingDuties.length; index++) {
      final Duty previous = workingDuties[index - 1];
      final Duty current = workingDuties[index];

      final DateTime previousEnd = _dutyEnd(previous)!;
      final DateTime currentStart = _dutyStart(current)!;

      final int restMinutes = currentStart.difference(previousEnd).inMinutes;

      if (restMinutes >= minimumRestMinutes) {
        continue;
      }

      warnings.add(
        Hidden18Warning(
          type: Hidden18WarningType.minimumRest,
          date: _dateOnly(current.date),
          relatedDate: _dateOnly(previous.date),
          minutes: restMinutes,
          message:
              'Only ${_formatMinutes(restMinutes)} rest between duties. '
              'Hidden 18 minimum is 12 hours.',
        ),
      );
    }
  }

  static int _checkRollingSevenDays({
    required Map<String, Duty> dutiesByDate,
    required List<Hidden18Warning> warnings,
  }) {
    if (dutiesByDate.isEmpty) {
      return 0;
    }

    final List<DateTime> dates =
        dutiesByDate.values
            .map((Duty duty) => _dateOnly(duty.date))
            .toSet()
            .toList()
          ..sort();

    final DateTime firstDate = dates.first;
    final DateTime lastDate = dates.last;

    int greatestMinutes = 0;
    final Set<String> warningWindows = <String>{};

    DateTime windowEnd = firstDate;

    while (!windowEnd.isAfter(lastDate)) {
      final DateTime windowStart = windowEnd.subtract(const Duration(days: 6));

      int totalMinutes = 0;

      for (int offset = 0; offset < 7; offset++) {
        final DateTime date = windowStart.add(Duration(days: offset));
        final Duty? duty = dutiesByDate[_dateKey(date)];

        if (duty == null || !duty.dutyType.countsAsWorking) {
          continue;
        }

        totalMinutes += _workedMinutes(duty) ?? 0;
      }

      if (totalMinutes > greatestMinutes) {
        greatestMinutes = totalMinutes;
      }

      if (totalMinutes > maximumRollingSevenDayMinutes) {
        final String warningKey =
            '${_dateKey(windowStart)}|${_dateKey(windowEnd)}';

        if (warningWindows.add(warningKey)) {
          warnings.add(
            Hidden18Warning(
              type: Hidden18WarningType.rollingSevenDays,
              date: windowEnd,
              relatedDate: windowStart,
              minutes: totalMinutes,
              message:
                  '${_formatMinutes(totalMinutes)} worked in the '
                  '7 days ending ${_displayDate(windowEnd)}. '
                  'Hidden 18 maximum is 72 hours.',
            ),
          );
        }
      }

      windowEnd = windowEnd.add(const Duration(days: 1));
    }

    return greatestMinutes;
  }

  static int _checkConsecutiveDays({
    required Map<String, Duty> dutiesByDate,
    required List<Hidden18Warning> warnings,
  }) {
    if (dutiesByDate.isEmpty) {
      return 0;
    }

    final List<DateTime> dates =
        dutiesByDate.values
            .map((Duty duty) => _dateOnly(duty.date))
            .toSet()
            .toList()
          ..sort();

    DateTime currentDate = dates.first;
    final DateTime lastDate = dates.last;

    int consecutiveDays = 0;
    bool warningRaisedForCurrentRun = false;

    while (!currentDate.isAfter(lastDate)) {
      final Duty? duty = dutiesByDate[_dateKey(currentDate)];

      if (duty != null && duty.dutyType.countsAsWorking) {
        consecutiveDays++;

        if (consecutiveDays > maximumConsecutiveWorkingDays &&
            !warningRaisedForCurrentRun) {
          warnings.add(
            Hidden18Warning(
              type: Hidden18WarningType.consecutiveDays,
              date: currentDate,
              minutes: consecutiveDays,
              message:
                  '$consecutiveDays consecutive working days detected. '
                  'Hidden 18 maximum is 13.',
            ),
          );

          warningRaisedForCurrentRun = true;
        }
      } else {
        // Rest days, annual leave (ALD/AW), sickness, public holidays,
        // unavailable Sundays and other non-working days all break a run
        // of consecutive working days.
        //
        // In particular, granted floating ALD and block AW arrive here as
        // DutyType.annualLeave through DutyResolver, so Annual Leave resets
        // the consecutive-days calculation automatically.
        consecutiveDays = 0;
        warningRaisedForCurrentRun = false;
      }

      currentDate = currentDate.add(const Duration(days: 1));
    }

    return consecutiveDays;
  }

  static int? _workedMinutes(Duty duty) {
    if (!duty.dutyType.countsAsWorking) {
      return null;
    }

    if (duty.rosteredMinutes != null && duty.rosteredMinutes! >= 0) {
      return duty.rosteredMinutes;
    }

    final DateTime? start = _dutyStart(duty);
    final DateTime? end = _dutyEnd(duty);

    if (start == null || end == null) {
      return null;
    }

    return end.difference(start).inMinutes;
  }

  static DateTime? _dutyStart(Duty duty) {
    final _ClockTime? bookOn = _parseClockTime(duty.bookOn);

    if (bookOn == null) {
      return null;
    }

    return DateTime(
      duty.date.year,
      duty.date.month,
      duty.date.day,
      bookOn.hour,
      bookOn.minute,
    );
  }

  static DateTime? _dutyEnd(Duty duty) {
    final _ClockTime? bookOn = _parseClockTime(duty.bookOn);
    final _ClockTime? bookOff = _parseClockTime(duty.bookOff);

    if (bookOn == null || bookOff == null) {
      return null;
    }

    DateTime end = DateTime(
      duty.date.year,
      duty.date.month,
      duty.date.day,
      bookOff.hour,
      bookOff.minute,
    );

    final int startMinute = (bookOn.hour * 60) + bookOn.minute;
    final int endMinute = (bookOff.hour * 60) + bookOff.minute;

    if (endMinute <= startMinute) {
      end = end.add(const Duration(days: 1));
    }

    return end;
  }

  static _ClockTime? _parseClockTime(String? value) {
    final String cleaned = value?.trim() ?? '';

    if (cleaned.isEmpty) {
      return null;
    }

    final RegExpMatch? match = RegExp(
      r'^(\d{1,2}):?(\d{2})$',
    ).firstMatch(cleaned);

    if (match == null) {
      return null;
    }

    final int? hour = int.tryParse(match.group(1)!);
    final int? minute = int.tryParse(match.group(2)!);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return _ClockTime(hour: hour, minute: minute);
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _dateKey(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');

    return '${value.year}-$month-$day';
  }

  static String _formatMinutes(int minutes) {
    if (minutes < 0) {
      return '0h 00m';
    }

    final int hours = minutes ~/ 60;
    final int remainder = minutes % 60;

    return '${hours}h ${remainder.toString().padLeft(2, '0')}m';
  }

  static String _displayDate(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');

    return '$day/$month/${value.year}';
  }
}

class _ClockTime {
  const _ClockTime({required this.hour, required this.minute});

  final int hour;
  final int minute;
}
