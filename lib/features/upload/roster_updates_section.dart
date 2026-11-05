import 'package:flutter/material.dart';
import '../../core/services/roster_update_service.dart';
import 'roster_update_card.dart';

class RosterUpdatesSection extends StatefulWidget {
  const RosterUpdatesSection({required this.notices, required this.onViewed,
    required this.onOpenDocument, super.key});
  final List<RosterUpdateNotice> notices;
  final Future<void> Function(List<RosterUpdateNotice>) onViewed;
  final ValueChanged<RosterUpdateNotice> onOpenDocument;

  @override
  State<RosterUpdatesSection> createState() => _RosterUpdatesSectionState();
}

class _RosterUpdatesSectionState extends State<RosterUpdatesSection> {
  bool _saving = false;
  String? _error;
  List<RosterUpdateNotice>? _retry;

  Future<void> _clear(List<RosterUpdateNotice> snapshot) async {
    if (_saving || snapshot.isEmpty) return;
    setState(() { _saving = true; _error = null; _retry = null; });
    try {
      await widget.onViewed(snapshot);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not clear these updates. Please retry.';
          _retry = snapshot;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open(RosterUpdateNotice notice) async {
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Roster update'),
      content: SingleChildScrollView(child: RosterUpdateCard(notice: notice,
        onOpenDocument: () => widget.onOpenDocument(notice), onUseShift: () {})),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Done'))],
    ));
    if (mounted) await _clear([notice]);
  }

  @override
  Widget build(BuildContext context) {
    // Investigation items are pending actions and cannot be cleared here.
    final notices = widget.notices.where((n) => !n.needsInvestigation).toList();
    if (notices.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Text('Roster updates',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        TextButton(onPressed: _saving ? null : () =>
          _clear(List<RosterUpdateNotice>.unmodifiable(notices)),
          child: const Text('Clear all roster updates')),
      ]),
      if (_error != null)
        ListTile(title: Text(_error!),
          trailing: TextButton(onPressed: _saving || _retry == null
            ? null : () => _clear(_retry!), child: const Text('Retry'))),
      for (final notice in notices)
        Card(child: ListTile(
          title: Text(notice.title),
          subtitle: Text(notice.detail),
          trailing: const Icon(Icons.chevron_right),
          onTap: _saving ? null : () => _open(notice),
        )),
      const SizedBox(height: 16),
    ]);
  }
}
