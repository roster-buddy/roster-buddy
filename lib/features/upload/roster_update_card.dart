import 'package:flutter/material.dart';
import '../../core/services/roster_update_service.dart';

class RosterUpdateCard extends StatelessWidget {
  const RosterUpdateCard({required this.notice, required this.onOpenDocument, required this.onUseShift, this.onFollowUp, super.key});
  final RosterUpdateNotice notice;
  final VoidCallback onOpenDocument, onUseShift;
  final VoidCallback? onFollowUp;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(notice.title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: notice.needsInvestigation
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.onSurface,
        )),
      const SizedBox(height: 8),
      if (notice.needsInvestigation)
        Text(
          'The ${notice.source} sheet shows ${notice.sheetDutyLabel.toLowerCase()} '
          'for this date. Your recorded annual leave has been kept. '
          'Check with Rosters to confirm.',
        ),
      Text(notice.detail),
      const SizedBox(height: 8),
      if (notice.documentId != null)
        TextButton.icon(onPressed: onOpenDocument, icon: const Icon(Icons.open_in_new),
          label: const Text('Open uploaded document')),
      if (notice.needsInvestigation && onFollowUp != null)
        OutlinedButton.icon(onPressed: onFollowUp, icon: const Icon(Icons.email_outlined),
          label: const Text('Follow up with Rosters')),
      if (notice.needsInvestigation && notice.sheetShowsWorking)
        FilledButton.icon(onPressed: onUseShift, icon: const Icon(Icons.work_outline),
          label: const Text('Use rostered shift')),
    ]),
  ));
}
