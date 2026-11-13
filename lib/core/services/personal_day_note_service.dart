import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalDayNoteService {
  PersonalDayNoteService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<String?> getNote(DateTime date) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return null;
    final Map<String, dynamic>? row = await _client
        .from('personal_day_notes')
        .select('note')
        .eq('user_id', user.id)
        .eq('note_date', _dateKey(date))
        .maybeSingle();
    final String note = row?['note']?.toString().trim() ?? '';
    return note.isEmpty ? null : note;
  }

  Future<Set<String>> getNoteDates(DateTime start, DateTime end) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return <String>{};
    final List<dynamic> rows = await _client
        .from('personal_day_notes')
        .select('note_date')
        .eq('user_id', user.id)
        .gte('note_date', _dateKey(start))
        .lte('note_date', _dateKey(end));
    return rows
        .whereType<Map<String, dynamic>>()
        .map((row) => row['note_date']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<void> saveNote(DateTime date, String value) async {
    final User? user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to save a note.');
    final String note = value.trim();
    if (note.isEmpty) return deleteNote(date);
    await _client.from('personal_day_notes').upsert(<String, dynamic>{
      'user_id': user.id,
      'note_date': _dateKey(date),
      'note': note,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> deleteNote(DateTime date) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('personal_day_notes')
        .delete()
        .eq('user_id', user.id)
        .eq('note_date', _dateKey(date));
  }
}
