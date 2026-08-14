import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/annual_leave_block_override.dart';
import '../models/duty.dart';
import '../models/duty_type.dart';
import '../models/roster_source.dart';
import 'sunday_availability_service.dart';

class DutyResolver {
  DutyResolver({SupabaseClient? supabase}) : _supabaseOverride = supabase;

  final SupabaseClient? _supabaseOverride;

  SupabaseClient get _supabase => _supabaseOverride ?? Supabase.instance.client;

  static const String _profileTableName = 'driver_profiles';
  static const String _dutyTableName = 'document_duties';
  static const String _annualLeavePeriodTableName = 'annual_leave_periods';
  static const String _annualLeaveRequestTableName = 'annual_leave_requests';
  static const String _annualLeaveBlockOverrideTableName =
      'annual_leave_block_overrides';
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
        .select(
          'payroll_number, roster_number, driver_number, '
          'permanently_unavailable_sundays',
        )
        .eq('user_id', user.id)
        .maybeSingle();

    if (profile == null) {
      return const [];
    }

    final String? payrollNumber = _normaliseIdentifier(
      profile['payroll_number'],
    );

    final String? rosterNumber = _normaliseIdentifier(
      profile['roster_number'] ?? profile['driver_number'],
    );

    final String? driverNumber = _normaliseIdentifier(profile['driver_number']);
    final bool permanentlyUnavailableSundays =
        profile['permanently_unavailable_sundays'] == true;

    if (payrollNumber == null && rosterNumber == null && driverNumber == null) {
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
          (row) => matchesProfile(
            row: row,
            payrollNumber: payrollNumber,
            rosterNumber: rosterNumber,
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

    final Map<String, dynamic>? grantedFloatingLeave = await _supabase
        .from(_annualLeaveRequestTableName)
        .select(
          'id, leave_date, status, request_type, notes, requested_at, '
          'decision_at',
        )
        .eq('user_id', user.id)
        .eq('leave_date', _databaseDate(date))
        .eq('request_type', 'floating')
        .eq('status', 'granted')
        .maybeSingle();

    if (grantedFloatingLeave != null) {
      duties.add(_floatingAnnualLeaveDutyFromRow(grantedFloatingLeave));
    }

    final List<dynamic> blockOverrideResponse = await _supabase
        .from(_annualLeaveBlockOverrideTableName)
        .select(
          'id, leave_year, period_type, '
          'original_start_date, original_end_date, '
          'override_start_date, override_end_date, '
          'change_type, swap_driver_number, swap_reference, notes',
        )
        .eq('user_id', user.id)
        .eq('leave_year', date.year);

    final List<AnnualLeaveBlockOverride> blockOverrides = blockOverrideResponse
        .whereType<Map<String, dynamic>>()
        .map(AnnualLeaveBlockOverride.fromMap)
        .toList(growable: false);

    final Set<String> officialBlockPeriodKeys =
        await _getOfficialBlockPeriodKeys(
          driverNumber: driverNumber,
          startYear: date.year,
          endYear: date.year,
        );

    final List<AnnualLeaveBlockOverride> effectiveBlockOverrides =
        _effectiveBlockOverrides(
          overrides: blockOverrides,
          officialPeriodKeys: officialBlockPeriodKeys,
        );

    _applyBlockOverridesForDate(
      duties: duties,
      date: date,
      overrides: effectiveBlockOverrides,
    );

    if (date.weekday == DateTime.sunday) {
      final SundayAvailabilityService sundayAvailabilityService =
          SundayAvailabilityService(supabase: _supabase);

      final bool explicitlyAvailable = await sundayAvailabilityService
          .isSundayExplicitlyAvailable(date);

      if (permanentlyUnavailableSundays) {
        _applyPermanentSundayUnavailability(
          duties: duties,
          sundayDates: <String>{_databaseDate(date)},
          explicitlyAvailableSundayDates: explicitlyAvailable
              ? <String>{_databaseDate(date)}
              : const <String>{},
        );
      } else {
        final Set<String> postBlockSundayDates = await _getPostBlockSundayDates(
          startDate: date,
          endDate: date,
          driverNumber: driverNumber,
          overrides: effectiveBlockOverrides,
        );

        if (postBlockSundayDates.contains(_databaseDate(date))) {
          _applyPostBlockSundayUnavailability(
            duties: duties,
            postBlockSundayDates: postBlockSundayDates,
            explicitlyAvailableSundayDates: explicitlyAvailable
                ? <String>{_databaseDate(date)}
                : const <String>{},
          );
        }
      }
    }

    final List<dynamic> manualDutyResponse = await _supabase
        .from(_manualDutyTableName)
        .select(
          'duty_date, duty_type, turn_number, book_on, book_off, '
          'rostered_minutes, remarks, manual_change_type, updated_at',
        )
        .eq('user_id', user.id)
        .eq('duty_date', _databaseDate(date));

    final Map<String, dynamic>? latestManualDuty = _latestManualDutyForDate(
      manualDutyResponse,
    );

    if (latestManualDuty != null) {
      duties.add(_manualDutyFromRow(latestManualDuty));
    }

    duties.sort(_compareDuties);

    return List<Duty>.unmodifiable(duties);
  }

  /// Loads and resolves every duty between [startDate] and [endDate],
  /// inclusive.
  ///
  /// The signed-in driver's profile is loaded once, followed by one query
  /// each for parsed roster duties, Annual Leave and manual duties.
  Future<Map<String, Duty>> getResolvedDutiesForRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final DateTime start = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final DateTime end = DateTime(endDate.year, endDate.month, endDate.day);

    if (end.isBefore(start)) {
      throw const DutyResolverException(
        'The roster range end date cannot be before the start date.',
      );
    }

    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const DutyResolverException(
        'You must be signed in before loading roster duties.',
      );
    }

