import 'package:flutter/material.dart';
import '../../core/formatters/roster_date_format.dart';
import '../../core/services/roster_update_service.dart';

class RosterUpdateCard extends StatelessWidget {
  const RosterUpdateCard({required this.notice, required this.onOpenDocument, required this.onUseShift, super.key});
  final RosterUpdateNotice notice;
  final VoidCallback onOpenDocument, onUseShift;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${notice.needsInvestigation ? 'Annual leave conflict — investigate' : 'Roster updated'} · ${displayDate(DateTime.parse(notice.date))}',
        style: TextStyle(fontWeight: FontWeight.w800, color: notice.needsInvestigation ? const Color(0xFFD64545) : const Color(0xFF102A43))),
      const SizedBox(height: 8),
      if (notice.needsInvestigation)
        const Text('You have annual leave recorded, but this sheet lists you working. Your annual leave has been kept.'),
      Text(notice.detail),
      const SizedBox(height: 8),
      if (notice.documentId != null)
        TextButton.icon(onPressed: onOpenDocument, icon: const Icon(Icons.open_in_new),
          label: const Text('Open uploaded document')),
      if (notice.needsInvestigation)
        FilledButton.icon(onPressed: onUseShift, icon: const Icon(Icons.work_outline),
          label: const Text('Use rostered shift')),
    ]),
  ));
}
