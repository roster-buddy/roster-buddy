import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/duty.dart';

enum ShiftSwapStatus { pending, approved, cancelled }

class ShiftSwap {
  const ShiftSwap({
    required this.id,
    required this.userId,
    required this.originalDate,
    required this.requestedDate,
    required this.status,
    this.originalTurnNumber,
    this.originalBookOn,
    this.originalBookOff,
    this.requestedTurnNumber,
    this.requestedBookOn,
    this.requestedBookOff,
    this.notes,
  });

  final String id;
  final String userId;
  final DateTime originalDate;
  final DateTime requestedDate;
  final ShiftSwapStatus status;

  final String? originalTurnNumber;
  final String? originalBookOn;
  final String? originalBookOff;

  final String? requestedTurnNumber;
  final String? requestedBookOn;
  final String? requestedBookOff;

  final String? notes;
}

class ShiftSwapService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<ShiftSwap> createRequest({
    required Duty originalDuty,
    required String requestedDate,
    required String requestedTurnNumber,
    String? otherDriverName,
    String? otherPayrollNumber,
    String type = 'Mutual swap',
    bool confirmedWithRosters = false,
    String? notes,
  }) async {
    final String? userId = _client.auth.currentUser?.id;

    if (userId == null) {
      throw StateError('You must be signed in to save a shift change.');
    }

    final List<String> metadata = <String>[
      'TYPE=$type',
      'CONFIRMED_WITH_ROSTERS=$confirmedWithRosters',
      if (otherDriverName != null && otherDriverName.trim().isNotEmpty)
        'OTHER_DRIVER=${otherDriverName.trim()}',
      if (otherPayrollNumber != null && otherPayrollNumber.trim().isNotEmpty)
        'OTHER_PAYROLL=${otherPayrollNumber.trim()}',
      if (notes != null && notes.trim().isNotEmpty) 'NOTES=${notes.trim()}',
    ];

    final Map<String, dynamic> row = await _client
        .from('shift_swaps')
        .insert({
          'user_id': userId,
          'original_date': _dateKey(originalDuty.date),
          'requested_date': _normaliseRequestedDate(requestedDate),
          'original_turn_number': originalDuty.turnNumber,
          'original_book_on': originalDuty.bookOn,
          'original_book_off': originalDuty.bookOff,
          'requested_turn_number': requestedTurnNumber.trim().isEmpty
              ? null
              : requestedTurnNumber.trim(),
          'requested_book_on': null,
          'requested_book_off': null,
          'status': confirmedWithRosters ? 'approved' : 'pending',
          'notes': metadata.join('\n'),
        })
        .select()
        .single();

    return _fromRow(row);
  }

  Future<List<ShiftSwap>> getRequests() async {
    final String? userId = _client.auth.currentUser?.id;

    if (userId == null) {
      return const <ShiftSwap>[];
    }

    final List<dynamic> rows = await _client
        .from('shift_swaps')
        .select()
        .eq('user_id', userId)
        .order('original_date');

    return rows
        .map((dynamic row) => _fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  ShiftSwap _fromRow(Map<String, dynamic> row) {
    return ShiftSwap(
      id: row['id'].toString(),
      userId: row['user_id'].toString(),
      originalDate: DateTime.parse(row['original_date'].toString()),
      requestedDate: DateTime.parse(row['requested_date'].toString()),
      status: _statusFromString(row['status'].toString()),
      originalTurnNumber: row['original_turn_number'] as String?,
      originalBookOn: row['original_book_on'] as String?,
      originalBookOff: row['original_book_off'] as String?,
      requestedTurnNumber: row['requested_turn_number'] as String?,
      requestedBookOn: row['requested_book_on'] as String?,
      requestedBookOff: row['requested_book_off'] as String?,
      notes: row['notes'] as String?,
    );
  }

  ShiftSwapStatus _statusFromString(String value) {
    switch (value) {
      case 'approved':
        return ShiftSwapStatus.approved;
      case 'cancelled':
        return ShiftSwapStatus.cancelled;
      default:
        return ShiftSwapStatus.pending;
    }
  }

  String _normaliseRequestedDate(String value) {
    final String trimmed = value.trim();

    final RegExp ukDate = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
    final RegExpMatch? match = ukDate.firstMatch(trimmed);

    if (match != null) {
      final int day = int.parse(match.group(1)!);
      final int month = int.parse(match.group(2)!);
      final int year = int.parse(match.group(3)!);

      final DateTime parsed = DateTime(year, month, day);

      if (parsed.year != year || parsed.month != month || parsed.day != day) {
        throw StateError('Enter a valid proposed duty date.');
      }

      return _dateKey(parsed);
    }

    final DateTime? parsed = DateTime.tryParse(trimmed);

    if (parsed == null) {
      throw StateError('Enter the proposed duty date as DD/MM/YYYY.');
    }

    return _dateKey(parsed);
  }

  String _dateKey(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');

    return '${value.year}-$month-$day';
  }
}