    final Map<String, dynamic>? profile = await _supabase
        .from(_profileTableName)
        .select(
          'payroll_number, roster_number, driver_number, '
          'permanently_unavailable_sundays',
        )
        .eq('user_id', user.id)
        .maybeSingle();

    if (profile == null) {
      return const <String, Duty>{};
    }

    final String? payrollNumber = _normaliseIdentifier(
      profile['payroll_number'],
    );

    final String? rosterNumber = _normaliseIdentifier(
      profile['roster_number'] ?? profile['driver_number'],
    );

    final String? driverNumber = _normaliseIdentifier(profile['driver_number']);
    final bool permanentlyUnavailableSundays =
        profile['permanently_unavailable_sundays'] == true;

    if (payrollNumber == null && rosterNumber == null && driverNumber == null) {
      return const <String, Duty>{};
    }

    final String databaseStart = _databaseDate(start);
    final String databaseEnd = _databaseDate(end);

    final List<Duty> duties = <Duty>[];

    final List<dynamic> parsedDutyResponse = await _supabase
        .from(_dutyTableName)
        .select(
          'duty_date, source, duty_type, turn_number, book_on, book_off, '
          'rostered_minutes, remarks, driver_number, payroll_number, '
          'driver_name, depot, amendment_code, mileage, page_number, raw_text',
        )
        .gte('duty_date', databaseStart)
        .lte('duty_date', databaseEnd);

    duties.addAll(
      parsedDutyResponse
          .whereType<Map<String, dynamic>>()
          .where(
            (row) => matchesProfile(
              row: row,
              payrollNumber: payrollNumber,
              rosterNumber: rosterNumber,
            ),
          )
          .map(_dutyFromRow),
    );

