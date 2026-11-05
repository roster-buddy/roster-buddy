import '../models/document_type.dart';

class DocumentClassifier {
  const DocumentClassifier();

  DocumentType classify(List<String> pages) {
    final text = pages.join('\n').toUpperCase();

    // Explicit amendment headings win over leave codes and depot/turn text
    // inside their rows.
    if (hasConflictingAmendmentStamps(pages)) return DocumentType.unknown;
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

  Set<DocumentType> amendmentStamps(List<String> pages) {
    final text = pages.join('\n').toUpperCase();
    return {
      if (_looksLike7Day(text)) DocumentType.sevenDayAmendment,
      if (_looksLike10Day(text)) DocumentType.tenDayAmendment,
      if (_looksLike48Hour(text)) DocumentType.fortyEightHourAmendment,
    };
  }

  bool hasConflictingAmendmentStamps(List<String> pages) =>
      amendmentStamps(pages).length > 1;

  bool _looksLikeBaseRoster(String text) {
    return text.contains('WEEK') && text.contains('SUN');
  }

  bool _looksLike10Day(String text) {
    return RegExp(r'\b(?:10|TEN)[\s-]*D\s*AYS?\b').hasMatch(text);
  }

  bool _looksLike7Day(String text) {
    return RegExp(r'\b(?:7|SEVEN)[\s-]*D\s*AYS?\b').hasMatch(text);
  }

  bool _looksLike48Hour(String text) {
    return RegExp(r'\b(?:48|FORTY[\s-]*EIGHT)[\s-]*(?:H\s*O\s*U\s*R\s*S?|HRS?|H)\b').hasMatch(text);
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
