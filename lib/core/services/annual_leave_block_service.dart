import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/annual_leave_block_cycle.dart';
import '../models/annual_leave_block_override.dart';

class AnnualLeaveBlockService {
  AnnualLeaveBlockService({SupabaseClient? supabase})
    : _supabaseOverride = supabase;

  final SupabaseClient? _supabaseOverride;

  SupabaseClient get _supabase => _supabaseOverride ?? Supabase.instance.client;

  static const String _cycleTable = 'annual_leave_block_cycles';
  static const String _overrideTable = 'annual_leave_block_overrides';

  Future<AnnualLeaveBlockCycle?> getCycleForYear(int leaveYear) async {
    final User user = _requireUser();

    final Map<String, dynamic>? row = await _supabase
        .from(_cycleTable)
        .select('leave_year, week_index, source')
        .eq('user_id', user.id)
        .eq('leave_year', leaveYear)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return AnnualLeaveBlockCycle.fromMap(row);
  }

  Future<AnnualLeaveBlockCycle> saveCycleForYear({
    required int leaveYear,
    required int weekIndex,
    String source = 'manual',
  }) async {
    final User user = _requireUser();

    if (weekIndex < 1 || weekIndex > 13) {
      throw const AnnualLeaveBlockException(
        'Block week must be between 1 and 13.',
      );
    }

    await _supabase.from(_cycleTable).upsert(<String, dynamic>{
      'user_id': user.id,
      'leave_year': leaveYear,
      'week_index': weekIndex,
      'source': source,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,leave_year');

    final AnnualLeaveBlockCycle? saved = await getCycleForYear(leaveYear);

    if (saved == null) {
      throw const AnnualLeaveBlockException(
        'Roster Buddy could not save the block leave cycle.',
      );
    }

    return saved;
  }

  Future<AnnualLeaveBlockCycle> ensureNextYearCycle({
    required int currentLeaveYear,
  }) async {
    final AnnualLeaveBlockCycle? current = await getCycleForYear(
      currentLeaveYear,
    );

    if (current == null) {
      throw const AnnualLeaveBlockException(
        'Set the current block week before calculating next year.',
      );
    }

    final int nextYear = currentLeaveYear + 1;

    final AnnualLeaveBlockCycle? existing = await getCycleForYear(nextYear);

    if (existing != null) {
      return existing;
    }

    return saveCycleForYear(
      leaveYear: nextYear,
      weekIndex: current.nextYearWeekIndex,
      source: 'calculated',
    );
  }

  Future<List<AnnualLeaveBlockOverride>> getOverridesForYear(
    int leaveYear,
  ) async {
    final User user = _requireUser();

    final List<dynamic> response = await _supabase
        .from(_overrideTable)
        .select(
          'id, leave_year, period_type, '
          'original_start_date, original_end_date, '
          'override_start_date, override_end_date, '
          'change_type, swap_driver_number, swap_reference, notes',
        )
        .eq('user_id', user.id)
        .eq('leave_year', leaveYear)
        .order('override_start_date');

    return response
        .whereType<Map<String, dynamic>>()
        .map(AnnualLeaveBlockOverride.fromMap)
        .toList(growable: false);
  }

  Future<void> saveOverride({
    required int leaveYear,
    required AnnualLeaveBlockPeriodType periodType,
    required DateTime overrideStartDate,
    required DateTime overrideEndDate,
    required AnnualLeaveBlockChangeType changeType,
    DateTime? originalStartDate,
    DateTime? originalEndDate,
    String? swapDriverNumber,
    String? swapReference,
    String? notes,
  }) async {
    final User user = _requireUser();

    if (overrideEndDate.isBefore(overrideStartDate)) {
      throw const AnnualLeaveBlockException(
        'The block leave end date cannot be before the start date.',
      );
    }

    if (changeType == AnnualLeaveBlockChangeType.mutualSwap &&
        (swapDriverNumber == null || swapDriverNumber.trim().isEmpty)) {
      throw const AnnualLeaveBlockException(
        'Enter the other driver number for a mutual swap.',
      );
    }

    await _supabase.from(_overrideTable).upsert(<String, dynamic>{
      'user_id': user.id,
      'leave_year': leaveYear,
      'period_type': _periodTypeValue(periodType),
      'original_start_date': _databaseDateNullable(originalStartDate),
      'original_end_date': _databaseDateNullable(originalEndDate),
      'override_start_date': _databaseDate(overrideStartDate),
      'override_end_date': _databaseDate(overrideEndDate),
      'change_type': _changeTypeValue(changeType),
      'swap_driver_number': _nullableText(swapDriverNumber),
      'swap_reference': _nullableText(swapReference),
      'notes': _nullableText(notes),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,leave_year,period_type');
  }

  Future<void> removeOverride({
    required int leaveYear,
    required AnnualLeaveBlockPeriodType periodType,
  }) async {
    final User user = _requireUser();

    await _supabase
        .from(_overrideTable)
        .delete()
        .eq('user_id', user.id)
        .eq('leave_year', leaveYear)
        .eq('period_type', _periodTypeValue(periodType));
  }

  User _requireUser() {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveBlockException(
        'You must be signed in before changing block annual leave.',
      );
    }

    return user;
  }

  static String _periodTypeValue(AnnualLeaveBlockPeriodType value) {
    switch (value) {
      case AnnualLeaveBlockPeriodType.spring:
        return 'spring';
      case AnnualLeaveBlockPeriodType.summerFirstWeek:
        return 'summer_first_week';
      case AnnualLeaveBlockPeriodType.summerSecondWeek:
        return 'summer_second_week';
      case AnnualLeaveBlockPeriodType.winter:
        return 'winter';
    }
  }

  static String _changeTypeValue(AnnualLeaveBlockChangeType value) {
    switch (value) {
      case AnnualLeaveBlockChangeType.manual:
        return 'manual';
      case AnnualLeaveBlockChangeType.agreedMove:
        return 'agreed_move';
      case AnnualLeaveBlockChangeType.mutualSwap:
        return 'mutual_swap';
    }
  }

  static String _databaseDate(DateTime value) {
    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  static String? _databaseDateNullable(DateTime? value) {
    return value == null ? null : _databaseDate(value);
  }

  static String? _nullableText(String? value) {
    final String cleaned = value?.trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }
}

class AnnualLeaveBlockException implements Exception {
  const AnnualLeaveBlockException(this.message);

  final String message;

  @override
  String toString() => message;
}
