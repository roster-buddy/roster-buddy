import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/duty.dart';

class ManualDutyService {
  ManualDutyService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _tableName = 'manual_duties';

  Future<void> saveRestDayWorked({
    required DateTime date,
    required String turnNumber,
    required String bookOn,
    required String bookOff,
    required Duty originalDuty,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const ManualDutyException(
        'You must be signed in before allocating a shift.',
      );
    }

    final int rosteredMinutes = _minutesBetween(
      bookOn: bookOn,
      bookOff: bookOff,
    );

    await _supabase.from(_tableName).upsert(<String, dynamic>{
      'user_id': user.id,
      'duty_date': _databaseDate(date),
      'duty_type': 'working',
      'manual_change_type': 'rest_day_worked',
      'turn_number': turnNumber.trim(),
      'book_on': bookOn,
      'book_off': bookOff,
      'rostered_minutes': rosteredMinutes,
      'remarks': 'Rest Day Worked (RDW)',
      'original_source': _sourceName(originalDuty),
      'original_duty_type': _dutyTypeName(originalDuty),
      'original_turn_number': _clean(originalDuty.turnNumber),
      'original_book_on': _clean(originalDuty.bookOn),
      'original_book_off': _clean(originalDuty.bookOff),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,duty_date,manual_change_type');
  }

  Future<void> saveSelectedTurn({
    required DateTime date,
    required String turnNumber,
    required String bookOn,
    required String bookOff,
    required Duty originalDuty,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const ManualDutyException(
        'You must be signed in before selecting a turn.',
      );
    }

    if (turnNumber.trim().isEmpty) {
      throw const ManualDutyException('Select a valid turn number.');
    }

    if (bookOn.trim().isEmpty || bookOff.trim().isEmpty) {
      throw const ManualDutyException(
        'The selected Job Card does not contain valid book-on/off times.',
      );
    }

    final int rosteredMinutes = _minutesBetween(
      bookOn: bookOn,
      bookOff: bookOff,
    );

    await _supabase.from(_tableName).upsert(<String, dynamic>{
      'user_id': user.id,
      'duty_date': _databaseDate(date),
      'duty_type': 'working',
      'manual_change_type': 'selected_turn',
      'turn_number': turnNumber.trim(),
      'book_on': bookOn,
      'book_off': bookOff,
      'rostered_minutes': rosteredMinutes,
      'remarks': 'Turn selected from Job Card',
      'original_source': _sourceName(originalDuty),
      'original_duty_type': _dutyTypeName(originalDuty),
      'original_turn_number': _clean(originalDuty.turnNumber),
      'original_book_on': _clean(originalDuty.bookOn),
      'original_book_off': _clean(originalDuty.bookOff),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,duty_date,manual_change_type');
  }

  Future<void> saveEditedDuty({
    required DateTime date,
    required String turnNumber,
    required String bookOn,
    required String bookOff,
    required String remarks,
    required Duty originalDuty,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const ManualDutyException(
        'You must be signed in before editing a duty.',
      );
    }

    final int rosteredMinutes = _minutesBetween(
      bookOn: bookOn,
      bookOff: bookOff,
    );

    await _supabase.from(_tableName).upsert(<String, dynamic>{
      'user_id': user.id,
      'duty_date': _databaseDate(date),
      'duty_type': _dutyTypeName(originalDuty),
      'manual_change_type': 'edited_times',
      'turn_number': turnNumber.trim().isEmpty ? null : turnNumber.trim(),
      'book_on': bookOn,
      'book_off': bookOff,
      'rostered_minutes': rosteredMinutes,
      'remarks': remarks.trim().isEmpty
          ? 'Manual duty time edit'
          : remarks.trim(),
      'original_source': _sourceName(originalDuty),
      'original_duty_type': _dutyTypeName(originalDuty),
      'original_turn_number': _clean(originalDuty.turnNumber),
      'original_book_on': _clean(originalDuty.bookOn),
      'original_book_off': _clean(originalDuty.bookOff),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,duty_date,manual_change_type');
  }

  static int _minutesBetween({
    required String bookOn,
    required String bookOff,
  }) {
    final List<int> start = bookOn.split(':').map(int.parse).toList();
    final List<int> end = bookOff.split(':').map(int.parse).toList();

    final int startMinutes = (start[0] * 60) + start[1];
    int endMinutes = (end[0] * 60) + end[1];

    if (endMinutes <= startMinutes) {
      endMinutes += 24 * 60;
    }

    return endMinutes - startMinutes;
  }

  static String _sourceName(Duty duty) {
    switch (duty.source.name) {
      case 'baseRoster':
        return 'base_roster';
      case 'tenDay':
        return '10_day';
      case 'sevenDay':
        return '7_day';
      case 'fortyEightHour':
        return '48_hour';
      case 'annualLeave':
        return 'annual_leave';
      case 'manual':
        return 'manual';
      default:
        return duty.source.name;
    }
  }

  static String _dutyTypeName(Duty duty) {
    switch (duty.dutyType.name) {
      case 'restDay':
        return 'rest_day';
      case 'annualLeave':
        return 'annual_leave';
      case 'publicHoliday':
        return 'public_holiday';
      default:
        return duty.dutyType.name;
    }
  }

  static String _databaseDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  static String? _clean(String? value) {
    final String cleaned = value?.trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }
}

class ManualDutyException implements Exception {
  const ManualDutyException(this.message);

  final String message;

  @override
  String toString() => message;
}
