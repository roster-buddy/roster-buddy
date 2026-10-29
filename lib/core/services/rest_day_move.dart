import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/duty.dart';
import '../models/duty_type.dart';
import '../widgets/roster_decision_sheet.dart';
import 'duty_resolver.dart';

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _label(DateTime d) => '${d.day}/${d.month}/${d.year}';

Future<List<Duty>?> _pick(BuildContext context, String title, List<Duty> duties, int count, {Duty? initial}) {
  final selected = <Duty>[?initial];
  return showRosterDecisionSheet<List<Duty>>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(builder: (context, setState) => RosterDecisionSheet(
      title: Text(title),
      content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final duty in duties) CheckboxListTile(
          title: Text(_label(duty.date)),
          subtitle: Text(duty.dutyType == DutyType.restDay ? 'Rest day' : '${duty.bookOn}–${duty.bookOff}'),
          value: selected.contains(duty),
          onChanged: (value) => setState(() {
            if (value == true && selected.length < count) selected.add(duty);
            if (value != true) selected.remove(duty);
          }),
        ),
      ])),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(sheetContext), child: const Text('Back')),
        CupertinoDialogAction(onPressed: selected.length == count ? () => Navigator.pop(sheetContext, selected) : null, child: Text('Continue (${selected.length}/$count)')),
      ],
    )),
  );
}

/// Each pair is committed together with its queue status by one database transaction.
Future<bool> actionRestDayMove(BuildContext context, List<Map<String, dynamic>> pairs, {String? id}) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  final profile = user == null ? null : await client.from('driver_profiles').select('display_name,depot,payroll_number').eq('user_id', user.id).maybeSingle();
  final lines = pairs.map((p) => '${p['rest']} → ${p['work']}').join('\n');
  final uri = Uri.parse('mailto:drivers.rosters@wmtrains.co.uk?subject=${Uri.encodeComponent('Rest day move request')}&body=${Uri.encodeComponent('Please approve these rest day moves:\n$lines\n\nRegards\n${profile?['display_name'] ?? ''}\n${profile?['depot'] ?? ''}\nPayroll: ${profile?['payroll_number'] ?? ''}')}');
  if (!context.mounted) return false;
  final approved = await showRosterDecisionSheet<bool>(
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
  await client.rpc('action_rest_day_move', params: {
    'p_action': approved ? 'confirm' : 'request',
    'p_pairs': pairs,
    'p_id': id,
  });
  return true;
}

List<Map<String, dynamic>> restDayMovePairs(String notes) {
  final encoded = notes.split('\n').firstWhere((line) => line.startsWith('PAIRS=')).substring(6);
  return (jsonDecode(encoded) as List).map((p) => Map<String, dynamic>.from(p as Map)).toList();
}

Future<bool> moveRestDays(BuildContext context, DateTime date) async {
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
  final sources = count == 1 ? [initial] : await _pick(context, 'Select rest days in this week', rests, count, initial: initial);
  if (sources == null || !context.mounted) return false;
  final targets = await _pick(context, count == 1 ? 'What date are you requesting to swap with?' : 'What dates are you requesting to swap with?', duties.where((d) => d.dutyType.countsAsWorking && d.hasTimes).toList(), count);
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
