class SmartScanTextLine {
  const SmartScanTextLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

class SmartScanResult {
  const SmartScanResult({
    required this.fullText,
    required this.lines,
    this.confidence,
  });

  final double? confidence;
  final String fullText;
  final List<SmartScanTextLine> lines;

  bool get hasText => fullText.trim().isNotEmpty;
}
