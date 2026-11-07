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

  /// Preserve empty day cells using the printed weekday column positions.
  static String reconstructBaseRoster(SmartScanResult result) {
    const days = [
      'SUNDAY',
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
    ];
    final anchors = <int, double>{};
    for (final line in result.lines) {
      final text = line.text.trim().toUpperCase();
      final day = days.indexOf(text);
      if (day >= 0) anchors[day] = line.left;
    }
    // Do not guess column positions unless the Monday–Saturday headings exist.
    if (!List.generate(6, (i) => i + 1).every(anchors.containsKey)) {
      return reconstruct(result);
    }
    final spacing = (anchors[6]! - anchors[1]!) / 5;
    if (spacing <= 0) return reconstruct(result);
    final sunday = anchors[1]! - spacing;
    final lines = List<SmartScanTextLine>.from(result.lines)
      ..sort((a, b) => a.top.compareTo(b.top));
    final rows = <List<SmartScanTextLine>>[];
    for (final line in lines) {
      if (rows.isEmpty ||
          (line.top - rows.last.first.top).abs() >
              math.max(2, (line.bottom - line.top) * 0.55)) {
        rows.add([line]);
      } else {
        rows.last.add(line);
      }
    }
    return rows
        .map((row) {
          final cells = List.generate(8, (_) => <String>[]);
          row.sort((a, b) => a.left.compareTo(b.left));
          for (final line in row) {
            final day = ((line.left - sunday + spacing * 0.15) / spacing)
                .floor();
            final column = line.left < sunday - spacing * 0.15
                ? 0
                : day.clamp(0, 6) + 1;
            cells[column].add(line.text.trim());
          }
          return cells.map((cell) => cell.join(' ')).join(' | ');
        })
        .join('\n');
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

    final heights =
        sortedLines
            .map((line) => math.max(1.0, line.bottom - line.top))
            .toList()
          ..sort();
    final typicalHeight = heights.isEmpty ? 12.0 : heights[heights.length ~/ 2];

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

      final double tolerance = math.max(
        10,
        math.min(lineHeight, typicalHeight) * 0.65,
      );

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
