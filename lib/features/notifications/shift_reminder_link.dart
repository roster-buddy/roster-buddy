DateTime? shiftReminderDate(Uri uri) {
  final value = uri.queryParameters['shift'] ?? '';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final date = DateTime.tryParse(value);
  if (date == null || date.toIso8601String().substring(0, 10) != value) return null;
  return date;
}

bool canEditShiftTimes(DateTime date, String start, String finish, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return true;
  // A reminder after midnight still belongs to the shift's starting date.
  return day == today.subtract(const Duration(days: 1)) &&
    start.isNotEmpty && finish.isNotEmpty &&
    finish.replaceAll(':', '').compareTo(start.replaceAll(':', '')) < 0;
}
