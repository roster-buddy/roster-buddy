import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/annual_leave_request.dart';

class AnnualLeaveService {
  AnnualLeaveService({SupabaseClient? supabase}) : _supabaseOverride = supabase;

  final SupabaseClient? _supabaseOverride;

  SupabaseClient get _supabase => _supabaseOverride ?? Supabase.instance.client;

  static const String _requestTable = 'annual_leave_requests';
  static const String _balanceTable = 'annual_leave_balances';

  Future<AnnualLeaveRequest> requestFloatingLeave({
    required DateTime date,
    String? notes,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveException(
        'You must be signed in before requesting annual leave.',
      );
    }

    final DateTime leaveDate = DateTime(date.year, date.month, date.day);

    // WMT annual leave is not required for Sundays.
    if (leaveDate.weekday == DateTime.sunday) {
      throw const AnnualLeaveException(
        'Annual leave cannot be requested for a Sunday.',
      );
    }

    final String dateValue = _databaseDate(leaveDate);

    final Map<String, dynamic>? existing = await _supabase
        .from(_requestTable)
        .select(
          'id, user_id, leave_date, status, request_type, '
          'requested_at, decision_at, notes',
        )
        .eq('user_id', user.id)
        .eq('leave_date', dateValue)
        .eq('request_type', 'floating')
        .maybeSingle();

    if (existing != null) {
      final AnnualLeaveRequest existingRequest = AnnualLeaveRequest.fromMap(
        existing,
      );

      if (existingRequest.status != AnnualLeaveRequestStatus.cancelled &&
          existingRequest.status != AnnualLeaveRequestStatus.refused) {
        throw const AnnualLeaveException(
          'You already have an annual leave request for this date.',
        );
      }
    }

    await _ensureBalanceRow(user.id, leaveDate.year);

    final int remainingDays = await getRemainingFloatingDays(leaveDate.year);

    if (remainingDays <= 0) {
      throw const AnnualLeaveException(
        'You do not have any floating annual leave days remaining.',
      );
    }

    if (existing != null) {
      await _supabase
          .from(_requestTable)
          .update(<String, dynamic>{
            'status': 'requested',
            'requested_at': DateTime.now().toUtc().toIso8601String(),
            'decision_at': null,
            'notes': _nullableText(notes),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', existing['id']);

      final Map<String, dynamic> refreshed = await _supabase
          .from(_requestTable)
          .select(
            'id, user_id, leave_date, status, request_type, '
            'requested_at, decision_at, notes',
          )
          .eq('id', existing['id'])
          .single();

      return AnnualLeaveRequest.fromMap(refreshed);
    }

    final Map<String, dynamic> inserted = await _supabase
        .from(_requestTable)
        .insert(<String, dynamic>{
          'user_id': user.id,
          'leave_date': dateValue,
          'status': 'requested',
          'request_type': 'floating',
          'notes': _nullableText(notes),
        })
        .select(
          'id, user_id, leave_date, status, request_type, '
          'requested_at, decision_at, notes',
        )
        .single();

    return AnnualLeaveRequest.fromMap(inserted);
  }

  Future<int> getRemainingFloatingDays(int leaveYear) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveException(
        'You must be signed in before loading annual leave.',
      );
    }

    await _ensureBalanceRow(user.id, leaveYear);

    final Map<String, dynamic> balance = await _supabase
        .from(_balanceTable)
        .select('entitlement_days, carry_over_days, starting_balance_days')
        .eq('user_id', user.id)
        .eq('leave_year', leaveYear)
        .single();

    final int entitlement =
        _asInt(balance['starting_balance_days']) ??
        _asInt(balance['entitlement_days']) ??
        14;

    final int carryOver = _asInt(balance['carry_over_days']) ?? 0;

    final String start = '$leaveYear-01-01';
    final String end = '$leaveYear-12-31';

    final List<dynamic> requests = await _supabase
        .from(_requestTable)
        .select('status')
        .eq('user_id', user.id)
        .eq('request_type', 'floating')
        .gte('leave_date', start)
        .lte('leave_date', end)
        .inFilter('status', <String>['requested', 'abeyance', 'granted']);

    final int committedDays = requests.length;

    final int remaining = entitlement + carryOver - committedDays;

    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _ensureBalanceRow(String userId, int leaveYear) async {
    final Map<String, dynamic>? existing = await _supabase
        .from(_balanceTable)
        .select('id')
        .eq('user_id', userId)
        .eq('leave_year', leaveYear)
        .maybeSingle();

    if (existing != null) {
      return;
    }

    await _supabase.from(_balanceTable).insert(<String, dynamic>{
      'user_id': userId,
      'leave_year': leaveYear,
      'entitlement_days': 14,
      'carry_over_days': 0,
      'starting_balance_days': 14,
    });
  }

  static String _databaseDate(DateTime value) {
    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  static String? _nullableText(String? value) {
    final String cleaned = value?.trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }
}

class AnnualLeaveException implements Exception {
  const AnnualLeaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
