import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/annual_leave_request.dart';

/// Shared by the calendar and Annual Leave page. Never sends email itself.
Future<bool> manageFloatingLeaveCancellation({
  required BuildContext context,
  required List<AnnualLeaveRequest> requests,
}) async {
  if (requests.isEmpty) return false;
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return false;
  try {
    final sorted = requests.toList()..sort((a, b) => a.leaveDate.compareTo(b.leaveDate));
    final pending = sorted.every((r) => r.cancellationPending);
    final profile = await client.from('driver_profiles')
        .select('display_name,depot,payroll_number').eq('user_id', user.id).maybeSingle();
    String dateLabel(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final dates = sorted.map((r) => dateLabel(r.leaveDate)).join('\n');
    final signature = [
      profile?['display_name'], profile?['depot'],
      if (profile?['payroll_number'] != null) 'Payroll Number: ${profile!['payroll_number']}',
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join('\n');
    final body = 'Please can I cancel my previously granted floating annual leave for:\n\n$dates\n\nRegards\n$signature';
    final uri = Uri.parse('mailto:drivers.rosters@wmtrains.co.uk'
        '?subject=${Uri.encodeComponent('Floating Annual Leave Cancellation')}'
        '&body=${Uri.encodeComponent(body)}');
    if (!context.mounted) return false;
    Future<bool>? email;
    final action = await showModalBottomSheet<String>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(pending ? 'Action pending cancellation' : 'Cancel annual leave',
            style: const TextStyle(color: Color(0xFF102A43), fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Text(dates),
          const SizedBox(height: 12),
          const Text('Leave stays granted and deducted until Rosters confirms cancellation.'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              email = launchUrl(uri, webOnlyWindowName: '_self');
              Navigator.pop(sheetContext, 'request');
            },
            icon: const Icon(Icons.mail_outline),
            label: Text(pending ? 'Prepare cancellation email again' : 'Prepare email and mark pending')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(sheetContext, 'confirm'),
            child: const Text('Rosters has confirmed cancellation')),
          if (pending) OutlinedButton(
            onPressed: () => Navigator.pop(sheetContext, 'retain'),
            child: const Text('Declined / withdrawn — keep leave')),
          TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Back')),
        ]),
      )),
    );
    if (action == null) return false;
    if (action == 'request' && !(await email!)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email. No cancellation was recorded.')));
      }
      return false;
    }
    await client.rpc('action_floating_leave_cancellation', params: {
      'p_ids': sorted.map((r) => r.id).toList(), 'p_action': action,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(action == 'confirm'
          ? 'Cancellation confirmed. Balance and calendar updated.'
          : action == 'retain'
              ? 'Leave retained. Pending cancellation cleared.'
              : 'Cancellation pending. Send the prepared draft from your email app. Leave stays granted until confirmed.'),
      ));
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update cancellation. Refresh the leave list and try again.')));
    }
    return false;
  }
}
