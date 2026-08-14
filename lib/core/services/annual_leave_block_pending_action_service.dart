import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/annual_leave_block_override.dart';
import '../models/annual_leave_block_pending_action.dart';

class AnnualLeaveBlockPendingActionException implements Exception {
  const AnnualLeaveBlockPendingActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AnnualLeaveBlockPendingActionService {
  AnnualLeaveBlockPendingActionService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  static const String _table = 'annual_leave_block_pending_actions';

  final SupabaseClient _supabase;

  Future<AnnualLeaveBlockPendingAction> savePendingAction({
    required int leaveYear,
    required AnnualLeaveBlockPeriodType periodType,
    required AnnualLeaveBlockChangeType changeType,
    required DateTime originalStartDate,
    required DateTime originalEndDate,
    required DateTime proposedStartDate,
    required DateTime proposedEndDate,
    String? swapDriverNumber,
    String? swapReference,
    String? notes,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'You must be signed in before saving a block leave action.',
      );
    }

    if (changeType == AnnualLeaveBlockChangeType.manual) {
      throw const AnnualLeaveBlockPendingActionException(
        'Manual block allocations do not require Union confirmation.',
      );
    }

    final DateTime originalStart = _dateOnly(originalStartDate);
    final DateTime originalEnd = _dateOnly(originalEndDate);
    final DateTime proposedStart = _dateOnly(proposedStartDate);
    final DateTime proposedEnd = _dateOnly(proposedEndDate);

    if (originalEnd.isBefore(originalStart) ||
        proposedEnd.isBefore(proposedStart)) {
      throw const AnnualLeaveBlockPendingActionException(
        'The block leave end date cannot be before the start date.',
      );
    }

    final String? cleanedSwapDriver = _nullableText(swapDriverNumber);

    if (changeType == AnnualLeaveBlockChangeType.mutualSwap &&
        cleanedSwapDriver == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'Enter the other driver number for a mutual swap.',
      );
    }

    final Map<String, dynamic> values = <String, dynamic>{
      'user_id': user.id,
      'leave_year': leaveYear,
      'period_type': _periodTypeDatabaseValue(periodType),
      'change_type': _changeTypeDatabaseValue(changeType),
      'original_start_date': _databaseDate(originalStart),
      'original_end_date': _databaseDate(originalEnd),
      'proposed_start_date': _databaseDate(proposedStart),
      'proposed_end_date': _databaseDate(proposedEnd),
      'swap_driver_number': cleanedSwapDriver,
      'swap_reference': _nullableText(swapReference),
      'notes': _nullableText(notes),
      'status': 'awaiting_union',
      'confirmed_at': null,
      'cancelled_at': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final Map<String, dynamic>? existing = await _supabase
        .from(_table)
        .select('id')
        .eq('user_id', user.id)
        .eq('leave_year', leaveYear)
        .eq('period_type', _periodTypeDatabaseValue(periodType))
        .eq('status', 'awaiting_union')
        .maybeSingle();

    final Map<String, dynamic> saved;

    if (existing == null) {
      saved = await _supabase.from(_table).insert(values).select().single();
    } else {
      saved = await _supabase
          .from(_table)
          .update(values)
          .eq('id', existing['id'])
          .eq('user_id', user.id)
          .select()
          .single();
    }

    return AnnualLeaveBlockPendingAction.fromMap(saved);
  }

  Future<AnnualLeaveBlockPendingAction> scheduleFutureRequest({
    required int leaveYear,
    required AnnualLeaveBlockPeriodType periodType,
    required AnnualLeaveBlockChangeType changeType,
    required DateTime originalStartDate,
    required DateTime originalEndDate,
    required DateTime proposedStartDate,
    required DateTime proposedEndDate,
    required String recipientEmail,
    required String emailSubject,
    required String emailBody,
    required DateTime scheduledFor,
    String? swapDriverNumber,
    String? swapReference,
    String? notes,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'You must be signed in before scheduling a block leave request.',
      );
    }

    if (changeType == AnnualLeaveBlockChangeType.manual) {
      throw const AnnualLeaveBlockPendingActionException(
        'Manual block allocations cannot be scheduled as requests.',
      );
    }

    final String cleanRecipient = recipientEmail.trim();
    final String cleanSubject = emailSubject.trim();
    final String cleanBody = emailBody.trim();

    if (cleanRecipient.isEmpty || cleanSubject.isEmpty || cleanBody.isEmpty) {
      throw const AnnualLeaveBlockPendingActionException(
        'The scheduled Union email is incomplete.',
      );
    }

    final String? cleanedSwapDriver = _nullableText(swapDriverNumber);