    if (driverNumber != null) {
      final List<dynamic> annualLeaveResponse = await _supabase
          .from(_annualLeavePeriodTableName)
          .select(
            'period_type, start_date, end_date, '
            'annual_leave_allocations!inner('
            'driver_number, surname, depot, source, is_confirmed, page_number'
            ')',
          )
          .lte('start_date', databaseEnd)
          .gte('end_date', databaseStart)
          .eq('annual_leave_allocations.driver_number', driverNumber)
          .eq('annual_leave_allocations.is_confirmed', true);

      for (final Map<String, dynamic> row
          in annualLeaveResponse.whereType<Map<String, dynamic>>()) {
        final String? periodStartValue = _nullableString(row['start_date']);
        final String? periodEndValue = _nullableString(row['end_date']);

        if (periodStartValue == null || periodEndValue == null) {
          continue;
        }

        final DateTime periodStart = DateTime.parse(periodStartValue);
        final DateTime periodEnd = DateTime.parse(periodEndValue);

        DateTime current = periodStart.isAfter(start) ? periodStart : start;
        final DateTime finalDate = periodEnd.isBefore(end) ? periodEnd : end;

        while (!current.isAfter(finalDate)) {
          final Duty? duty = _annualLeaveDutyFromRow(row: row, date: current);

          if (duty != null) {
            duties.add(duty);
          }

          current = current.add(const Duration(days: 1));
        }
      }
    }

    final List<dynamic> grantedFloatingLeaveResponse = await _supabase
        .from(_annualLeaveRequestTableName)
        .select(
          'id, leave_date, status, request_type, notes, requested_at, '
          'decision_at',
        )
        .eq('user_id', user.id)
        .eq('request_type', 'floating')
        .eq('status', 'granted')
        .gte('leave_date', databaseStart)
        .lte('leave_date', databaseEnd);

    duties.addAll(
      grantedFloatingLeaveResponse.whereType<Map<String, dynamic>>().map(
        _floatingAnnualLeaveDutyFromRow,
      ),
    );

    final List<dynamic> blockOverrideResponse = await _supabase
        .from(_annualLeaveBlockOverrideTableName)
        .select(
          'id, leave_year, period_type, '
          'original_start_date, original_end_date, '
          'override_start_date, override_end_date, '
          'change_type, swap_driver_number, swap_reference, notes',
        )
        .eq('user_id', user.id)
        .gte('leave_year', start.year)
        .lte('leave_year', end.year);

    final List<AnnualLeaveBlockOverride> blockOverrides = blockOverrideResponse
        .whereType<Map<String, dynamic>>()
        .map(AnnualLeaveBlockOverride.fromMap)
        .toList(growable: false);

    final Set<String> officialBlockPeriodKeys =
        await _getOfficialBlockPeriodKeys(
          driverNumber: driverNumber,
          startYear: start.year,
          endYear: end.year,
        );

    final List<AnnualLeaveBlockOverride> effectiveBlockOverrides =
        _effectiveBlockOverrides(
          overrides: blockOverrides,
          officialPeriodKeys: officialBlockPeriodKeys,
        );

    if (effectiveBlockOverrides.isNotEmpty) {
      _applyBlockOverridesForRange(
        duties: duties,
        start: start,
        end: end,
        overrides: effectiveBlockOverrides,
      );
    }

    final SundayAvailabilityService sundayAvailabilityService =
        SundayAvailabilityService(supabase: _supabase);

    final Set<String> explicitlyAvailableSundayDates =
        await sundayAvailabilityService.getAvailableSundayDatesForRange(
          start,
          end,
        );

    if (permanentlyUnavailableSundays) {
      final Set<String> sundayDates = _sundayDatesForRange(start, end);

      _applyPermanentSundayUnavailability(
        duties: duties,
        sundayDates: sundayDates,
        explicitlyAvailableSundayDates: explicitlyAvailableSundayDates,
      );
    } else {
      final Set<String> postBlockSundayDates = await _getPostBlockSundayDates(
        startDate: start,
        endDate: end,
        driverNumber: driverNumber,
        overrides: effectiveBlockOverrides,
      );

      if (postBlockSundayDates.isNotEmpty) {
        _applyPostBlockSundayUnavailability(
          duties: duties,
          postBlockSundayDates: postBlockSundayDates,
          explicitlyAvailableSundayDates: explicitlyAvailableSundayDates,
        );
      }
    }

