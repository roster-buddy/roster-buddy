import 'annual_leave_block_override.dart';

enum AnnualLeaveBlockPendingStatus {
  awaitingUnion,
  scheduled,
  readyToSend,
  sent,
  confirmed,
  cancelled,
  failed,
}

class AnnualLeaveBlockPendingAction {
  const AnnualLeaveBlockPendingAction({
    required this.id,
    required this.userId,
    required this.leaveYear,
    required this.periodType,
    required this.changeType,
    required this.originalStartDate,
    required this.originalEndDate,
    required this.proposedStartDate,
    required this.proposedEndDate,
    required this.status,
    required this.createdAt,
    this.swapDriverNumber,
    this.swapReference,
    this.notes,
    this.recipientEmail,
    this.emailSubject,
    this.emailBody,
    this.scheduledFor,
    this.sentAt,
    this.errorMessage,
    this.confirmedAt,
    this.cancelledAt,
  });

  final String id;
  final String userId;
  final int leaveYear;
  final AnnualLeaveBlockPeriodType periodType;
  final AnnualLeaveBlockChangeType changeType;
  final DateTime originalStartDate;
  final DateTime originalEndDate;
  final DateTime proposedStartDate;
  final DateTime proposedEndDate;

  final String? swapDriverNumber;
  final String? swapReference;
  final String? notes;

  final String? recipientEmail;
  final String? emailSubject;
  final String? emailBody;
  final DateTime? scheduledFor;
  final DateTime? sentAt;
  final String? errorMessage;

  final AnnualLeaveBlockPendingStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;

  factory AnnualLeaveBlockPendingAction.fromMap(Map<String, dynamic> row) {
    return AnnualLeaveBlockPendingAction(
      id: row['id'].toString(),
      userId: row['user_id'].toString(),
      leaveYear: _requiredInt(row['leave_year']),
      periodType: _periodType(row['period_type']),
      changeType: _changeType(row['change_type']),
      originalStartDate: DateTime.parse(row['original_start_date'].toString()),
      originalEndDate: DateTime.parse(row['original_end_date'].toString()),
      proposedStartDate: DateTime.parse(row['proposed_start_date'].toString()),
      proposedEndDate: DateTime.parse(row['proposed_end_date'].toString()),
      swapDriverNumber: _nullableString(row['swap_driver_number']),
      swapReference: _nullableString(row['swap_reference']),
      notes: _nullableString(row['notes']),
      recipientEmail: _nullableString(row['recipient_email']),
      emailSubject: _nullableString(row['email_subject']),
      emailBody: _nullableString(row['email_body']),
      scheduledFor: _nullableDateTime(row['scheduled_for']),
      sentAt: _nullableDateTime(row['sent_at']),
      errorMessage: _nullableString(row['error_message']),
      status: _status(row['status']),
      createdAt: DateTime.parse(row['created_at'].toString()),
      confirmedAt: _nullableDateTime(row['confirmed_at']),
      cancelledAt: _nullableDateTime(row['cancelled_at']),
    );
  }

  static AnnualLeaveBlockPeriodType _periodType(Object? value) {
    switch (value?.toString()) {
      case 'spring':
        return AnnualLeaveBlockPeriodType.spring;
      case 'summer_first_week':
        return AnnualLeaveBlockPeriodType.summerFirstWeek;
      case 'summer_second_week':
        return AnnualLeaveBlockPeriodType.summerSecondWeek;
      case 'winter':
        return AnnualLeaveBlockPeriodType.winter;
      default:
        throw FormatException(
          'Unknown block annual leave period type: ${value ?? 'null'}',
        );
    }
  }

  static AnnualLeaveBlockChangeType _changeType(Object? value) {
    switch (value?.toString()) {
      case 'agreed_move':
        return AnnualLeaveBlockChangeType.agreedMove;
      case 'mutual_swap':
        return AnnualLeaveBlockChangeType.mutualSwap;
      default:
        throw FormatException(
          'Unknown block annual leave change type: ${value ?? 'null'}',
        );
    }
  }

  static AnnualLeaveBlockPendingStatus _status(Object? value) {
    switch (value?.toString()) {
      case 'awaiting_union':
        return AnnualLeaveBlockPendingStatus.awaitingUnion;
      case 'scheduled':
        return AnnualLeaveBlockPendingStatus.scheduled;
      case 'ready_to_send':
        return AnnualLeaveBlockPendingStatus.readyToSend;
      case 'sent':
        return AnnualLeaveBlockPendingStatus.sent;
      case 'confirmed':
        return AnnualLeaveBlockPendingStatus.confirmed;
      case 'cancelled':
        return AnnualLeaveBlockPendingStatus.cancelled;
      case 'failed':
        return AnnualLeaveBlockPendingStatus.failed;
      default:
        throw FormatException(
          'Unknown block pending action status: ${value ?? 'null'}',
        );
    }
  }

  static int _requiredInt(Object? value) {
    if (value is int) {
      return value;
    }

    final int? parsed = int.tryParse(value?.toString() ?? '');

    if (parsed == null) {
      throw FormatException('Invalid integer value: ${value ?? 'null'}');
    }

    return parsed;
  }

  static String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final String cleaned = value.toString().trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static DateTime? _nullableDateTime(Object? value) {
    if (value == null) {
      return null;
    }

    final String cleaned = value.toString().trim();

    return cleaned.isEmpty ? null : DateTime.parse(cleaned);
  }
}
