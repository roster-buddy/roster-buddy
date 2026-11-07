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
      final text = line.text.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
      for (var day = 0; day < days.length; day++) {
        if (text.contains(days[day])) anchors[day] = line.left;
      }
    }
    final lines = List<SmartScanTextLine>.from(result.lines)
      ..sort((a, b) => a.top.compareTo(b.top));
    if (lines.isEmpty) return result.fullText;

    final maxRight = lines.map((line) => line.right).reduce(math.max);
    final numericLabels = lines.where((line) {
      final digits = line.text.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.isNotEmpty &&
          digits.length <= 4 &&
          line.left < maxRight * 0.2;
    }).toList();

    double sunday;
    double spacing;
    final anchorDays = anchors.keys.toList()..sort();
    final hasSeparatedHeadings = anchorDays.length >= 3 &&
        anchors[anchorDays.last]! > anchors[anchorDays.first]!;
    if (hasSeparatedHeadings) {
      final firstDay = anchorDays.first;
      final lastDay = anchorDays.last;
      spacing =
          (anchors[lastDay]! - anchors[firstDay]!) / (lastDay - firstDay);
      sunday = anchors[firstDay]! - spacing * firstDay;
    } else if (numericLabels.isNotEmpty) {
      final leftEdge = numericLabels.map((line) => line.left).reduce(math.min);
      final mainGridLabels = numericLabels.where(
        (line) => line.left <= leftEdge + maxRight * 0.04,
      );
      final identityRight = mainGridLabels
          .map((line) => line.right)
          .reduce(math.max);
      sunday = identityRight + maxRight * 0.005;
      spacing = (maxRight - sunday) / 7;
    } else {
      return reconstruct(result);
    }
    if (spacing <= 0) return reconstruct(result);
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
            final column = line.left < sunday - spacing * 0.03
                ? 0
                : day.clamp(0, 6) + 1;
            cells[column].add(line.text.trim());
          }
          return cells.map((cell) => cell.join(' ')).join(' | ');
        })
        .where((row) {
          final firstCell = row.split('|').first.trim();
          final digits = firstCell.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.length == 4) return true;
          final lineNumber = int.tryParse(digits);
          return lineNumber != null && lineNumber >= 1 && lineNumber <= 54;
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
