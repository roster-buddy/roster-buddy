class ParserUtils {
  const ParserUtils._();

  static final RegExp _timePattern = RegExp(
    r'(?<!\d)([0-2OILSB]?\d)[\.:;\s]?([0-5OILSB]\d)(?!\d)',
    caseSensitive: false,
  );

  static final RegExp _turnPattern = RegExp(
    r'\b(?:WO|W0|WQ|TURN)?\s*[-:]?\s*(\d{2,4})\b',
    caseSensitive: false,
  );

  static final RegExp _datePattern = RegExp(
    r'\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b',
  );

  static String normaliseWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> nonEmptyLines(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map(normaliseWhitespace)
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static String normaliseIdentifier(String? value) {
    if (value == null) return '';

    return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').trim();
  }

  static String? normalisePayrollNumber(String? value) {
    if (value == null) return null;

    final cleaned = _replaceCommonOcrDigits(
      value,
    ).replaceAll(RegExp(r'[^0-9]'), '').trim();

    return cleaned.isEmpty ? null : cleaned;
  }

  static String? normaliseDriverNumber(String? value) {
    if (value == null) return null;

    final cleaned = _replaceCommonOcrDigits(
      value,
    ).replaceAll(RegExp(r'[^0-9]'), '').trim();

    return cleaned.isEmpty ? null : cleaned;
  }

  static String? normaliseTurnNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final cleaned = _replaceCommonOcrDigits(
      value.toUpperCase(),
    ).replaceAll(RegExp(r'\bW[O0Q]\b'), 'WO');

    final labelledMatch = _turnPattern.firstMatch(cleaned);
    if (labelledMatch != null) {
      return labelledMatch.group(1);
    }

    final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 2 && digits.length <= 4) {
      return digits;
    }

    return null;
  }

  static String? normaliseTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final cleaned = _replaceCommonOcrDigits(value.toUpperCase());
    final match = _timePattern.firstMatch(cleaned);

    if (match == null) {
      return null;
    }

    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static List<String> extractTimes(String value) {
    final cleaned = _replaceCommonOcrDigits(value.toUpperCase());
    final results = <String>[];

    for (final match in _timePattern.allMatches(cleaned)) {
      final candidate = normaliseTime(match.group(0));
      if (candidate != null && !results.contains(candidate)) {
        results.add(candidate);
      }
    }

    return results;
  }

  static DateTime? parseDate(String? value, {int? defaultYear}) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final cleaned = _replaceCommonOcrDigits(value);
    final numericMatch = _datePattern.firstMatch(cleaned);

    if (numericMatch != null) {
      final day = int.tryParse(numericMatch.group(1) ?? '');
      final month = int.tryParse(numericMatch.group(2) ?? '');
      var year = int.tryParse(numericMatch.group(3) ?? '');

      if (day == null || month == null || year == null) {
        return null;
      }

      if (year < 100) {
        year += year >= 70 ? 1900 : 2000;
      }

      return safeDate(year, month, day);
    }

    final textDate = RegExp(
      r'\b(\d{1,2})(?:ST|ND|RD|TH)?\s+'
      r'(JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|'
      r'MAY|JUN(?:E)?|JUL(?:Y)?|AUG(?:UST)?|SEP(?:TEMBER)?|'
      r'OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)'
      r'(?:\s+(\d{2,4}))?\b',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (textDate == null) {
      return null;
    }

    final day = int.tryParse(textDate.group(1) ?? '');
    final month = monthNumber(textDate.group(2));
    var year = int.tryParse(textDate.group(3) ?? '') ?? defaultYear;

    if (day == null || month == null || year == null) {
      return null;
    }

    if (year < 100) {
      year += year >= 70 ? 1900 : 2000;
    }

    return safeDate(year, month, day);
  }

  static List<DateTime> extractDates(String value, {int? defaultYear}) {
    final results = <DateTime>[];

    for (final match in _datePattern.allMatches(value)) {
      final parsed = parseDate(match.group(0), defaultYear: defaultYear);
      if (parsed != null && !_containsDate(results, parsed)) {
        results.add(parsed);
      }
    }

    final textDatePattern = RegExp(
      r'\b\d{1,2}(?:ST|ND|RD|TH)?\s+'
      r'(?:JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|'
      r'MAY|JUN(?:E)?|JUL(?:Y)?|AUG(?:UST)?|SEP(?:TEMBER)?|'
      r'OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)'
      r'(?:\s+\d{2,4})?\b',
      caseSensitive: false,
    );

    for (final match in textDatePattern.allMatches(value)) {
      final parsed = parseDate(match.group(0), defaultYear: defaultYear);
      if (parsed != null && !_containsDate(results, parsed)) {
        results.add(parsed);
      }
    }

    return results;
  }

  static int? parseRosteredMinutes(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final time = normaliseTime(value);
    if (time != null) {
      final parts = time.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final decimalMatch = RegExp(
      r'\b(\d{1,2})[.,](\d{1,2})\b',
    ).firstMatch(_replaceCommonOcrDigits(value));

    if (decimalMatch != null) {
      final hours = int.tryParse(decimalMatch.group(1) ?? '');
      final decimal = int.tryParse(decimalMatch.group(2) ?? '');

      if (hours == null || decimal == null) {
        return null;
      }

      final divisor = decimalMatch.group(2)!.length == 1 ? 10 : 100;
      final minutes = (decimal / divisor * 60).round();

      return hours * 60 + minutes;
    }

    final minutesOnly = int.tryParse(
      _replaceCommonOcrDigits(value).replaceAll(RegExp(r'[^0-9]'), ''),
    );

    return minutesOnly;
  }

  static int calculateDutyMinutes(String? bookOn, String? bookOff) {
    final start = normaliseTime(bookOn);
    final end = normaliseTime(bookOff);

    if (start == null || end == null) {
      return 0;
    }

    final startParts = start.split(':');
    final endParts = end.split(':');

    final startMinutes =
        int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    var endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    if (endMinutes < startMinutes) {
      endMinutes += 24 * 60;
    }

    return endMinutes - startMinutes;
  }

  static int? monthNumber(String? value) {
    if (value == null) return null;

    final month = value.trim().toUpperCase();

    if (month.startsWith('JAN')) return DateTime.january;
    if (month.startsWith('FEB')) return DateTime.february;
    if (month.startsWith('MAR')) return DateTime.march;
    if (month.startsWith('APR')) return DateTime.april;
    if (month == 'MAY') return DateTime.may;
    if (month.startsWith('JUN')) return DateTime.june;
    if (month.startsWith('JUL')) return DateTime.july;
    if (month.startsWith('AUG')) return DateTime.august;
    if (month.startsWith('SEP')) return DateTime.september;
    if (month.startsWith('OCT')) return DateTime.october;
    if (month.startsWith('NOV')) return DateTime.november;
    if (month.startsWith('DEC')) return DateTime.december;

    return null;
  }

  static DateTime? safeDate(int year, int month, int day) {
    if (year < 1900 ||
        year > 2200 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }

    final result = DateTime(year, month, day);

    if (result.year != year || result.month != month || result.day != day) {
      return null;
    }

    return result;
  }

  static String _replaceCommonOcrDigits(String value) {
    return value
        .replaceAll('O', '0')
        .replaceAll('Q', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('|', '1')
        .replaceAll('S', '5')
        .replaceAll('B', '8');
  }

  static bool _containsDate(List<DateTime> dates, DateTime candidate) {
    return dates.any(
      (date) =>
          date.year == candidate.year &&
          date.month == candidate.month &&
          date.day == candidate.day,
    );
  }
}
