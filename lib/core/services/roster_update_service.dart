import 'roster_notification_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'printed_roster_identity.dart';
import '../models/duty_type.dart';
import '../models/duty.dart';
import '../models/roster_source.dart';
import 'duty_resolver.dart';

class RosterUpdateNotice {
  const RosterUpdateNotice(this.date, this.receivedAt, this.source, this.start, this.finish, this.turn, {this.documentId, this.needsInvestigation = false, this.dutyType = 'working', this.amendmentCode, this.kind = 'allocated'});
  final String date, source, start, finish, turn;
  final DateTime receivedAt;
  final String? documentId;
  final bool needsInvestigation;
  final String dutyType;
  final String? amendmentCode;
  final String kind;
  String get viewKey => '${documentId ?? ''}|$date|$source|${receivedAt.toUtc().toIso8601String()}';
  String get title => RosterNotificationText.title(date, amendmentCode, dutyType, needsInvestigation ? 'leave_conflict' : kind);
  Duty? get rosteredDuty {
    final dateValue = DateTime.tryParse(date);
    final sourceValue = const {'10D': RosterSource.tenDay, '7D': RosterSource.sevenDay, '48HR': RosterSource.fortyEightHour}[source];
    final typeValue = const {'working': DutyType.working, 'training': DutyType.training, 'medical': DutyType.medical}[dutyType];
    final clock = RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$');
    if (dateValue == null || sourceValue == null || typeValue == null || !clock.hasMatch(start) || !clock.hasMatch(finish)) return null;
    int minutes(String value) => int.parse(value.substring(0, 2)) * 60 + int.parse(value.substring(3));
    return Duty(date: dateValue, source: sourceValue, dutyType: typeValue,
      bookOn: start, bookOff: finish, turnNumber: turn.isEmpty ? null : turn,
      rosteredMinutes: (minutes(finish) - minutes(start) + 1440) % 1440,
      remarks: 'Allocated from uploaded $source sheet after reviewing annual leave conflict');
  }

  String get detail => RosterNotificationText.detail(source, start, finish, turn);
}

class RosterUpdateService {
  Future<List<RosterUpdateNotice>> load({DateTime? since}) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return [];
    final profile = await client.from('driver_profiles').select('payroll_number, roster_updates_seen_at')
        .eq('user_id', user.id).maybeSingle();
    final payroll = profile?['payroll_number']?.toString();
    final key = PrintedRosterIdentity.payrollKey(payroll);
    if (key == null) return [];
    final cutoff = since ?? DateTime.now().subtract(const Duration(days: 30));
    final rows = await client.from('document_duties')
        .select('duty_date, source, payroll_number, duty_type, document_id, book_on, book_off, turn_number, amendment_code, created_at')
        .like('payroll_number', '%$key')
        .inFilter('source', ['10_day', '7_day', '48_hour'])
        .gt('created_at', cutoff.toUtc().toIso8601String())
        .order('created_at', ascending: false);
    final dates = rows.map((row) => DateTime.tryParse(row['duty_date']?.toString() ?? ''))
        .whereType<DateTime>().toList()..sort();
    final annualLeaveDates = <String>{};
    if (dates.isNotEmpty) {
      final resolved = await DutyResolver().getResolvedDutiesForRange(dates.first, dates.last);
      for (final entry in resolved.entries) {
        if (entry.value.dutyType == DutyType.annualLeave) annualLeaveDates.add(entry.key);
      }
    }
    if (dates.isNotEmpty) {
      final granted = await client.from('annual_leave_requests').select('leave_date')
          .eq('user_id', user.id).eq('status', 'granted')
          .gte('leave_date', dates.first.toIso8601String().substring(0, 10))
          .lte('leave_date', dates.last.toIso8601String().substring(0, 10));
      for (final row in granted) { annualLeaveDates.add(row['leave_date'] as String); }
    }
    final events = await client.from('roster_push_events')
        .select('document_id, duty_date, kind').eq('user_id', user.id)
        .gt('created_at', cutoff.toUtc().toIso8601String())
        .order('created_at', ascending: true);
    final kinds = <String, String>{
      for (final event in events)
        '${event['document_id']}|${event['duty_date']}': event['kind'] as String,
    };
    final viewed = await client.from('roster_update_views').select('notice_key')
        .eq('user_id', user.id)
        .gt('received_at', cutoff.toUtc().toIso8601String());
    return fromRows(rows, viewedKeys: viewed.map((row) => row['notice_key'] as String).toSet(), payrollNumber: payroll, since: cutoff, annualLeaveDates: annualLeaveDates, eventKinds: kinds, seenAt: DateTime.tryParse(profile?['roster_updates_seen_at']?.toString() ?? ''));
  }

  Future<void> markViewed(List<RosterUpdateNotice> viewed) async {
    final updates = viewed.where((notice) => !notice.needsInvestigation).toList();
    if (updates.isEmpty) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in to mark updates viewed.');
    await client.from('roster_update_views').upsert([
      for (final notice in updates)
        {'user_id': user.id, 'notice_key': notice.viewKey,
         'received_at': notice.receivedAt.toUtc().toIso8601String()},
    ], onConflict: 'user_id,notice_key', ignoreDuplicates: true);
  }

  static List<RosterUpdateNotice> fromRows(List<Map<String, dynamic>> rows, {
    required String? payrollNumber, required DateTime since,
    Set<String> annualLeaveDates = const {},
    Map<String, String> eventKinds = const {},
    DateTime? seenAt,
    Set<String> viewedKeys = const {},
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
      final notice = RosterUpdateNotice(date, received, source, clock(row['book_on']), clock(row['book_off']), row['turn_number']?.toString() ?? '',
        documentId: row['document_id']?.toString(),
        dutyType: row['duty_type']?.toString() ?? 'working',
        amendmentCode: row['amendment_code']?.toString(),
        kind: eventKinds['${row['document_id']}|$date'] ?? 'allocated',
        needsInvestigation: annualLeaveDates.contains(date) && ['working', 'training', 'medical'].contains(row['duty_type']),
      );
      final key = '$date|$source';
      if (notices[key] == null || received.isAfter(notices[key]!.receivedAt)) notices[key] = notice;
    }
    return notices.values.where((notice) => notice.needsInvestigation ||
        !((seenAt != null && !notice.receivedAt.isAfter(seenAt)) ||
          viewedKeys.contains(notice.viewKey))).toList()..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  }
}
