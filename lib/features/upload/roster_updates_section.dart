import 'package:flutter/material.dart';
import '../../core/services/roster_update_service.dart';
import 'roster_update_card.dart';

class RosterUpdatesSection extends StatelessWidget {
  const RosterUpdatesSection({required this.notices, required this.onViewed,
    required this.onOpenDocument, super.key});
  final List<RosterUpdateNotice> notices;
  final Future<void> Function(List<RosterUpdateNotice>) onViewed;
  final ValueChanged<RosterUpdateNotice> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) return const SizedBox.shrink();
    return Card(child: ListTile(
      leading: const Icon(Icons.notifications_outlined),
      title: const Text('Roster updates'),
      subtitle: Text('${notices.length} unread · Tap to view all'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final snapshot = List<RosterUpdateNotice>.unmodifiable(notices);
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
          _ViewedRosterUpdatesPage(notices: snapshot, onViewed: onViewed,
            onOpenDocument: onOpenDocument)));
      },
    ));
  }
}

class _ViewedRosterUpdatesPage extends StatefulWidget {
  const _ViewedRosterUpdatesPage({required this.notices, required this.onViewed,
    required this.onOpenDocument});
  final List<RosterUpdateNotice> notices;
  final Future<void> Function(List<RosterUpdateNotice>) onViewed;
  final ValueChanged<RosterUpdateNotice> onOpenDocument;
  @override
  State<_ViewedRosterUpdatesPage> createState() => _ViewedRosterUpdatesPageState();
}

class _ViewedRosterUpdatesPageState extends State<_ViewedRosterUpdatesPage> {
  bool _saving = true;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markViewed());
  }
  Future<void> _markViewed() async {
    if (!mounted) return;
    setState(() { _saving = true; _failed = false; });
    try {
      await widget.onViewed(widget.notices);
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      if (mounted) setState(() { _saving = false; _failed = true; });
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Roster updates')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_failed)
        ListTile(title: const Text('Could not save viewed updates. Please retry.'),
          trailing: TextButton(onPressed: _markViewed, child: const Text('Retry')))
      else Padding(padding: const EdgeInsets.only(bottom: 12),
        child: Text(_saving ? 'Marking updates as viewed…' : 'All updates below are marked as viewed.')),
      for (final notice in widget.notices)
        RosterUpdateCard(notice: notice,
          onOpenDocument: () => widget.onOpenDocument(notice), onUseShift: () {}),
    ]),
  );
}
