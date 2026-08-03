class JobCardPageSplitter {
  const JobCardPageSplitter();

  static final RegExp _turnStartPattern = RegExp(
    r'(?=\bW[O0Q]\s*[-:]?\s*\d{2,4}\b)',
    caseSensitive: false,
  );

  static final RegExp _turnCodePattern = RegExp(
    r'\bW[O0Q]\s*[-:]?\s*\d{2,4}\b',
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

    if (turnMatches.isEmpty || turnMatches.length == 1) {
      return <String>[page];
    }

    final String heading = page.substring(0, turnMatches.first.start).trim();

    final List<String> rawSections = page
        .substring(turnMatches.first.start)
        .split(_turnStartPattern)
        .map((String section) => section.trim())
        .where((String section) => section.isNotEmpty)
        .toList(growable: false);

    if (rawSections.isEmpty) {
      return <String>[page];
    }

    final List<String> sections = <String>[];

    for (int index = 0; index < rawSections.length; index++) {
      final String section = index == 0 && heading.isNotEmpty
          ? '$heading\n${rawSections[index]}'
          : rawSections[index];

      if (_turnCodePattern.hasMatch(section)) {
        sections.add(section);
      }
    }

    return sections.isEmpty ? <String>[page] : sections;
  }
}
