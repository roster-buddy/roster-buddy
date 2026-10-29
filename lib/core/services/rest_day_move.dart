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
String _label(DateTime d) => '${d.day}/${d.month}/${d.year}';

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
  final rests = duties.where((d) => d.dutyType == DutyType.restDay).toList();
  if (!context.mounted) return false;
  if (rests.isEmpty) throw Exception('No rest days found in this week.');
  final initial = rests.where((d) => _key(d.date) == _key(date)).firstOrNull ?? rests.first;
  final count = await showRosterDecisionSheet<int>(
    context: context,
    builder: (sheetContext) => RosterDecisionSheet(
      title: Text('Move rest days — ${_label(initial.date)}'),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, 1), child: const Text('Just this date')),
        if (rests.length >= 2) CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext, 2), child: const Text('Multiple dates')),
        CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext), child: const Text('Back')),
      ],
    ),
  );
  if (count == null || !context.mounted) return false;
  final sources = count == 1 && _key(initial.date) == _key(date) ? [initial] : await pickDates('Select rest days in this week', rests, count, count == 2 ? initial : null);
  if (sources == null || !context.mounted) return false;
  final targets = await pickDates(count == 1 ? 'Select the date to swap with' : 'Select the dates to swap with', duties.where((d) => d.dutyType.countsAsWorking && d.hasTimes).toList(), count, null);
  if (targets == null || !context.mounted) return false;
  sources.sort((a,b) => a.date.compareTo(b.date));
  targets.sort((a,b) => a.date.compareTo(b.date));
  final pairs = <Map<String, dynamic>>[
    for (var i=0; i<count; i++) {
      'rest': _key(sources[i].date), 'work': _key(targets[i].date),
      'type': targets[i].dutyType.name, 'on': targets[i].bookOn, 'off': targets[i].bookOff,
      'turn': targets[i].turnNumber, 'restSource': sources[i].source.name, 'workSource': targets[i].source.name,
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
  final turn = TextEditingController();
  final on = TextEditingController();
  final off = TextEditingController();
  final form = GlobalKey<FormState>();
  String? validTime(String? value) {
    return RegExp(r'^(?:[01]\\d|2[0-3]):[0-5]\\d$').hasMatch(value?.trim() ?? '')
        ? null : 'Enter HH:mm';
  }
  try {
    return await showRosterDecisionSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) => RosterDecisionSheet(
        title: Text("Allocate duty — ${pair['rest']}"),
        content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (choices.isNotEmpty) DropdownButtonFormField<JobCardChoice>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Select a Job Card turn'),
            items: choices.map((choice) => DropdownMenuItem(value: choice, child: Text('Turn ${choice.jobCard.turnNumber} · ${choice.jobCard.bookOn}–${choice.jobCard.bookOff}'))).toList(),
            onChanged: (choice) {
              if (choice == null) return;
              turn.text = choice.jobCard.turnNumber;
              on.text = choice.jobCard.bookOn;
              off.text = choice.jobCard.bookOff;
            },
          ),
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
