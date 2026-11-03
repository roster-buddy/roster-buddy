import '../models/duty_code.dart';

class RosterNotificationText {
  const RosterNotificationText._();

  static String label(String? code, String type) {
    if (type == 'annual_leave') return 'Annual leave';
    if (type == 'medical') return 'Medical';
    if (type == 'rest_day') return 'Rest day';
    if (type == 'sick') return 'Sick';
    if (type == 'public_holiday') return 'Bank holiday';
    final definition = DutyCodeLibrary.find(code);
    if (definition?.code == 'TS') return 'Safety brief';
    return definition?.preferredMeaning ?? switch (type) {
      'training' => 'Training',
      'unavailable' => 'Unavailable',
      'unknown' => 'Duty',
      _ => 'Shift',
    };
  }

  static String title(String date, String? code, String type, String kind) {
    final day = DateTime.parse(date);
    final shortDate = '${day.day}/${day.month}/${(day.year % 100).toString().padLeft(2, '0')}';
    if (kind == 'leave_conflict') return 'Annual leave conflict on $shortDate';
    return '${label(code, type)} ${kind == 'changed' ? 'updated' : 'allocated'} on $shortDate';
  }

  static String detail(String source, String start, String finish, String turn) {
    final clock = RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$');
    return [
      source,
      if (clock.hasMatch(start) && clock.hasMatch(finish))
        '${start.replaceAll(':', '')}–${finish.replaceAll(':', '')}',
      if (turn.trim().isNotEmpty) 'T${turn.trim()}',
    ].join(' ');
  }
}
