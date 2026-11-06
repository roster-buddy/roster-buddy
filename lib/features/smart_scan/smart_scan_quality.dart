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
