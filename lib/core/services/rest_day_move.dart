import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/duty.dart';
import '../models/duty_type.dart';
import '../widgets/roster_decision_sheet.dart';
import 'duty_resolver.dart';
import 'job_card_service.dart';

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

typedef RestDayDatePicker = Future<List<Duty>?> Function(
  String title, List<Duty> duties, int count, Duty? initial,
);

/// Each pair is committed together with its queue status by one database transaction.
Future<bool> actionRestDayMove(BuildContext context, List<Map<String, dynamic>> pairs, {String? id, bool awaitingAllocation = false}) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  final profile = user == null ? null : await client.from('driver_profiles').select('display_name,depot,payroll_number').eq('user_id', user.id).maybeSingle();
  final lines = pairs.map((p) => '${p['rest']} → ${p['work']}').join('\n');
  final uri = Uri.parse('mailto:drivers.rosters@wmtrains.co.uk?subject=${Uri.encodeComponent('Rest day move request')}&body=${Uri.encodeComponent('Please approve these rest day moves:\n$lines\n\nRegards\n${profile?['display_name'] ?? ''}\n${profile?['depot'] ?? ''}\nPayroll: ${profile?['payroll_number'] ?? ''}')}');
  if (!context.mounted) return false;
  final approved = awaitingAllocation ? true : await showRosterDecisionSheet<bool>(
    context: context,
    builder: (sheetContext) => RosterDecisionSheet(
      title: const Text('Confirmed by DTCM / Rosters?'),
      actions: [
        CupertinoDialogAction(onPressed: () {
          // Start directly in the tap handler for Safari's user activation.
          launchUrl(uri, mode: LaunchMode.platformDefault, webOnlyWindowName: '_self');
          Navigator.pop(sheetContext, false);
        }, child: const Text('No')),
        CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, true), child: const Text('Yes')),
      ],
    ),
  );
  if (approved == null) return false;
  final queueId = await client.rpc('action_rest_day_move', params: {
    'p_action': approved ? 'confirm' : 'request', 'p_pairs': pairs, 'p_id': id,
  });
  if (!approved || !context.mounted) return true;
  final allocated = <Map<String, dynamic>>[];
  for (final pair in pairs) {
    if (!context.mounted) return true;
    final allocation = await _allocateMovedDuty(context, pair);
    if (allocation == null) return true; // Keep it in notifications to finish later.
    allocated.add({...pair, ...allocation});
  }
  await client.rpc('allocate_rest_day_move', params: {
    'p_id': queueId, 'p_pairs': allocated,
  });
  return true;
}

List<Map<String, dynamic>> restDayMovePairs(String notes) {
  final encoded = notes.split('\n').firstWhere((line) => line.startsWith('PAIRS=')).substring(6);
  return (jsonDecode(encoded) as List).map((p) => Map<String, dynamic>.from(p as Map)).toList();
}

Future<bool> moveRestDays(BuildContext context, DateTime date, {required RestDayDatePicker pickDates}) async {
  final start = DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday % 7));
  final resolved = await DutyResolver().getResolvedDutiesForRange(start, start.add(const Duration(days: 6)));
  final duties = resolved.values.toList()..sort((a,b) => a.date.compareTo(b.date));
  final rests = duties.where((d) => d.date.weekday != DateTime.sunday && d.dutyType == DutyType.restDay).toList();
  final working = duties.where((d) => d.date.weekday != DateTime.sunday && d.dutyType.countsAsWorking && d.hasTimes).toList();
  if (!context.mounted) return false;
  if (rests.isEmpty || working.isEmpty) throw Exception('No eligible working/rest dates in this week. Sundays cannot be swapped.');
  final initial = working.where((d) => _key(d.date) == _key(date)).firstOrNull;
  final count = await showRosterDecisionSheet<int>(
    context: context,
    builder: (sheetContext) => RosterDecisionSheet(
      title: const Text('Move rest days'),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, 1), child: const Text('Just this date')),
        if (rests.length >= 2 && working.length >= 2) CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, 2), child: const Text('Multiple dates')),
        CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext), child: const Text('Back')),
      ],
    ),
  );
  if (count == null || !context.mounted) return false;
  final sources = count == 1 && initial != null ? [initial] : await pickDates('Select $count working dates to become rest days', working, count, initial);
  if (sources == null || !context.mounted) return false;
  final targets = await pickDates('Select $count rest dates to become working days', rests, count, null);
  if (targets == null || !context.mounted) return false;
  sources.sort((a,b) => a.date.compareTo(b.date));
  targets.sort((a,b) => a.date.compareTo(b.date));
  final pairs = <Map<String, dynamic>>[
    for (var i=0; i<count; i++) {
      'rest': _key(targets[i].date), 'work': _key(sources[i].date),
      'type': sources[i].dutyType.name, 'on': sources[i].bookOn, 'off': sources[i].bookOff,
      'turn': sources[i].turnNumber, 'restSource': targets[i].source.name, 'workSource': sources[i].source.name,
    }
  ];
  return actionRestDayMove(context, pairs);
}

