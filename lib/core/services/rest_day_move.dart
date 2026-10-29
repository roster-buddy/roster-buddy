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
import '../widgets/roster_time_input_formatter.dart';

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
  final date = DateTime.parse(pair['rest'] as String);
  List<JobCardChoice> choices = <JobCardChoice>[];
  try {
    choices = await JobCardService().findValidJobCardsForDate(dutyDate: date);
  } catch (_) {
    // Manual allocation remains available when Job Cards are unavailable.
  }
  if (!context.mounted) return null;
  final turn = TextEditingController();
  final on = TextEditingController();
  final off = TextEditingController();
  final form = GlobalKey<FormState>();
  var selection = -1;
  const border = OutlineInputBorder();
  String? validTime(String? value) {
    return RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(RosterTimeInputFormatter.normalise(value ?? ''))
        ? null : 'Enter HH:mm';
  }
  try {
    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
            child: Form(key: form, child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Allocate shift', style: TextStyle(color: Color(0xFF102A43), fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(MaterialLocalizations.of(context).formatFullDate(date), style: const TextStyle(color: Color(0xFF52667A))),
                const SizedBox(height: 18),
                DropdownButtonFormField<int>(
                  initialValue: selection,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Turn / Job Card', border: border),
                  items: [
                    const DropdownMenuItem(value: -1, child: Text('Manual / cross-depot duty')),
                    for (var i = 0; i < choices.length; i++) DropdownMenuItem(
                      value: i,
                      child: Text('Turn ${choices[i].jobCard.turnNumber} · ${choices[i].jobCard.bookOn}–${choices[i].jobCard.bookOff}'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    selection = value ?? -1;
                    if (selection >= 0) {
                      final card = choices[selection].jobCard;
                      turn.text = card.turnNumber; on.text = card.bookOn; off.text = card.bookOff;
                    } else {
                      turn.clear(); on.clear(); off.clear();
                    }
                  }),
                ),
                const SizedBox(height: 12),
                if (selection == -1) ...[
                  TextFormField(controller: turn, decoration: const InputDecoration(labelText: 'Manual turn / duty reference', border: border)),
                  const SizedBox(height: 12),
                ],
                Row(children: [
                  Expanded(child: TextFormField(controller: on, keyboardType: TextInputType.number, inputFormatters: const [RosterTimeInputFormatter()], validator: validTime,
                    decoration: const InputDecoration(labelText: 'Book on', hintText: 'HH:mm', border: border))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: off, keyboardType: TextInputType.number, inputFormatters: const [RosterTimeInputFormatter()], validator: validTime,
                    decoration: const InputDecoration(labelText: 'Book off', hintText: 'HH:mm', border: border))),
                ]),
                const SizedBox(height: 10),
                const Text('Selecting a Job Card fills its booked times automatically. Manual or cross-depot duties can still be entered.',
                  style: TextStyle(color: Color(0xFF52667A), height: 1.4)),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Save allocated shift'),
                  onPressed: () {
                    if (form.currentState!.validate()) {
                      Navigator.pop(sheetContext, <String, dynamic>{
                        'turn': turn.text.trim(), 'on': RosterTimeInputFormatter.normalise(on.text), 'off': RosterTimeInputFormatter.normalise(off.text), 'type': 'working',
                      });
                    }
                  },
                ),
                TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Finish later')),
              ],
            )),
          ),
        ),
      ),
    );
  } finally {
    Future<void>.delayed(const Duration(seconds: 1), () {
      turn.dispose(); on.dispose(); off.dispose();
    });
  }
}
