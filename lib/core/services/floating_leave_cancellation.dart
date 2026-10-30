import 'driver_email_identity.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/annual_leave_request.dart';

/// Shared by the calendar and Annual Leave page. Never sends email itself.
Future<bool> manageFloatingLeaveCancellation({
  required BuildContext context,
  required List<AnnualLeaveRequest> requests,
  Map<String, dynamic>? historyRestore,
}) async {
  if (requests.isEmpty) return false;
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return false;
  try {
    final sorted = requests.toList()..sort((a, b) => a.leaveDate.compareTo(b.leaveDate));
    final profile = await client.from('driver_profiles')
        .select('display_name,depot,payroll_number').eq('user_id', user.id).maybeSingle();
    String dateLabel(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final dates = sorted.map((r) => dateLabel(r.leaveDate)).join('\n');
    final signature = [
      await driverNumberEmailLine(),
      if (profile?['payroll_number'] != null) 'Payroll Number: ${profile!['payroll_number']}',
      profile?['depot'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join('\n');
    final body = 'Please can I cancel my previously granted floating annual leave for:\n\n$dates\n\n$signature';
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
          Text('Cancellation confirmed by DTCM / Rosters?',
            style: const TextStyle(color: Color(0xFF102A43), fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              email = launchUrl(uri, webOnlyWindowName: '_self');
              Navigator.pop(sheetContext, 'request');
            },
            icon: const Icon(Icons.mail_outline),
            label: const Text('No')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(sheetContext, 'confirm'),
            child: const Text('Yes')),
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
    if (historyRestore != null) {
      if (sorted.length != 1) throw StateError('Select one historical shift');
      await client.rpc('cancel_leave_for_history', params: {
        'p_id': sorted.single.id, 'p_action': action, 'p_restore': historyRestore,
      });
    } else {
      await client.rpc('action_floating_leave_cancellation', params: {
        'p_ids': sorted.map((r) => r.id).toList(), 'p_action': action,
      });
    }
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
