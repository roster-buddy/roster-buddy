import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/duty.dart';
import '../models/duty_type.dart';
import '../models/roster_source.dart';

class DutyHistoryService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Duty>> load(DateTime date, Future<List<Duty>> resolved) async {
    final current = await resolved;
    final user = _client.auth.currentUser;
    if (user == null) return current;
    final key = date.toIso8601String().substring(0, 10);
    final manual = await _client.from('manual_duties').select().eq('user_id', user.id).eq('duty_date', key).order('updated_at', ascending: false);
    final archived = await _client.from('manual_duty_history').select('snapshot').eq('user_id', user.id).eq('duty_date', key).order('archived_at', ascending: false);
    final result = <Duty>[...current];
    for (final row in [...manual, ...archived.map((row) => Map<String, dynamic>.from(row['snapshot'] as Map))]) {
      result.add(_duty(date, row));
      if (row['original_duty_type'] != null) {
        result.add(_duty(date, {
          'source': row['original_source'], 'duty_type': row['original_duty_type'], 'turn_number': row['original_turn_number'],
          'book_on': row['original_book_on'], 'book_off': row['original_book_off'],
          'remarks': 'Previous entry preserved with manual change',
        }));
      }
    }
    final seen = <String>{};
    return result.where((d) => seen.add('${d.source.name}|${d.dutyType.name}|${d.turnNumber}|${d.bookOn}|${d.bookOff}|${d.remarks}')).toList();
  }

  Duty _duty(DateTime date, Map<String, dynamic> row) {
    String? time(dynamic value) => value == null ? null : value.toString().substring(0, 5);
    const types = {
      'working': DutyType.working, 'training': DutyType.training, 'medical': DutyType.medical,
      'rest_day': DutyType.restDay, 'annual_leave': DutyType.annualLeave, 'sick': DutyType.sick,
      'public_holiday': DutyType.publicHoliday, 'unavailable': DutyType.unavailable,
    };
    final sources = {'base_roster': RosterSource.baseRoster, 'ten_day': RosterSource.tenDay, 'seven_day': RosterSource.sevenDay, 'forty_eight_hour': RosterSource.fortyEightHour};
    final source = sources[row['source']] ?? RosterSource.values.where((s) => s.name == row['source']).firstOrNull ?? RosterSource.manual;
    return Duty(date: date, source: source,
      dutyType: types[row['duty_type']] ?? DutyType.unknown,
      turnNumber: row['turn_number']?.toString(), bookOn: time(row['book_on']),
      bookOff: time(row['book_off']), rosteredMinutes: row['rostered_minutes'] as int?,
      remarks: row['remarks']?.toString());
  }

  Future<void> revert(Duty selected, Duty current) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in required');
    const types = {
      DutyType.restDay: 'rest_day', DutyType.annualLeave: 'annual_leave',
      DutyType.publicHoliday: 'public_holiday',
    };
    await _client.from('manual_duties').upsert({
      'user_id': user.id, 'duty_date': selected.date.toIso8601String().substring(0,10),
      'manual_change_type': 'manual_change',
      'duty_type': types[selected.dutyType] ?? selected.dutyType.name,
      'turn_number': selected.turnNumber, 'book_on': selected.bookOn, 'book_off': selected.bookOff,
      'rostered_minutes': selected.rosteredMinutes,
      'remarks': 'Reverted to ${selected.source.name} entry${selected.remarks == null ? '' : ': ${selected.remarks}'}',
      'original_source': current.source.name,
      'original_duty_type': types[current.dutyType] ?? current.dutyType.name,
      'original_turn_number': current.turnNumber, 'original_book_on': current.bookOn,
      'original_book_off': current.bookOff, 'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,duty_date,manual_change_type');
  }
}