Future<Map<String, dynamic>?> _allocateMovedDuty(BuildContext context, Map<String, dynamic> pair) async {
  List<JobCardChoice> choices = <JobCardChoice>[];
  try {
    choices = await JobCardService().findValidJobCardsForDate(dutyDate: DateTime.parse(pair['rest'] as String));
  } catch (_) {
    // Manual allocation remains available when Job Cards are unavailable.
  }
  if (!context.mounted) return null;
  final mode = await showRosterDecisionSheet<String>(
    context: context,
    builder: (sheetContext) => RosterDecisionSheet(
      title: Text("Allocate work — ${pair['rest']}"),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, 'card'), child: const Text('Job Card turn')),
        CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, 'manual'), child: const Text('Manual / cross-depot cover')),
        CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext), child: const Text('Finish later')),
      ],
    ),
  );
  if (mode == null || !context.mounted) return null;
  if (mode == 'card') {
    final selected = await showRosterDecisionSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) => RosterDecisionSheet(
        title: const Text('Select Job Card turn'),
        content: choices.isEmpty ? const Text('No valid Job Cards for this date. Go back and choose Manual / cross-depot cover.') : null,
        actions: [
          for (final choice in choices) CupertinoDialogAction(
            onPressed: () => Navigator.pop(sheetContext, <String, dynamic>{
              'turn': choice.jobCard.turnNumber, 'on': choice.jobCard.bookOn,
              'off': choice.jobCard.bookOff, 'type': 'working',
            }),
            child: Text('Turn ${choice.jobCard.turnNumber} · ${choice.jobCard.bookOn}–${choice.jobCard.bookOff}'),
          ),
          CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, <String, dynamic>{'back': true}), child: const Text('Back')),
        ],
      ),
    );
    if (selected?['back'] == true && context.mounted) return _allocateMovedDuty(context, pair);
    return selected;
  }
  final turn = TextEditingController();
  final on = TextEditingController();
  final off = TextEditingController();
  final form = GlobalKey<FormState>();
  String? validTime(String? value) {
    return RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value?.trim() ?? '')
        ? null : 'Enter HH:mm';
  }
  try {
    return await showRosterDecisionSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) => RosterDecisionSheet(
        title: Text("Manual / cross-depot cover — ${pair['rest']}"),
        content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: turn, decoration: const InputDecoration(labelText: 'Turn number (optional)')),
          TextFormField(controller: on, keyboardType: TextInputType.datetime, validator: validTime, decoration: const InputDecoration(labelText: 'Book on (HH:mm)')),
          TextFormField(controller: off, keyboardType: TextInputType.datetime, validator: validTime, decoration: const InputDecoration(labelText: 'Book off (HH:mm)')),
        ])),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext), child: const Text('Finish later')),
          CupertinoDialogAction(onPressed: () {
            if (form.currentState!.validate()) { Navigator.pop(sheetContext, <String, dynamic>{
              'turn': turn.text.trim(), 'on': on.text.trim(), 'off': off.text.trim(), 'type': 'working',
            }); }
          }, child: const Text('Confirm')),
        ],
      ),
    );
  } finally {
    // Modal reverse animation can still reference controllers briefly.
    Future<void>.delayed(const Duration(seconds: 1), () {
      turn.dispose(); on.dispose(); off.dispose();
    });
  }
}
