import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/duty.dart';
import '../models/duty_type.dart';

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

  Future<void> saveMovedRestDay({
    required DateTime date,
    required Duty originalDuty,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const ManualDutyException(
        'You must be signed in before moving a Rest Day.',
      );
    }

    final bool canMoveRestDayHere =
        originalDuty.dutyType == DutyType.working ||
        originalDuty.dutyType == DutyType.training ||
        originalDuty.dutyType == DutyType.medical;

    if (!canMoveRestDayHere) {
      throw const ManualDutyException(
        'A Rest Day can only be moved onto a working duty.',
      );
    }

    await _supabase.from(_tableName).upsert(<String, dynamic>{
      'user_id': user.id,
      'duty_date': _databaseDate(date),
      'duty_type': 'rest_day',
      'manual_change_type': 'moved_rest_day',
      'turn_number': null,
      'book_on': null,
      'book_off': null,
      'rostered_minutes': null,
      'remarks': 'Moved Rest Day',
      'original_source': _sourceName(originalDuty),
      'original_duty_type': _dutyTypeName(originalDuty),
      'original_turn_number': _clean(originalDuty.turnNumber),
      'original_book_on': _clean(originalDuty.bookOn),
      'original_book_off': _clean(originalDuty.bookOff),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,duty_date,manual_change_type');
  }

  Future<void> saveManualChange({
    required DateTime date,
    required DutyType dutyType,
    required String turnNumber,
    required String bookOn,
    required String bookOff,
    required String remarks,
    required Duty originalDuty,
  }) async {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const ManualDutyException(
        'You must be signed in before making a manual change.',
      );
    }

    final bool workingType = dutyType.countsAsWorking;

    String? storedBookOn;
    String? storedBookOff;
    int? rosteredMinutes;

    if (workingType) {
      if (bookOn.trim().isEmpty || bookOff.trim().isEmpty) {
        throw const ManualDutyException(
          'Enter book-on and book-off times for a working duty.',
        );
      }

      storedBookOn = bookOn;
      storedBookOff = bookOff;
      rosteredMinutes = _minutesBetween(bookOn: bookOn, bookOff: bookOff);
    }

    String dutyTypeValue;

    switch (dutyType) {
      case DutyType.working:
        dutyTypeValue = 'working';
      case DutyType.training:
        dutyTypeValue = 'training';
      case DutyType.medical:
        dutyTypeValue = 'medical';
      case DutyType.restDay:
        dutyTypeValue = 'rest_day';
      case DutyType.sick:
        dutyTypeValue = 'sick';
      case DutyType.publicHoliday:
        dutyTypeValue = 'public_holiday';
      case DutyType.unavailable:
        dutyTypeValue = 'unavailable';
      case DutyType.annualLeave:
        dutyTypeValue = 'annual_leave';
      case DutyType.unknown:
        throw const ManualDutyException('Select a valid duty type.');
    }

    await _supabase.from(_tableName).upsert(<String, dynamic>{
      'user_id': user.id,
      'duty_date': _databaseDate(date),
      'duty_type': dutyTypeValue,
      'manual_change_type': 'manual_change',
      'turn_number': workingType ? _clean(turnNumber) : null,
      'book_on': storedBookOn,
      'book_off': storedBookOff,
      'rostered_minutes': rosteredMinutes,
      'remarks': remarks.trim().isEmpty ? 'Manual duty change' : remarks.trim(),
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