    if (changeType == AnnualLeaveBlockChangeType.mutualSwap &&
        cleanedSwapDriver == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'Enter the other driver number for a mutual swap.',
      );
    }

    final Map<String, dynamic> values = <String, dynamic>{
      'user_id': user.id,
      'leave_year': leaveYear,
      'period_type': _periodTypeDatabaseValue(periodType),
      'change_type': _changeTypeDatabaseValue(changeType),
      'original_start_date': _databaseDate(_dateOnly(originalStartDate)),
      'original_end_date': _databaseDate(_dateOnly(originalEndDate)),
      'proposed_start_date': _databaseDate(_dateOnly(proposedStartDate)),
      'proposed_end_date': _databaseDate(_dateOnly(proposedEndDate)),
      'swap_driver_number': cleanedSwapDriver,
      'swap_reference': _nullableText(swapReference),
      'notes': _nullableText(notes),
      'status': 'scheduled',
      'recipient_email': cleanRecipient,
      'email_subject': cleanSubject,
      'email_body': cleanBody,
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'sent_at': null,
      'error_message': null,
      'confirmed_at': null,
      'cancelled_at': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final Map<String, dynamic>? existing = await _supabase
        .from(_table)
        .select('id')
        .eq('user_id', user.id)
        .eq('leave_year', leaveYear)
        .eq('period_type', _periodTypeDatabaseValue(periodType))
        .inFilter('status', <String>['awaiting_union', 'scheduled'])
        .maybeSingle();

    final Map<String, dynamic> saved;

    if (existing == null) {
      saved = await _supabase.from(_table).insert(values).select().single();
    } else {
      saved = await _supabase
          .from(_table)
          .update(values)
          .eq('id', existing['id'])
          .eq('user_id', user.id)
          .select()
          .single();
    }

    return AnnualLeaveBlockPendingAction.fromMap(saved);
  }

  Future<List<AnnualLeaveBlockPendingAction>> getScheduledActionsForYear(
    int leaveYear,
  ) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'You must be signed in before loading scheduled block leave requests.',
      );
    }

    final List<dynamic> response = await _supabase
        .from(_table)
        .select()
        .eq('user_id', user.id)
        .eq('leave_year', leaveYear)
        .eq('status', 'scheduled')
        .order('scheduled_for');

    return List<AnnualLeaveBlockPendingAction>.unmodifiable(
      response.whereType<Map<String, dynamic>>().map(
        AnnualLeaveBlockPendingAction.fromMap,
      ),
    );
  }

  Future<void> cancelScheduledAction({required String actionId}) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'You must be signed in before changing scheduled block leave requests.',
      );
    }

    final Map<String, dynamic>? existing = await _supabase
        .from(_table)
        .select('id')
        .eq('id', actionId)
        .eq('user_id', user.id)
        .eq('status', 'scheduled')
        .maybeSingle();

    if (existing == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'This scheduled block leave request could not be found.',
      );
    }

    await _supabase
        .from(_table)
        .update(<String, dynamic>{
          'status': 'cancelled',
          'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', actionId)
        .eq('user_id', user.id)
        .eq('status', 'scheduled');
  }

  Future<List<AnnualLeaveBlockPendingAction>> getPendingActions() async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'You must be signed in before loading Pending Actions.',
      );
    }

    final List<dynamic> response = await _supabase
        .from(_table)
        .select()
        .eq('user_id', user.id)
        .inFilter('status', <String>['awaiting_union', 'scheduled'])
        .order('proposed_start_date');

    return List<AnnualLeaveBlockPendingAction>.unmodifiable(
      response.whereType<Map<String, dynamic>>().map(
        AnnualLeaveBlockPendingAction.fromMap,
      ),
    );
  }

  Future<void> cancelPendingAction({required String actionId}) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'You must be signed in before changing Pending Actions.',
      );
    }

    final Map<String, dynamic>? existing = await _supabase
        .from(_table)
        .select('id')
        .eq('id', actionId)
        .eq('user_id', user.id)
        .eq('status', 'awaiting_union')
        .maybeSingle();

    if (existing == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'This pending block leave action could not be found.',
      );
    }

    await _supabase
        .from(_table)
        .update(<String, dynamic>{
          'status': 'cancelled',
          'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', actionId)
        .eq('user_id', user.id)
        .eq('status', 'awaiting_union');
  }

  Future<void> markConfirmed({required String actionId}) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'You must be signed in before changing Pending Actions.',
      );
    }

    final Map<String, dynamic>? existing = await _supabase
        .from(_table)
        .select('id')
        .eq('id', actionId)
        .eq('user_id', user.id)
        .eq('status', 'awaiting_union')
        .maybeSingle();

    if (existing == null) {
      throw const AnnualLeaveBlockPendingActionException(
        'This pending block leave action could not be found.',
      );
    }

    await _supabase
        .from(_table)
        .update(<String, dynamic>{
          'status': 'confirmed',
          'confirmed_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', actionId)
        .eq('user_id', user.id)
        .eq('status', 'awaiting_union');
  }

  static String _periodTypeDatabaseValue(AnnualLeaveBlockPeriodType value) {
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

  static String _changeTypeDatabaseValue(AnnualLeaveBlockChangeType value) {
    switch (value) {
      case AnnualLeaveBlockChangeType.manual:
        return 'manual';
      case AnnualLeaveBlockChangeType.agreedMove:
        return 'agreed_move';
      case AnnualLeaveBlockChangeType.mutualSwap:
        return 'mutual_swap';
    }
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _databaseDate(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');

    return '${value.year}-$month-$day';
  }

  static String? _nullableText(String? value) {
    if (value == null) {
      return null;
    }

    final String cleaned = value.trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
