import 'table_extractor.dart';

class AmendmentColumnMap {
  const AmendmentColumnMap({
    this.name,
    this.payrollNumber,
    this.depot,
    this.amendmentCode,
    this.turnNumber,
    this.bookOn,
    this.bookOff,
    this.rosteredHours,
    this.mileage,
    this.remarks,
    this.headerPageNumber,
    this.headerLineNumber,
  });

  final int? name;
  final int? payrollNumber;
  final int? depot;
  final int? amendmentCode;
  final int? turnNumber;
  final int? bookOn;
  final int? bookOff;
  final int? rosteredHours;
  final int? mileage;
  final int? remarks;

  final int? headerPageNumber;
  final int? headerLineNumber;

  bool get hasPayrollNumber => payrollNumber != null;

  bool get hasTurnNumber => turnNumber != null;

  bool get hasBookOn => bookOn != null;

  bool get hasBookOff => bookOff != null;

  bool get hasRequiredColumns =>
      hasPayrollNumber && (hasTurnNumber || hasBookOn || hasBookOff);

  int get detectedColumnCount {
    return [
      name,
      payrollNumber,
      depot,
      amendmentCode,
      turnNumber,
      bookOn,
      bookOff,
      rosteredHours,
      mileage,
      remarks,
    ].whereType<int>().length;
  }

  String? valueAt(ExtractedTableRow row, int? columnIndex) {
    if (columnIndex == null) {
      return null;
    }

    return row.columnAt(columnIndex);
  }

  String? nameValue(ExtractedTableRow row) {
    return valueAt(row, name);
  }

  String? payrollValue(ExtractedTableRow row) {
    return valueAt(row, payrollNumber);
  }

  String? depotValue(ExtractedTableRow row) {
    return valueAt(row, depot);
  }

  String? amendmentCodeValue(ExtractedTableRow row) {
    return valueAt(row, amendmentCode);
  }

  String? turnValue(ExtractedTableRow row) {
    return valueAt(row, turnNumber);
  }

  String? bookOnValue(ExtractedTableRow row) {
    return valueAt(row, bookOn);
  }

  String? bookOffValue(ExtractedTableRow row) {
    return valueAt(row, bookOff);
  }

  String? rosteredHoursValue(ExtractedTableRow row) {
    return valueAt(row, rosteredHours);
  }

  String? mileageValue(ExtractedTableRow row) {
    return valueAt(row, mileage);
  }

  String? remarksValue(ExtractedTableRow row) {
    return valueAt(row, remarks);
  }
}

class AmendmentColumnDetector {
  const AmendmentColumnDetector();

  AmendmentColumnMap? detect(List<ExtractedTableRow> rows) {
    AmendmentColumnMap? bestMatch;

    for (final row in rows) {
      final candidate = _mapHeaderRow(row);

      if (candidate == null) {
        continue;
      }

      if (bestMatch == null ||
          candidate.detectedColumnCount > bestMatch.detectedColumnCount) {
        bestMatch = candidate;
      }
    }

    return bestMatch;
  }

  AmendmentColumnMap? _mapHeaderRow(ExtractedTableRow row) {
    if (row.columns.length < 3) {
      return null;
    }

    int? name;
    int? payrollNumber;
    int? depot;
    int? amendmentCode;
    int? turnNumber;
    int? bookOn;
    int? bookOff;
    int? rosteredHours;
    int? mileage;
    int? remarks;

    for (var index = 0; index < row.columns.length; index++) {
      final header = _normaliseHeader(row.columns[index]);

      if (_matchesAny(header, const ['NAME', 'DRIVER NAME', 'SURNAME'])) {
        name ??= index;
        continue;
      }

      if (_matchesAny(header, const [
        'PAY NO',
        'PAY NUMBER',
        'PAYROLL',
        'PAYROLL NO',
        'PAYROLL NUMBER',
        'PAYNO',
      ])) {
        payrollNumber ??= index;
        continue;
      }

      if (_matchesAny(header, const ['DEPOT', 'LOCATION'])) {
        depot ??= index;
        continue;
      }

      if (_matchesAny(header, const [
        'AMEND',
        'AMENDMENT',
        'CODE',
        'UNAVAILABILITY',
      ])) {
        amendmentCode ??= index;
        continue;
      }

      if (_matchesAny(header, const [
        'TURN',
        'TURN NO',
        'TURN NUMBER',
        'DUTY',
        'DUTY NO',
      ])) {
        turnNumber ??= index;
        continue;
      }

      if (_matchesAny(header, const [
        'BOOK ON',
        'BOOKON',
        'ON',
        'START',
        'START TIME',
      ])) {
        bookOn ??= index;
        continue;
      }

      if (_matchesAny(header, const [
        'BOOK OFF',
        'BOOKOFF',
        'OFF',
        'FINISH',
        'FINISH TIME',
      ])) {
        bookOff ??= index;
        continue;
      }

      if (_matchesAny(header, const [
        'ROSTERED HOURS',
        'ROSTER HOURS',
        'HOURS',
        'ROSTERED',
        'DURATION',
      ])) {
        rosteredHours ??= index;
        continue;
      }

      if (_matchesAny(header, const ['MILEAGE', 'MILES'])) {
        mileage ??= index;
        continue;
      }

      if (_matchesAny(header, const [
        'REMARKS',
        'REMARK',
        'COMMENTS',
        'NOTES',
      ])) {
        remarks ??= index;
      }
    }

    final result = AmendmentColumnMap(
      name: name,
      payrollNumber: payrollNumber,
      depot: depot,
      amendmentCode: amendmentCode,
      turnNumber: turnNumber,
      bookOn: bookOn,
      bookOff: bookOff,
      rosteredHours: rosteredHours,
      mileage: mileage,
      remarks: remarks,
      headerPageNumber: row.pageNumber,
      headerLineNumber: row.lineNumber,
    );

    if (!result.hasRequiredColumns || result.detectedColumnCount < 3) {
      return null;
    }

    return result;
  }

  String _normaliseHeader(String value) {
    return value
        .toUpperCase()
        .replaceAll('&', ' AND ')
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _matchesAny(String header, List<String> candidates) {
    for (final candidate in candidates) {
      if (header == candidate || header.contains(candidate)) {
        return true;
      }
    }

    return false;
  }
}
