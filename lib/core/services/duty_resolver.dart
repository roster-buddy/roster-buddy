import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/duty.dart';
import '../models/duty_type.dart';
import '../models/roster_source.dart';

class DutyResolver {
  DutyResolver({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _profileTableName = 'driver_profiles';
  static const String _dutyTableName = 'document_duties';
  static const String _annualLeavePeriodTableName = 'annual_leave_periods';
  static const String _manualDutyTableName = 'manual_duties';

  /// Returns the highest-priority duty applicable to the signed-in user
  /// on [date].
  ///
  /// Priority:
  /// Base Roster → 10-Day → 7-Day → 48-Hour.
  Future<Duty?> getDutyForDate(DateTime date) async {
    final List<Duty> duties = await getDutiesForDate(date);

    if (duties.isEmpty) {
      return null;
    }

    return duties.first;
  }

  /// Returns every applicable duty for [date], ordered from the highest
  /// priority source to the lowest.
  ///
  /// Keeping all versions available allows a future date-details screen to
  /// show the Base, 10-Day, 7-Day and 48-Hour history.
  Future<List<Duty>> getDutiesForDate(DateTime date) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const DutyResolverException(
        'You must be signed in before loading roster duties.',
      );
    }

    final Map<String, dynamic>? profile = await _supabase
        .from(_profileTableName)
        .select('payroll_number, driver_number')
        .eq('user_id', user.id)
        .maybeSingle();

    if (profile == null) {
      return const [];
    }

    final String? payrollNumber = _normaliseIdentifier(
      profile['payroll_number'],
    );
    final String? driverNumber = _normaliseIdentifier(profile['driver_number']);

    if (payrollNumber == null && driverNumber == null) {
      return const [];
    }

    final List<dynamic> response = await _supabase
        .from(_dutyTableName)
        .select(
          'duty_date, source, duty_type, turn_number, book_on, book_off, '
          'rostered_minutes, remarks, driver_number, payroll_number, '
          'driver_name, depot, amendment_code, mileage, page_number, raw_text',
        )
        .eq('duty_date', _databaseDate(date));

    final List<Duty> duties = response
        .whereType<Map<String, dynamic>>()
        .where(
          (row) => _matchesProfile(
            row: row,
            payrollNumber: payrollNumber,
            driverNumber: driverNumber,
          ),
        )
        .map(_dutyFromRow)
        .toList();

    if (driverNumber != null) {
      final String databaseDate = _databaseDate(date);

      final List<dynamic> annualLeaveResponse = await _supabase
          .from(_annualLeavePeriodTableName)
          .select(
            'period_type, start_date, end_date, '
            'annual_leave_allocations!inner('
            'driver_number, surname, depot, source, is_confirmed, page_number'
            ')',
          )
          .lte('start_date', databaseDate)
          .gte('end_date', databaseDate)
          .eq('annual_leave_allocations.driver_number', driverNumber)
          .eq('annual_leave_allocations.is_confirmed', true);

      duties.addAll(
        annualLeaveResponse
            .whereType<Map<String, dynamic>>()
            .map((row) => _annualLeaveDutyFromRow(row: row, date: date))
            .whereType<Duty>(),
      );
    }

    final List<dynamic> manualDutyResponse = await _supabase
        .from(_manualDutyTableName)
        .select(
          'duty_date, duty_type, turn_number, book_on, book_off, '
          'rostered_minutes, remarks, manual_change_type',
        )
        .eq('user_id', user.id)
        .eq('duty_date', _databaseDate(date));

    duties.addAll(
      manualDutyResponse.whereType<Map<String, dynamic>>().map(
        _manualDutyFromRow,
      ),
    );

    duties.sort(_compareDuties);

    return List<Duty>.unmodifiable(duties);
  }

  /// Resolves an already-loaded collection without making a database request.
  ///
  /// This will also be useful for unit tests and when Calendar loads a range
  /// of duties in one query.
  Duty? resolve(Iterable<Duty> duties) {
    final List<Duty> candidates = duties.toList();

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort(_compareDuties);
    return candidates.first;
  }

  static int _compareDuties(Duty first, Duty second) {
    final int priorityComparison = second.source.priority.compareTo(
      first.source.priority,
    );

    if (priorityComparison != 0) {
      return priorityComparison;
    }

    // Provides deterministic ordering where more than one parsed record from
    // the same source applies to the same date.
    return second.uniqueKey.compareTo(first.uniqueKey);
  }

  static bool _matchesProfile({
    required Map<String, dynamic> row,
    required String? payrollNumber,
    required String? driverNumber,
  }) {
    final String? rowPayroll = _normaliseIdentifier(row['payroll_number']);
    final String? rowDriver = _normaliseIdentifier(row['driver_number']);

    final bool payrollMatches =
        payrollNumber != null &&
        rowPayroll != null &&
        payrollNumber == rowPayroll;

    final bool driverMatches =
        driverNumber != null && rowDriver != null && driverNumber == rowDriver;

    return payrollMatches || driverMatches;
  }

