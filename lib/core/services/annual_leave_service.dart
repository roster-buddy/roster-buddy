import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/annual_leave_balance.dart';
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
          'requested_at, decision_at, notes, queue_position',
        )
        .eq('user_id', user.id)
        .eq('leave_date', dateValue)
        .eq('request_type', 'floating')
        .maybeSingle();

    if (existing != null) {
      final AnnualLeaveRequest existingRequest = AnnualLeaveRequest.fromMap(
        existing,
      );

      if (existingRequest.status != AnnualLeaveRequestStatus.cancelled) {
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
            'queue_position': null,
            'notes': _nullableText(notes),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', existing['id']);

      final Map<String, dynamic> refreshed = await _supabase
          .from(_requestTable)
          .select(
            'id, user_id, leave_date, status, request_type, '
            'requested_at, decision_at, notes, queue_position',
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
          'requested_at, decision_at, notes, queue_position',
        )
        .single();

    return AnnualLeaveRequest.fromMap(inserted);
  }

  /// Loads annual leave requests between [startDate] and [endDate],
  /// inclusive, keyed by YYYY-MM-DD.
  ///
  /// Cancelled requests are excluded because the underlying rostered duty
  /// becomes the active calendar state again.
  /// Places an existing annual leave request into abeyance.
  ///
  /// A queue position is required because abeyance represents the driver's
  /// actual position in the waiting list for that date.
  Future<AnnualLeaveRequest> markAbeyance({
    required String requestId,
    required int queuePosition,
  }) async {
    if (queuePosition < 1) {
      throw const AnnualLeaveException(
        'The abeyance queue position must be 1 or greater.',
      );
    }

    return _updateRequestStatus(
      requestId: requestId,
      status: 'abeyance',
      queuePosition: queuePosition,
    );
  }

  /// Marks an annual leave request as granted.
  ///
  /// The queue position is cleared because a granted request is no longer
  /// waiting in abeyance.
  Future<AnnualLeaveRequest> markGranted({required String requestId}) async {
    return _updateRequestStatus(
      requestId: requestId,
      status: 'granted',
      clearQueuePosition: true,
    );
  }

  /// Cancels an annual leave request.
  ///
  /// Cancelled requests no longer count against the floating-day balance and
  /// the underlying allocated rostered duty becomes active again.
  Future<AnnualLeaveRequest> cancelRequest({required String requestId}) async {
    return _updateRequestStatus(
      requestId: requestId,
      status: 'cancelled',
      clearQueuePosition: true,
    );
  }

  Future<AnnualLeaveRequest> _updateRequestStatus({
    required String requestId,
    required String status,
    int? queuePosition,
    bool clearQueuePosition = false,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveException(
        'You must be signed in before changing annual leave.',
      );
    }

    final Map<String, dynamic>? existing = await _supabase
        .from(_requestTable)
        .select(
          'id, user_id, leave_date, status, request_type, '
          'requested_at, decision_at, notes, queue_position',
        )
        .eq('id', requestId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (existing == null) {
      throw const AnnualLeaveException(
        'This annual leave request could not be found.',
      );
    }

    final AnnualLeaveRequest request = AnnualLeaveRequest.fromMap(existing);

    if (request.status == AnnualLeaveRequestStatus.cancelled) {
      throw const AnnualLeaveException(
        'This annual leave request has already been cancelled.',
      );
    }

    final Map<String, dynamic> changes = <String, dynamic>{
      'status': status,
      'decision_at': status == 'requested'
          ? null
          : DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (queuePosition != null) {
      changes['queue_position'] = queuePosition;
    } else if (clearQueuePosition) {
      changes['queue_position'] = null;
    }

    await _supabase
        .from(_requestTable)
        .update(changes)
        .eq('id', requestId)
        .eq('user_id', user.id);

    final Map<String, dynamic> refreshed = await _supabase
        .from(_requestTable)
        .select(
          'id, user_id, leave_date, status, request_type, '
          'requested_at, decision_at, notes, queue_position',
        )
        .eq('id', requestId)
        .eq('user_id', user.id)
        .single();

    return AnnualLeaveRequest.fromMap(refreshed);
  }

  Future<Map<String, AnnualLeaveRequest>> getRequestsForRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveException(
        'You must be signed in before loading annual leave.',
      );
    }

    final DateTime start = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final DateTime end = DateTime(endDate.year, endDate.month, endDate.day);

    if (end.isBefore(start)) {
      throw const AnnualLeaveException(
        'The annual leave range end date cannot be before the start date.',
      );
    }

    final List<dynamic> response = await _supabase
        .from(_requestTable)
        .select(
          'id, user_id, leave_date, status, request_type, '
          'requested_at, decision_at, notes, queue_position',
        )
        .eq('user_id', user.id)
        .gte('leave_date', _databaseDate(start))
        .lte('leave_date', _databaseDate(end))
        .neq('status', 'cancelled')
        .order('leave_date');

    final Map<String, AnnualLeaveRequest> requests =
        <String, AnnualLeaveRequest>{};

    for (final Map<String, dynamic> row
        in response.whereType<Map<String, dynamic>>()) {
      final AnnualLeaveRequest request = AnnualLeaveRequest.fromMap(row);

      requests[_databaseDate(request.leaveDate)] = request;
    }

    return Map<String, AnnualLeaveRequest>.unmodifiable(requests);
  }

  Future<AnnualLeaveBalance> getBalanceForYear(int leaveYear) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveException(
        'You must be signed in before loading annual leave.',
      );
    }

    await _ensureBalanceRow(user.id, leaveYear);

    final Map<String, dynamic> balance = await _supabase
        .from(_balanceTable)
        .select(
          'leave_year, entitlement_days, starting_balance_days, '
          'bonus_days, carry_over_days, lieu_days',
        )
        .eq('user_id', user.id)
        .eq('leave_year', leaveYear)
        .single();

    final int committedDays = await _getCommittedFloatingDays(
      userId: user.id,
      leaveYear: leaveYear,
    );

    return AnnualLeaveBalance.fromMap(balance, committedDays: committedDays);
  }

  Future<int> getRemainingFloatingDays(int leaveYear) async {
    final AnnualLeaveBalance balance = await getBalanceForYear(leaveYear);
    return balance.remainingDays;
  }

  /// Saves the user's allowance setup for one leave year.
  ///
  /// [startingBalanceDays] is particularly useful when Roster Buddy starts
  /// part way through a leave year. For a normal new leave year this should
  /// normally remain equal to [entitlementDays].
  Future<AnnualLeaveBalance> saveBalanceSetup({
    required int leaveYear,
    required int startingBalanceDays,
    int entitlementDays = 14,
    int bonusDays = 0,
    int carryOverDays = 0,
    int lieuDays = 0,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveException(
        'You must be signed in before changing annual leave.',
      );
    }

    if (leaveYear < 2000) {
      throw const AnnualLeaveException('Enter a valid leave year.');
    }

    if (entitlementDays < 0 ||
        startingBalanceDays < 0 ||
        bonusDays < 0 ||
        carryOverDays < 0 ||
        lieuDays < 0) {
      throw const AnnualLeaveException(
        'Annual leave day values cannot be negative.',
      );
    }

    await _supabase.from(_balanceTable).upsert(<String, dynamic>{
      'user_id': user.id,
      'leave_year': leaveYear,
      'entitlement_days': entitlementDays,
      'starting_balance_days': startingBalanceDays,
      'bonus_days': bonusDays,
      'carry_over_days': carryOverDays,
      'lieu_days': lieuDays,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,leave_year');

    return getBalanceForYear(leaveYear);
  }

  /// Creates the next leave year using the normal yearly entitlement.
  ///
  /// Bonus days, carry-over and lieu days deliberately do not automatically
  /// move into the new year. They can be entered in Annual Leave Settings
  /// once their actual values are known.
  Future<AnnualLeaveBalance> ensureNextLeaveYear({
    required int currentLeaveYear,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveException(
        'You must be signed in before setting up annual leave.',
      );
    }

    final int nextLeaveYear = currentLeaveYear + 1;

    final Map<String, dynamic>? existing = await _supabase
        .from(_balanceTable)
        .select('id')
        .eq('user_id', user.id)
        .eq('leave_year', nextLeaveYear)
        .maybeSingle();

    if (existing == null) {
      await _supabase.from(_balanceTable).insert(<String, dynamic>{
        'user_id': user.id,
        'leave_year': nextLeaveYear,
        'entitlement_days': 14,
        'starting_balance_days': 14,
        'bonus_days': 0,
        'carry_over_days': 0,
        'lieu_days': 0,
      });
    }

    return getBalanceForYear(nextLeaveYear);
  }

  Future<int> _getCommittedFloatingDays({
    required String userId,
    required int leaveYear,
  }) async {
    final String start = '$leaveYear-01-01';
    final String end = '$leaveYear-12-31';

    final List<dynamic> requests = await _supabase
        .from(_requestTable)
        .select('id')
        .eq('user_id', userId)
        .eq('request_type', 'floating')
        .gte('leave_date', start)
        .lte('leave_date', end)
        .inFilter('status', <String>['requested', 'abeyance', 'granted']);

    return requests.length;
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
      'starting_balance_days': 14,
      'bonus_days': 0,
      'carry_over_days': 0,
      'lieu_days': 0,
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
}

class AnnualLeaveException implements Exception {
  const AnnualLeaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
