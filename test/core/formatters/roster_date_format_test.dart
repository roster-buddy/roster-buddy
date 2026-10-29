import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/formatters/roster_date_format.dart';

void main() {
  test('full dates are padded day/month/year', () {
    expect(displayDate(DateTime(2027, 1, 5)), '05/01/2027');
    expect(displayStoredDate('2026-12-14'), '14/12/2026');
    expect(displayDatesInText('2026-12-14 → 2026-12-16'), '14/12/2026 → 16/12/2026');
  });
  test('date entry follows UK order and rejects impossible dates', () {
    const localizations = RosterDateLocalizations();
    expect(localizations.parseCompactDate('05/01/2027'), DateTime(2027, 1, 5));
    expect(localizations.parseCompactDate('31/02/2027'), isNull);
    expect(localizations.parseCompactDate('29/02/2028'), DateTime(2028, 2, 29));
    expect(localizations.formatFullDate(DateTime(2027, 1, 5)), '05/01/2027');
  });
}
