import '../models/document_type.dart';

class DocumentClassifier {
  const DocumentClassifier();

  DocumentType classify(List<String> pages) {
    final text = pages.join('\n').toUpperCase();

    // Explicit amendment headings win over leave codes and depot/turn text
    // inside their rows.
    if (_looksLike48Hour(text)) {
      return DocumentType.fortyEightHourAmendment;
    }

    if (_looksLike7Day(text)) {
      return DocumentType.sevenDayAmendment;
    }

    if (_looksLike10Day(text)) {
      return DocumentType.tenDayAmendment;
    }

    if (_looksLikeJobCard(text)) {
      return DocumentType.jobCard;
    }

    if (_looksLikeAnnualLeave(text)) {
      return DocumentType.annualLeaveRoster;
    }

    if (_looksLikeBaseRoster(text)) {
      return DocumentType.baseRoster;
    }

    if (RegExp(r'\bSUNDAY\s+(?:AMENDMENT|DUTIES|ROSTER|SHEET)\b').hasMatch(text)) {
      return DocumentType.fortyEightHourAmendment;
    }

    return DocumentType.unknown;
  }

  bool _looksLikeBaseRoster(String text) {
    return text.contains('WEEK') && text.contains('SUN');
  }

  bool _looksLike10Day(String text) {
    return text.contains('10 DAY') || text.contains('10-DAY');
  }

  bool _looksLike7Day(String text) {
    return text.contains('7 DAY') || text.contains('7-DAY');
  }

  bool _looksLike48Hour(String text) {
    return text.contains('48 HOUR') || text.contains('48-HOUR');
  }

  bool _looksLikeAnnualLeave(String text) {
    return text.contains('ANNUAL LEAVE');
  }

  bool _looksLikeJobCard(String text) {
    return RegExp(r'\bJOB\s+CARD\b').hasMatch(text) ||
        (RegExp(r'\bW[O0Q]\s*[-:]?\s*\d{2,4}\b').hasMatch(text) &&
            RegExp(r'\b(?:DAY(?:\s+CODE)?|DAYS?|APPLIES)\s*[:\-]?\s*(?:SUN|SU|SO|SAO|SX)\b').hasMatch(text));
  }
}
