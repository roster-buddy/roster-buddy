import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/annual_leave_request.dart';

void main() {
  Map<String, dynamic> row({bool? pending, String status = 'granted'}) => {
    'id': 'request', 'user_id': 'owner', 'leave_date': '2026-11-25',
    'status': status, 'request_type': 'floating',
    'requested_at': '2026-10-29T08:00:00Z',
    'cancellation_pending': ?pending,
  };
  test('pending cancellation stays granted until confirmed', () {
    final request = AnnualLeaveRequest.fromMap(row(pending: true));
    expect(request.cancellationPending, isTrue);
    expect(request.status, AnnualLeaveRequestStatus.granted);
    expect(request.requestType, AnnualLeaveRequestType.floating);
  });
  test('older request payloads have no pending cancellation', () {
    expect(AnnualLeaveRequest.fromMap(row()).cancellationPending, isFalse);
  });
  test('confirmed cancellation clears pending state', () {
    final request = AnnualLeaveRequest.fromMap(row(pending: false, status: 'cancelled'));
    expect(request.status, AnnualLeaveRequestStatus.cancelled);
    expect(request.cancellationPending, isFalse);
  });
}