    final List<dynamic> manualDutyResponse = await _supabase
        .from(_manualDutyTableName)
        .select(
          'duty_date, duty_type, turn_number, book_on, book_off, '
          'rostered_minutes, remarks, manual_change_type, updated_at',
        )
        .eq('user_id', user.id)
        .gte('duty_date', databaseStart)
        .lte('duty_date', databaseEnd);

    duties.addAll(
      _latestManualDutiesByDate(manualDutyResponse).map(_manualDutyFromRow),
    );

    return resolveByDate(duties);
  }

  /// Returns Sundays that immediately follow an effective block-leave week
  /// ending on Saturday.
  ///
  /// The official Annual Leave Roster remains the baseline. If that block has
  /// a user-specific move or mutual swap, the override dates replace the
  /// original dates for this rule as well.
  Future<Set<String>> _getOfficialBlockPeriodKeys({
    required String? driverNumber,
    required int startYear,
    required int endYear,
  }) async {
    if (driverNumber == null || driverNumber.trim().isEmpty) {
      return const <String>{};
    }

    final DateTime firstDate = DateTime(startYear, 1, 1);
    final DateTime lastDate = DateTime(endYear, 12, 31);

    final List<dynamic> response = await _supabase
        .from(_annualLeavePeriodTableName)
        .select(
          'period_type, start_date, end_date, '
          'annual_leave_allocations!inner('
          'driver_number, is_confirmed'
          ')',
        )
        .lte('start_date', _databaseDate(lastDate))
        .gte('end_date', _databaseDate(firstDate))
        .eq('annual_leave_allocations.driver_number', driverNumber)
        .eq('annual_leave_allocations.is_confirmed', true);

    final Set<String> result = <String>{};

    for (final Map<String, dynamic> row
        in response.whereType<Map<String, dynamic>>()) {
      final DateTime? start = DateTime.tryParse(
        (row['start_date'] ?? '').toString(),
      );

      final AnnualLeaveBlockPeriodType? type = _blockPeriodTypeFromDatabase(
        row['period_type'],
      );

      if (start == null || type == null) {
        continue;
      }

      result.add('${start.year}:${type.name}');
    }

    return Set<String>.unmodifiable(result);
  }

  static List<AnnualLeaveBlockOverride> _effectiveBlockOverrides({
    required List<AnnualLeaveBlockOverride> overrides,
    required Set<String> officialPeriodKeys,
  }) {
    return overrides
        .where((AnnualLeaveBlockOverride override) {
          if (override.changeType != AnnualLeaveBlockChangeType.manual) {
            return true;
          }

          final String key =
              '${override.leaveYear}:${override.periodType.name}';

          return !officialPeriodKeys.contains(key);
        })
        .toList(growable: false);
  }

  /// Exposes block-override filtering for focused unit tests.
  static List<AnnualLeaveBlockOverride> effectiveBlockOverridesForTest({
    required List<AnnualLeaveBlockOverride> overrides,
    required Set<String> officialPeriodKeys,
  }) {
    return _effectiveBlockOverrides(
      overrides: overrides,
      officialPeriodKeys: officialPeriodKeys,
    );
  }

  /// Exposes block-leave duty creation for focused unit tests.
  static Duty blockOverrideDutyForTest({
    required AnnualLeaveBlockOverride override,
    required DateTime date,
  }) {
    return _blockOverrideDuty(override: override, date: date);
  }

  Future<Set<String>> _getPostBlockSundayDates({
    required DateTime startDate,
    required DateTime endDate,
    required String? driverNumber,
    required List<AnnualLeaveBlockOverride> overrides,
  }) async {
    if (driverNumber == null || driverNumber.trim().isEmpty) {
      return const <String>{};
    }

    final DateTime rangeStart = _dateOnly(startDate);
    final DateTime rangeEnd = _dateOnly(endDate);

    if (rangeEnd.isBefore(rangeStart)) {
      return const <String>{};
    }

    final DateTime possibleBlockEndStart = rangeStart.subtract(
      const Duration(days: 1),
    );
    final DateTime possibleBlockEndEnd = rangeEnd.subtract(
      const Duration(days: 1),
    );

    final List<dynamic> response = await _supabase
        .from(_annualLeavePeriodTableName)
        .select(
          'period_type, start_date, end_date, '
          'annual_leave_allocations!inner('
          'driver_number, is_confirmed'
          ')',
        )
        .gte('end_date', _databaseDate(possibleBlockEndStart))
        .lte('end_date', _databaseDate(possibleBlockEndEnd))
        .eq('annual_leave_allocations.driver_number', driverNumber)
        .eq('annual_leave_allocations.is_confirmed', true);

    final Set<String> result = <String>{};

    for (final Map<String, dynamic> row
        in response.whereType<Map<String, dynamic>>()) {
      final DateTime? officialEnd = DateTime.tryParse(
        (row['end_date'] ?? '').toString(),
      );

      final AnnualLeaveBlockPeriodType? periodType =
          _blockPeriodTypeFromDatabase(row['period_type']);

      if (officialEnd == null || periodType == null) {
        continue;
      }

      final AnnualLeaveBlockOverride? matchingOverride = _matchingBlockOverride(
        overrides: overrides,
        leaveYear: officialEnd.year,
        periodType: periodType,
      );

      // Once a block has been moved or swapped, its original dates no longer
      // create the post-block Sunday rule for this driver.
      if (matchingOverride != null) {
        continue;
      }

      _addPostBlockSundayIfApplicable(
        result: result,
        blockEndDate: officialEnd,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
    }

    // Overrides must also be checked independently because a moved block may
    // now end on a Saturday even when the original block end was elsewhere.
    for (final AnnualLeaveBlockOverride override in overrides) {
      _addPostBlockSundayIfApplicable(
        result: result,
        blockEndDate: override.overrideEndDate,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
    }

    return Set<String>.unmodifiable(result);
  }

  static AnnualLeaveBlockOverride? _matchingBlockOverride({
    required List<AnnualLeaveBlockOverride> overrides,
    required int leaveYear,
    required AnnualLeaveBlockPeriodType periodType,
  }) {
    for (final AnnualLeaveBlockOverride override in overrides) {
      if (override.leaveYear == leaveYear &&
          override.periodType == periodType) {
        return override;
      }
    }

    return null;
  }

  static AnnualLeaveBlockPeriodType? _blockPeriodTypeFromDatabase(
    Object? value,
  ) {
    switch (_nullableString(value)) {
      case 'spring':
        return AnnualLeaveBlockPeriodType.spring;
      case 'summer_first_week':
        return AnnualLeaveBlockPeriodType.summerFirstWeek;
      case 'summer_second_week':
        return AnnualLeaveBlockPeriodType.summerSecondWeek;
      case 'winter':
        return AnnualLeaveBlockPeriodType.winter;
      default:
        return null;
    }
  }

  static void _addPostBlockSundayIfApplicable({
    required Set<String> result,
    required DateTime blockEndDate,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final DateTime blockEnd = _dateOnly(blockEndDate);

    if (blockEnd.weekday != DateTime.saturday) {
      return;
    }

    final DateTime sunday = blockEnd.add(const Duration(days: 1));

    if (sunday.isBefore(rangeStart) || sunday.isAfter(rangeEnd)) {
      return;
    }

    result.add(_databaseDate(sunday));
  }

  static Set<String> _sundayDatesForRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    final DateTime start = _dateOnly(startDate);
    final DateTime end = _dateOnly(endDate);

    final Set<String> result = <String>{};

    DateTime current = start;

    while (!current.isAfter(end)) {
      if (current.weekday == DateTime.sunday) {
        result.add(_databaseDate(current));
      }

      current = current.add(const Duration(days: 1));
    }

    return Set<String>.unmodifiable(result);
  }

  static void _applyPermanentSundayUnavailability({
    required List<Duty> duties,
    required Set<String> sundayDates,
    required Set<String> explicitlyAvailableSundayDates,
  }) {
    for (final String sundayDateValue in sundayDates) {
      if (explicitlyAvailableSundayDates.contains(sundayDateValue)) {
        continue;
      }

      final DateTime? sunday = DateTime.tryParse(sundayDateValue);

      if (sunday == null || sunday.weekday != DateTime.sunday) {
        continue;
      }

      final bool hasBookedSundayDuty = duties.any(
        (Duty duty) =>
            _databaseDate(duty.date) == sundayDateValue &&
            duty.dutyType.countsAsWorking,
      );

      if (!hasBookedSundayDuty) {
        continue;
      }

      final bool alreadyUnavailable = duties.any(
        (Duty duty) =>
            _databaseDate(duty.date) == sundayDateValue &&
            duty.dutyType == DutyType.unavailable &&
            duty.rawText == 'permanent_sunday_unavailable',
      );

      if (alreadyUnavailable) {
        continue;
      }

      duties.add(
        Duty(
          date: _dateOnly(sunday),
          source: RosterSource.annualLeave,
          dutyType: DutyType.unavailable,
          remarks: 'Unavailable – permanently unavailable Sunday',
          rawText: 'permanent_sunday_unavailable',
        ),
      );
    }
  }

  static void _applyPostBlockSundayUnavailability({
    required List<Duty> duties,
    required Set<String> postBlockSundayDates,
    required Set<String> explicitlyAvailableSundayDates,
  }) {
    for (final String sundayDateValue in postBlockSundayDates) {
      if (explicitlyAvailableSundayDates.contains(sundayDateValue)) {
        continue;
      }

      final DateTime? sunday = DateTime.tryParse(sundayDateValue);

      if (sunday == null || sunday.weekday != DateTime.sunday) {
        continue;
      }

      final bool hasBookedSundayDuty = duties.any(
        (Duty duty) =>
            _databaseDate(duty.date) == sundayDateValue &&
            duty.dutyType.countsAsWorking,
      );

      if (!hasBookedSundayDuty) {
        continue;
      }

      final bool alreadyUnavailable = duties.any(
        (Duty duty) =>
            _databaseDate(duty.date) == sundayDateValue &&
            duty.dutyType == DutyType.unavailable &&
            duty.rawText == 'post_block_sunday',
      );

      if (alreadyUnavailable) {
        continue;
      }

      duties.add(
        Duty(
          date: _dateOnly(sunday),
          source: RosterSource.annualLeave,
          dutyType: DutyType.unavailable,
          remarks: 'Unavailable – Sunday following block annual leave',
          rawText: 'post_block_sunday',
        ),
      );
    }
  }

  /// Resolves a collection containing multiple dates into one winning duty
  /// per date using the normal Roster Buddy source hierarchy.
  Map<String, Duty> resolveByDate(Iterable<Duty> duties) {
    final Map<String, List<Duty>> dutiesByDate = <String, List<Duty>>{};

    for (final Duty duty in duties) {
      final String key = _databaseDate(duty.date);

      dutiesByDate.putIfAbsent(key, () => <Duty>[]).add(duty);
    }

    final Map<String, Duty> resolved = <String, Duty>{};

    for (final MapEntry<String, List<Duty>> entry in dutiesByDate.entries) {
      final Duty? duty = resolve(entry.value);

      if (duty != null) {
        resolved[entry.key] = duty;
      }
    }

    return Map<String, Duty>.unmodifiable(resolved);
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

  static void _applyBlockOverridesForDate({
    required List<Duty> duties,
    required DateTime date,
    required List<AnnualLeaveBlockOverride> overrides,
  }) {
    for (final AnnualLeaveBlockOverride override in overrides) {
      final bool dateInOriginal =
          override.originalStartDate != null &&
          override.originalEndDate != null &&
          !_dateOnly(date).isBefore(_dateOnly(override.originalStartDate!)) &&
          !_dateOnly(date).isAfter(_dateOnly(override.originalEndDate!));

      final bool dateInOverride =
          !_dateOnly(date).isBefore(_dateOnly(override.overrideStartDate)) &&
          !_dateOnly(date).isAfter(_dateOnly(override.overrideEndDate));

      if (dateInOriginal) {
        duties.removeWhere(
          (Duty duty) =>
              duty.source == RosterSource.annualLeave &&
              duty.dutyType == DutyType.annualLeave &&
              _periodMatchesOverride(duty.remarks, override.periodType),
        );
      }

      if (dateInOverride) {
        duties.add(_blockOverrideDuty(override: override, date: date));
      }
    }
  }

  static void _applyBlockOverridesForRange({
    required List<Duty> duties,
    required DateTime start,
    required DateTime end,
    required List<AnnualLeaveBlockOverride> overrides,
  }) {
    for (final AnnualLeaveBlockOverride override in overrides) {
      if (override.originalStartDate != null &&
          override.originalEndDate != null) {
        duties.removeWhere((Duty duty) {
          if (duty.source != RosterSource.annualLeave ||
              duty.dutyType != DutyType.annualLeave ||
              !_periodMatchesOverride(duty.remarks, override.periodType)) {
            return false;
          }

          final DateTime dutyDate = _dateOnly(duty.date);

          return !dutyDate.isBefore(_dateOnly(override.originalStartDate!)) &&
              !dutyDate.isAfter(_dateOnly(override.originalEndDate!));
        });
      }

      DateTime current = _dateOnly(override.overrideStartDate);
      final DateTime finalDate = _dateOnly(override.overrideEndDate);

      if (current.isBefore(_dateOnly(start))) {
        current = _dateOnly(start);
      }

      final DateTime cappedEnd = finalDate.isAfter(_dateOnly(end))
          ? _dateOnly(end)
          : finalDate;

      while (!current.isAfter(cappedEnd)) {
        duties.add(_blockOverrideDuty(override: override, date: current));

        current = current.add(const Duration(days: 1));
      }
    }
  }

  static Duty _blockOverrideDuty({
    required AnnualLeaveBlockOverride override,
    required DateTime date,
  }) {
    String changeLabel;

    switch (override.changeType) {
      case AnnualLeaveBlockChangeType.manual:
        changeLabel = 'Manual block leave';
      case AnnualLeaveBlockChangeType.agreedMove:
        changeLabel = 'Moved block annual leave';
      case AnnualLeaveBlockChangeType.mutualSwap:
        changeLabel = 'Mutual swap block annual leave';
    }

    return Duty(
      date: _dateOnly(date),
      source: RosterSource.annualLeave,
      dutyType: DutyType.annualLeave,
      remarks: '${_periodLabelForOverride(override.periodType)} – $changeLabel',
      rawText: override.notes,
    );
  }

  static bool _periodMatchesOverride(
    String? remarks,
    AnnualLeaveBlockPeriodType type,
  ) {
    final String value = (remarks ?? '').toLowerCase();

    switch (type) {
      case AnnualLeaveBlockPeriodType.spring:
        return value.contains('spring');

      case AnnualLeaveBlockPeriodType.summerFirstWeek:
        return value.contains('summer') && value.contains('first');

      case AnnualLeaveBlockPeriodType.summerSecondWeek:
        return value.contains('summer') && value.contains('second');

      case AnnualLeaveBlockPeriodType.winter:
        return value.contains('winter');
    }
  }

  static String _periodLabelForOverride(AnnualLeaveBlockPeriodType type) {
    switch (type) {
      case AnnualLeaveBlockPeriodType.spring:
        return 'Spring block annual leave';

      case AnnualLeaveBlockPeriodType.summerFirstWeek:
        return 'Summer block annual leave – first week';

      case AnnualLeaveBlockPeriodType.summerSecondWeek:
        return 'Summer block annual leave – second week';

      case AnnualLeaveBlockPeriodType.winter:
        return 'Winter block annual leave';
    }
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static bool matchesProfile({
    required Map<String, dynamic> row,
    required String? payrollNumber,
    required String? rosterNumber,
  }) {
    final RosterSource source = _rosterSource(row['source']);

    if (source == RosterSource.baseRoster) {
      final String? rowRosterNumber = _normaliseIdentifier(
        row['driver_number'],
      );

      return rosterNumber != null &&
          rowRosterNumber != null &&
          rosterNumber == rowRosterNumber;
    }

    final String? rowPayrollNumber = _normaliseIdentifier(
      row['payroll_number'],
    );

    return payrollNumber != null &&
        rowPayrollNumber != null &&
        payrollNumber == rowPayrollNumber;
  }

  static Duty _floatingAnnualLeaveDutyFromRow(Map<String, dynamic> row) {
    final String? dateValue = _nullableString(row['leave_date']);

    if (dateValue == null) {
      throw const DutyResolverException(
        'A granted annual leave request is missing its leave date.',
      );
    }

    final String? notes = _nullableString(row['notes']);

    return Duty(
      date: DateTime.parse(dateValue),
      source: RosterSource.annualLeave,
      dutyType: DutyType.annualLeave,
      remarks: notes == null
          ? 'Floating annual leave'
          : 'Floating annual leave – $notes',
      rawText: _nullableString(row['id']),
    );
  }

  static Map<String, dynamic>? _latestManualDutyForDate(
    Iterable<dynamic> rows,
  ) {
    Map<String, dynamic>? latest;

    for (final dynamic value in rows) {
      if (value is! Map<String, dynamic>) {
        continue;
      }

      if (latest == null || _isLaterManualDuty(value, latest)) {
        latest = value;
      }
    }

    return latest;
  }

  static List<Map<String, dynamic>> _latestManualDutiesByDate(
    Iterable<dynamic> rows,
  ) {
    final Map<String, Map<String, dynamic>> latestByDate =
        <String, Map<String, dynamic>>{};

    for (final dynamic value in rows) {
      if (value is! Map<String, dynamic>) {
        continue;
      }

      final String? dutyDate = _nullableString(value['duty_date']);

      if (dutyDate == null) {
        continue;
      }

      final Map<String, dynamic>? existing = latestByDate[dutyDate];

      if (existing == null || _isLaterManualDuty(value, existing)) {
        latestByDate[dutyDate] = value;
      }
    }

    final List<Map<String, dynamic>> result = latestByDate.values.toList();

    result.sort((first, second) {
      final String firstDate = _nullableString(first['duty_date']) ?? '';
      final String secondDate = _nullableString(second['duty_date']) ?? '';
      return firstDate.compareTo(secondDate);
    });

    return result;
  }

  static bool _isLaterManualDuty(
    Map<String, dynamic> candidate,
    Map<String, dynamic> existing,
  ) {
    final DateTime? candidateUpdatedAt = DateTime.tryParse(
      _nullableString(candidate['updated_at']) ?? '',
    );
    final DateTime? existingUpdatedAt = DateTime.tryParse(
      _nullableString(existing['updated_at']) ?? '',
    );

    if (candidateUpdatedAt != null && existingUpdatedAt != null) {
      final int comparison = candidateUpdatedAt.compareTo(existingUpdatedAt);

      if (comparison != 0) {
        return comparison > 0;
      }
    } else if (candidateUpdatedAt != null) {
      return true;
    } else if (existingUpdatedAt != null) {
      return false;
    }

    // Deterministic fallback for older rows without updated_at.
    return _manualChangePriority(candidate['manual_change_type']) >
        _manualChangePriority(existing['manual_change_type']);
  }

  static int _manualChangePriority(Object? value) {
    switch (_nullableString(value)) {
      case 'manual_change':
        return 4;
      case 'edited_times':
        return 3;
      case 'selected_turn':
        return 2;
      case 'rest_day_worked':
        return 1;
      default:
        return 0;
    }
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
