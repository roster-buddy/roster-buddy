enum AnnualLeaveRequestStatus { requested, abeyance, granted, cancelled }

enum AnnualLeaveRequestType { floating, block }

class AnnualLeaveRequest {
  const AnnualLeaveRequest({
    required this.id,
    required this.userId,
    required this.leaveDate,
    required this.status,
    required this.requestType,
    required this.requestedAt,
    this.decisionAt,
    this.notes,
    this.queuePosition,
  });

  final String id;
  final String userId;
  final DateTime leaveDate;
  final AnnualLeaveRequestStatus status;
  final AnnualLeaveRequestType requestType;
  final DateTime requestedAt;
  final DateTime? decisionAt;
  final String? notes;

  /// Position in the annual-leave abeyance queue.
  ///
  /// For example, 3 means the driver is third in the queue for that date.
  final int? queuePosition;

  factory AnnualLeaveRequest.fromMap(Map<String, dynamic> row) {
    return AnnualLeaveRequest(
      id: row['id'].toString(),
      userId: row['user_id'].toString(),
      leaveDate: DateTime.parse(row['leave_date'].toString()),
      status: _statusFromDatabase(row['status']),
      requestType: _typeFromDatabase(row['request_type']),
      requestedAt: DateTime.parse(row['requested_at'].toString()),
      decisionAt: row['decision_at'] == null
          ? null
          : DateTime.parse(row['decision_at'].toString()),
      notes: _nullableString(row['notes']),
      queuePosition: _nullableInt(row['queue_position']),
    );
  }

  static AnnualLeaveRequestStatus _statusFromDatabase(Object? value) {
    switch (value?.toString()) {
      case 'requested':
        return AnnualLeaveRequestStatus.requested;
      case 'abeyance':
        return AnnualLeaveRequestStatus.abeyance;
      case 'granted':
        return AnnualLeaveRequestStatus.granted;
      case 'cancelled':
        return AnnualLeaveRequestStatus.cancelled;
      default:
        throw FormatException(
          'Unknown annual leave request status: ${value ?? 'null'}',
        );
    }
  }

  static AnnualLeaveRequestType _typeFromDatabase(Object? value) {
    switch (value?.toString()) {
      case 'floating':
        return AnnualLeaveRequestType.floating;
      case 'block':
        return AnnualLeaveRequestType.block;
      default:
        throw FormatException(
          'Unknown annual leave request type: ${value ?? 'null'}',
        );
    }
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

  static String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final String cleaned = value.toString().trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
