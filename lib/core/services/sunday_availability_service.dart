import 'package:supabase_flutter/supabase_flutter.dart';

class SundayAvailabilityService {
  SundayAvailabilityService({SupabaseClient? supabase})
    : _supabaseOverride = supabase;

  final SupabaseClient? _supabaseOverride;

  SupabaseClient get _supabase => _supabaseOverride ?? Supabase.instance.client;

  static const String _profileTable = 'driver_profiles';
  static const String _overrideTable = 'sunday_availability_overrides';

  /// Whether the signed-in driver is normally unavailable for every Sunday.
  ///
  /// A date-specific availability override can still make an individual
  /// Sunday available without changing this permanent preference.
  Future<bool> isPermanentlyUnavailableOnSundays() async {
    final User user = _requireUser();

    final Map<String, dynamic>? profile = await _supabase
        .from(_profileTable)
        .select('permanently_unavailable_sundays')
        .eq('user_id', user.id)
        .maybeSingle();

    return profile?['permanently_unavailable_sundays'] == true;
  }

  /// Changes the driver's normal Sunday availability.
  Future<void> setPermanentlyUnavailableOnSundays(bool unavailable) async {
    final User user = _requireUser();

    await _supabase
        .from(_profileTable)
        .update(<String, dynamic>{
          'permanently_unavailable_sundays': unavailable,
        })
        .eq('user_id', user.id);
  }

  /// Returns true when the driver has explicitly made this individual Sunday
  /// available.
  Future<bool> isSundayExplicitlyAvailable(DateTime date) async {
    _requireSunday(date);

    final User user = _requireUser();

    final Map<String, dynamic>? row = await _supabase
        .from(_overrideTable)
        .select('is_available')
        .eq('user_id', user.id)
        .eq('sunday_date', _databaseDate(date))
        .maybeSingle();

    return row?['is_available'] == true;
  }

  /// Makes a particular Sunday available.
  ///
  /// This is used both for:
  /// - a normally available driver returning after a block leave week; and
  /// - a permanently Sunday-unavailable driver volunteering for one Sunday.
  Future<void> makeSundayAvailable(DateTime date) async {
    _requireSunday(date);

    final User user = _requireUser();

    await _supabase.from(_overrideTable).upsert(<String, dynamic>{
      'user_id': user.id,
      'sunday_date': _databaseDate(date),
      'is_available': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,sunday_date');
  }

  /// Removes a date-specific availability override.
  ///
  /// The Sunday then returns to whatever state the normal Roster Buddy rules
  /// produce.
  Future<void> removeSundayAvailabilityOverride(DateTime date) async {
    _requireSunday(date);

    final User user = _requireUser();

    await _supabase
        .from(_overrideTable)
        .delete()
        .eq('user_id', user.id)
        .eq('sunday_date', _databaseDate(date));
  }

  /// Loads all explicitly available Sundays in a date range.
  Future<Set<String>> getAvailableSundayDatesForRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final User user = _requireUser();

    final DateTime start = _dateOnly(startDate);
    final DateTime end = _dateOnly(endDate);

    if (end.isBefore(start)) {
      throw const SundayAvailabilityException(
        'The Sunday availability end date cannot be before the start date.',
      );
    }

    final List<dynamic> response = await _supabase
        .from(_overrideTable)
        .select('sunday_date')
        .eq('user_id', user.id)
        .eq('is_available', true)
        .gte('sunday_date', _databaseDate(start))
        .lte('sunday_date', _databaseDate(end));

    return response
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> row) => row['sunday_date']?.toString())
        .whereType<String>()
        .where((String value) => value.trim().isNotEmpty)
        .toSet();
  }

  User _requireUser() {
    final User? user = _supabase.auth.currentUser;

    if (user == null) {
      throw const SundayAvailabilityException(
        'You must be signed in before changing Sunday availability.',
      );
    }

    return user;
  }

  static void _requireSunday(DateTime date) {
    if (date.weekday != DateTime.sunday) {
      throw const SundayAvailabilityException(
        'Sunday availability can only be changed for a Sunday.',
      );
    }
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _databaseDate(DateTime value) {
    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}

class SundayAvailabilityException implements Exception {
  const SundayAvailabilityException(this.message);

  final String message;

  @override
  String toString() => message;
}
