enum ParseWarningSeverity { information, warning, blocking }

class ParseWarning {
  const ParseWarning({
    required this.message,
    this.pageNumber,
    this.weekNumber,
    this.severity = ParseWarningSeverity.warning,
  });

  final String message;
  final int? pageNumber;
  final int? weekNumber;
  final ParseWarningSeverity severity;

  bool get preventsImport => severity == ParseWarningSeverity.blocking;
}
