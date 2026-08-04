import 'dart:math' as math;

import 'smart_scan_result.dart';

class SmartScanPageTextReconstructor {
  SmartScanPageTextReconstructor._();

  static List<String> reconstructPages(Iterable<SmartScanResult> results) {
    return results
        .map(reconstruct)
        .where((String text) => text.trim().isNotEmpty)
        .toList(growable: false);
  }

  static String reconstruct(SmartScanResult result) {
    if (result.lines.isEmpty) {
      return result.fullText;
    }

    final List<SmartScanTextLine> sortedLines =
        List<SmartScanTextLine>.from(result.lines)..sort((first, second) {
          final int topComparison = first.top.compareTo(second.top);

          if (topComparison != 0) {
            return topComparison;
          }

          return first.left.compareTo(second.left);
        });

    final List<List<SmartScanTextLine>> rows = <List<SmartScanTextLine>>[];

    for (final SmartScanTextLine line in sortedLines) {
      if (line.text.trim().isEmpty) {
        continue;
      }

      if (rows.isEmpty) {
        rows.add(<SmartScanTextLine>[line]);
        continue;
      }

      final List<SmartScanTextLine> currentRow = rows.last;

      final double currentTop =
          currentRow
              .map((SmartScanTextLine item) => item.top)
              .reduce((double first, double second) => first + second) /
          currentRow.length;

      final double lineHeight = math.max(1, line.bottom - line.top);

      final double tolerance = math.max(10, lineHeight * 0.65);

      if ((line.top - currentTop).abs() <= tolerance) {
        currentRow.add(line);
      } else {
        rows.add(<SmartScanTextLine>[line]);
      }
    }

    final List<String> reconstructedRows = <String>[];

    for (final List<SmartScanTextLine> row in rows) {
      row.sort((first, second) => first.left.compareTo(second.left));

      final String rowText = row
          .map((SmartScanTextLine line) => line.text.trim())
          .where((String text) => text.isNotEmpty)
          .join('  ');

      if (rowText.isNotEmpty) {
        reconstructedRows.add(rowText);
      }
    }

    if (reconstructedRows.isEmpty) {
      return result.fullText;
    }

    return reconstructedRows.join('\n');
  }
}
