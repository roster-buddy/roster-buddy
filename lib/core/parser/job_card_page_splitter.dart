class JobCardPageSplitter {
  const JobCardPageSplitter();

  static final RegExp _turnCodePattern = RegExp(
    r'\b(?:(?:VSTP|STP|LTP)[ \t]+)?W[O0Q]\s*[-:]?\s*(\d{2,4})\b',
    caseSensitive: false,
  );

  /// Splits one OCR page into individual Job Card text blocks.
  ///
  /// A page containing only one turn is returned unchanged.
  /// Introductory headings before the first WO turn are attached to the
  /// first Job Card rather than being discarded.
  List<String> split(String pageText) {
    final String page = pageText.trim();

    if (page.isEmpty) {
      return const <String>[];
    }

    final List<RegExpMatch> turnMatches = _turnCodePattern
        .allMatches(page)
        .toList(growable: false);

    if (turnMatches.length < 2) {
      return <String>[page];
    }

    final sections = <String>[];
    var sectionStart = 0;
    var previousTurn = turnMatches.first.group(1);
    for (final match in turnMatches.skip(1)) {
      final turn = match.group(1);
      final lineStart = page.lastIndexOf('\n', match.start - 1) + 1;
      final startsLine = page.substring(lineStart, match.start).trim().isEmpty;
      if (turn == previousTurn || !startsLine) {
        continue;
      }

      final precedingText = page.substring(sectionStart, match.start).trim();
      sections.add(precedingText);
      sectionStart = match.start;
      previousTurn = turn;
    }

    sections.add(page.substring(sectionStart).trim());
    return sections;
  }
}
