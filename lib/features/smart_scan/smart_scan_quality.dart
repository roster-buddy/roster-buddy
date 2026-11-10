class SmartScanQuality {
  SmartScanQuality._();

  static final RegExp _identity = RegExp(
    r'\b[0-9]{4,8}\s+[A-Za-z]{2,5}\b',
  );
  static final RegExp _clock = RegExp(r'\b(?:[01]?[0-9]|2[0-3]):[0-9]{2}\b');
  static final RegExp _clockOrHours = RegExp(
    r'\b(?:[01]?[0-9]|2[0-3])[:.][0-9]{2}\b',
  );
  static final RegExp _noDuty = RegExp(
    r'\b(?:ND|NDNA|NONA|NO|ALD|ZS|SF)\b',
    caseSensitive: false,
  );

  /// The secure service is deliberately the quick first pass. A full roster
  /// receives a local rescue reading when too many identified payroll rows
  /// lack either two clocks or a recognised non-working code.
  static bool needsLocalRescue(String text) {
    final upper = text.toUpperCase();
    final weekdayHeadings = const [
      'SUNDAY',
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
    ].where(upper.contains).length;
    if (weekdayHeadings >= 3) {
      if (upper.contains('NO DUTY')) return true;

      // Printed Base Rosters often have a numbered duty row followed by
      // a separate four-digit roster identity/route row. A cloud OCR pass
      // can preserve the text while losing the positions needed to pair
      // the rows into seven day columns. Request positioned local OCR.
      final lines = text.split(RegExp(r'\r?\n'));
      final weekLine = RegExp(r'^\s*(?:WEEK\s*)?(?:[1-9]|[1-4][0-9]|5[0-4])\s+(?=\S)', caseSensitive: false);
      final rosterLine = RegExp(r'^\s*\d{4}\b');
      for (var i = 0; i < lines.length - 1; i++) {
        if (!weekLine.hasMatch(lines[i])) continue;
        for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
          if (weekLine.hasMatch(lines[j])) break;
          if (rosterLine.hasMatch(lines[j])) return true;
        }
      }
    }

    final rows = text.split(RegExp(r'\r?\n'))
        .where((row) => _identity.hasMatch(row))
        .toList(growable: false);
    if (rows.length < 5) return false;
    final complete = rows.where((row) {
      final clocks = _clock.allMatches(row).length;
      final clockOrHours = _clockOrHours.allMatches(row).length;
      return clocks >= 2 || clockOrHours >= 3 || _noDuty.hasMatch(row);
    }).length;
    return complete < (rows.length * .85).ceil();
  }
}
