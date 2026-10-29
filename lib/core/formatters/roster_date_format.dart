import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

String displayDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

String displayStoredDate(Object? value) {
  final text = value?.toString() ?? '';
  final parsed = DateTime.tryParse(text);
  return parsed == null ? text : displayDate(parsed);
}

String displayDatesInText(String text) => text.replaceAllMapped(
  RegExp(r'\b[0-9]{4}-[0-9]{2}-[0-9]{2}\b'),
  (match) => displayStoredDate(match.group(0)),
);

class RosterDateLocalizations extends DefaultMaterialLocalizations {
  const RosterDateLocalizations();
  @override
  String formatFullDate(DateTime date) => displayDate(date);
  @override
  String formatMediumDate(DateTime date) => displayDate(date);
  @override
  String formatShortDate(DateTime date) => displayDate(date);
  @override
  String formatCompactDate(DateTime date) => displayDate(date);
  @override
  String formatShortMonthDay(DateTime date) => displayDate(date);
  @override
  String get dateHelpText => 'dd/mm/yyyy';
  @override
  DateTime? parseCompactDate(String? input) {
    final parts = (input ?? '').trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null || parts[2].length != 4) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day ? date : null;
  }
}

class RosterDateLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const RosterDateLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';
  @override
  Future<MaterialLocalizations> load(Locale locale) => SynchronousFuture<MaterialLocalizations>(const RosterDateLocalizations());
  @override
  bool shouldReload(RosterDateLocalizationsDelegate old) => false;
}