  static Duty _manualDutyFromRow(Map<String, dynamic> row) {
    final String? dateValue = _nullableString(row['duty_date']);

    if (dateValue == null) {
      throw const DutyResolverException(
        'A manual duty is missing its duty date.',
      );
    }

    return Duty(
      date: DateTime.parse(dateValue),
      source: RosterSource.manual,
      dutyType: _dutyType(row['duty_type']),
      turnNumber: _nullableString(row['turn_number']),
      bookOn: _databaseTimeToAppTime(row['book_on']),
      bookOff: _databaseTimeToAppTime(row['book_off']),
      rosteredMinutes: _nullableInt(row['rostered_minutes']),
      remarks: _nullableString(row['remarks']),
      rawText: _nullableString(row['manual_change_type']),
    );
  }

  static Duty? _annualLeaveDutyFromRow({
    required Map<String, dynamic> row,
    required DateTime date,
  }) {
    final Object? relatedValue = row['annual_leave_allocations'];
    Map<String, dynamic>? allocation;

    if (relatedValue is Map<String, dynamic>) {
      allocation = relatedValue;
    } else if (relatedValue is Map) {
      allocation = Map<String, dynamic>.from(relatedValue);
    } else if (relatedValue is List && relatedValue.isNotEmpty) {
      final Object? first = relatedValue.first;

      if (first is Map<String, dynamic>) {
        allocation = first;
      } else if (first is Map) {
        allocation = Map<String, dynamic>.from(first);
      }
    }

    if (allocation == null) {
      return null;
    }

    final String? driverNumber = _nullableString(allocation['driver_number']);

    if (driverNumber == null) {
      return null;
    }

    final String periodLabel = _annualLeavePeriodLabel(row['period_type']);

    return Duty(
      date: DateTime(date.year, date.month, date.day),
      source: RosterSource.annualLeave,
      dutyType: DutyType.annualLeave,
      remarks: periodLabel,
      driverNumber: driverNumber,
      driverName: _nullableString(allocation['surname']),
      depot: _nullableString(allocation['depot']),
      pageNumber: _nullableInt(allocation['page_number']),
      rawText:
          '${_nullableString(row['start_date']) ?? ''} - '
          '${_nullableString(row['end_date']) ?? ''}',
    );
  }

  static String _annualLeavePeriodLabel(Object? value) {
    switch (_nullableString(value)) {
      case 'spring':
        return 'Spring block annual leave';
      case 'summer_first_week':
        return 'Summer block annual leave – first week';
      case 'summer_second_week':
        return 'Summer block annual leave – second week';
      case 'winter':
        return 'Winter block annual leave';
      default:
        return 'Block annual leave';
    }
  }

  static Duty _dutyFromRow(Map<String, dynamic> row) {
    final String? dateValue = _nullableString(row['duty_date']);

    if (dateValue == null) {
      throw const DutyResolverException(
        'A stored duty is missing its duty date.',
      );
    }

    return Duty(
      date: DateTime.parse(dateValue),
      source: _rosterSource(row['source']),
      dutyType: _dutyType(row['duty_type']),
      turnNumber: _nullableString(row['turn_number']),
      bookOn: _databaseTimeToAppTime(row['book_on']),
      bookOff: _databaseTimeToAppTime(row['book_off']),
      rosteredMinutes: _nullableInt(row['rostered_minutes']),
      remarks: _nullableString(row['remarks']),
      driverNumber: _nullableString(row['driver_number']),
      payrollNumber: _nullableString(row['payroll_number']),
      driverName: _nullableString(row['driver_name']),
      depot: _nullableString(row['depot']),
      amendmentCode: _nullableString(row['amendment_code']),
      mileage: _nullableString(row['mileage']),
      pageNumber: _nullableInt(row['page_number']),
      rawText: _nullableString(row['raw_text']),
    );
  }

  static RosterSource _rosterSource(Object? value) {
    switch (_nullableString(value)) {
      case 'base_roster':
        return RosterSource.baseRoster;
      case '10_day':
        return RosterSource.tenDay;
      case '7_day':
        return RosterSource.sevenDay;
      case '48_hour':
        return RosterSource.fortyEightHour;
      case 'annual_leave':
        return RosterSource.annualLeave;
      default:
        throw DutyResolverException(
          'Unsupported stored roster source: ${value ?? 'null'}.',
        );
    }
  }

  static DutyType _dutyType(Object? value) {
    switch (_nullableString(value)) {
      case 'working':
        return DutyType.working;
      case 'training':
        return DutyType.training;
      case 'medical':
        return DutyType.medical;
      case 'rest_day':
        return DutyType.restDay;
      case 'annual_leave':
        return DutyType.annualLeave;
      case 'sick':
        return DutyType.sick;
      case 'public_holiday':
        return DutyType.publicHoliday;
      case 'unavailable':
        return DutyType.unavailable;
      case 'unknown':
        return DutyType.unknown;
      default:
        throw DutyResolverException(
          'Unsupported stored duty type: ${value ?? 'null'}.',
        );
    }
  }

  static String _databaseDate(DateTime value) {
    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  static String? _databaseTimeToAppTime(Object? value) {
    final String? time = _nullableString(value);

    if (time == null) {
      return null;
    }

    return time.length >= 5 ? time.substring(0, 5) : time;
  }

  static String? _normaliseIdentifier(Object? value) {
    final String? identifier = _nullableString(value);

    if (identifier == null) {
      return null;
    }

    return identifier.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  static String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final String cleaned = value.toString().trim();

    return cleaned.isEmpty ? null : cleaned;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString().trim());
  }
}

class DutyResolverException implements Exception {
  const DutyResolverException(this.message);

  final String message;

  @override
  String toString() => message;
}
