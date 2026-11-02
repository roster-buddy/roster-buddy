import 'package:supabase_flutter/supabase_flutter.dart';
import 'printed_roster_identity.dart';

class RosterUpdateNotice {
  const RosterUpdateNotice(this.date, this.receivedAt, this.source, this.start, this.finish, this.turn);
  final String date, source, start, finish, turn;
  final DateTime receivedAt;
  String get detail => '$source · $start–$finish${turn.isEmpty ? '' : ' · Turn $turn'}';
}

class RosterUpdateService {
  Future<List<RosterUpdateNotice>> load({DateTime? since}) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return [];
    final profile = await client.from('driver_profiles').select('payroll_number')
        .eq('user_id', user.id).maybeSingle();
    final payroll = profile?['payroll_number']?.toString();
    final key = PrintedRosterIdentity.payrollKey(payroll);
    if (key == null) return [];
    final cutoff = since ?? DateTime.now().subtract(const Duration(days: 30));
    final rows = await client.from('document_duties')
        .select('duty_date, source, payroll_number, book_on, book_off, turn_number, created_at')
        .like('payroll_number', '%$key')
        .inFilter('source', ['10_day', '7_day', '48_hour'])
        .gt('created_at', cutoff.toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return fromRows(rows, payrollNumber: payroll, since: cutoff);
  }

  static List<RosterUpdateNotice> fromRows(List<Map<String, dynamic>> rows, {
    required String? payrollNumber, required DateTime since,
  }) {
    final notices = <String, RosterUpdateNotice>{};
    const labels = {'10_day': '10D', '7_day': '7D', '48_hour': '48HR'};
    String clock(dynamic value) {
      final text = value?.toString() ?? '';
      return text.length >= 5 ? text.substring(0, 5) : '—';
    }
    for (final row in rows) {
      if (!PrintedRosterIdentity.payrollMatches(row['payroll_number']?.toString(), payrollNumber)) continue;
      final received = DateTime.tryParse(row['created_at']?.toString() ?? '');
      final date = row['duty_date']?.toString() ?? '';
      final source = labels[row['source']];
      if (received == null || !received.isAfter(since) || source == null || DateTime.tryParse(date) == null) continue;
      final notice = RosterUpdateNotice(date, received, source, clock(row['book_on']), clock(row['book_off']), row['turn_number']?.toString() ?? '');
      final key = '$date|$source';
      if (notices[key] == null || received.isAfter(notices[key]!.receivedAt)) notices[key] = notice;
    }
    return notices.values.toList()..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  }
}
