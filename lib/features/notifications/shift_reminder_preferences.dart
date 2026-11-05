import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'push_notification_settings.dart';

const shiftReminderOptions = <int>[15, 30, 45, 60, 75, 90, 105, 120];

String shiftReminderLabel(int minutes) => switch (minutes) {
  60 => '1 hour', 120 => '2 hours',
  _ => '$minutes mins',
};

Set<int> readShiftReminderMinutes(dynamic value) => value is List
    ? value.whereType<int>().where(shiftReminderOptions.contains).toSet()
    : <int>{30};

class NotificationSettingsIcon extends StatelessWidget {
  const NotificationSettingsIcon({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 28, height: 28,
    child: Stack(children: [
      Icon(Icons.notifications_outlined, color: color, size: 25),
      Positioned(right: 0, bottom: 0, child: Icon(Icons.settings, color: color, size: 13)),
    ]));
}

class ShiftReminderPreferences extends StatelessWidget {
  const ShiftReminderPreferences({
    super.key, required this.selected, required this.onChanged, this.enabled = true,
  });
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Shift reminders',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('Remind me before book-on. Select as many times as you want, or leave all unselected for no advance reminders.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final minutes in shiftReminderOptions)
          FilterChip(
            label: Text(shiftReminderLabel(minutes)),
            selected: selected.contains(minutes),
            onSelected: !enabled ? null : (value) {
              final next = Set<int>.from(selected);
              if (value) { next.add(minutes); } else { next.remove(minutes); }
              onChanged(next);
            },
          ),
      ]),
      const SizedBox(height: 16),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.lock_clock_outlined),
        title: Text('5 minutes after book-off',
          style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Always included for working shifts. Check your finish time and edit it for delays or overtime.'),
        trailing: Icon(Icons.lock_outline, size: 18),
      ),
      const Text('Times follow your latest shift, including overnight finishes. Enable device notifications to receive reminders when the app is closed.'),
    ],
  );
}

class ShiftReminderSettingsPage extends StatefulWidget {
  const ShiftReminderSettingsPage({super.key});
  @override
  State<ShiftReminderSettingsPage> createState() => _ShiftReminderSettingsPageState();
}

class _ShiftReminderSettingsPageState extends State<ShiftReminderSettingsPage> {
  Set<int> _selected = {30};
  bool _loading = true, _saving = false, _loaded = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Sign in required');
      final row = await client.from('driver_profiles')
          .select('shift_reminder_minutes').eq('user_id', user.id).single();
      if (mounted) {
        setState(() {
        _selected = readShiftReminderMinutes(row['shift_reminder_minutes']);
        _loading = false; _loaded = true; _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
        _loading = false; _error = 'Could not load reminder preferences. Please retry.';
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Sign in required');
      await client.from('driver_profiles')
          .update({'shift_reminder_minutes': _selected.toList()..sort()})
          .eq('user_id', user.id).select('user_id').single();
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your changes. Tap Retry to save them.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [NotificationSettingsIcon(), SizedBox(width: 10), Text('Notification settings')])),
    body: _loading ? const Center(child: CircularProgressIndicator()) :
      ListView(padding: const EdgeInsets.all(20), children: [
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.red)),
          TextButton(onPressed: _saving ? null : (_loaded ? _save : _load), child: const Text('Retry')),
        ],
        Card(child: Padding(padding: const EdgeInsets.all(16),
          child: ShiftReminderPreferences(selected: _selected, enabled: !_saving,
            onChanged: !_loaded ? (_) {} : (value) {
              setState(() => _selected = value);
              _save();
            }))),
        const SizedBox(height: 12),
        Text(_saving ? 'Saving…' : 'Changes save automatically.',
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        const PushNotificationSettings(),
      ]),
  );
}
