import '../models/parse_result.dart';
import '../parser/parser_utils.dart';

class DocumentDateIndex {
  const DocumentDateIndex._();

  static List<DateTime> fromText(Iterable<String> pages) {
    final dates = <String, DateTime>{};
    for (final page in pages) {
      for (final date in ParserUtils.extractDates(page)) {
        dates[date.toIso8601String().substring(0, 10)] = date;
      }
    }
    return dates.values.toList()..sort();
  }

  static List<String> forResult(ParseResult? result) {
    if (result == null) return [];
    final dates = <String>{};
    void add(DateTime date) => dates.add(date.toIso8601String().substring(0, 10));
    void addRange(DateTime start, DateTime end) {
      if (end.isBefore(start) || end.difference(start).inDays > 3660) return;
      var day = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      while (!day.isAfter(last)) {
        add(day);
        day = DateTime(day.year, day.month, day.day + 1);
      }
    }
    result.identifiedDates.forEach(add);
    for (final duty in result.duties) { add(duty.date); }
    for (final card in result.jobCards) { addRange(card.validFrom, card.validTo); }
    for (final allocation in result.annualLeaveAllocations) {
      for (final period in allocation.periods) { addRange(period.startDate, period.endDate); }
    }
    return dates.toList()..sort();
  }
}
