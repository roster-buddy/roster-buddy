import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'document_opener.dart';

class DayDocumentLinks extends StatefulWidget {
  const DayDocumentLinks({required this.date, this.loadDocuments, this.openDocument, super.key});
  final DateTime date;
  final Future<List<Map<String, dynamic>>> Function(DateTime)? loadDocuments;
  final Future<void> Function(Map<String, dynamic>)? openDocument;
  @override
  State<DayDocumentLinks> createState() => _DayDocumentLinksState();
}

class _DayDocumentLinksState extends State<DayDocumentLinks> {
  late Future<List<Map<String, dynamic>>> _documents;
  String? _opening;
  bool _expanded = false;
  @override
  void initState() { super.initState(); _documents = _load(); }

  Future<List<Map<String, dynamic>>> _load() async {
    if (widget.loadDocuments != null) return widget.loadDocuments!(widget.date);
    return await Supabase.instance.client.from('roster_documents')
        .select('id, original_filename, detected_type, storage_path, created_at')
        .contains('identified_dates', [widget.date.toIso8601String().substring(0, 10)])
        .order('created_at', ascending: false);
  }

  Future<void> _open(Map<String, dynamic> row) async {
    if (_opening != null) return;
    setState(() => _opening = row['id'].toString());
    try {
      if (widget.openDocument != null) {
        await widget.openDocument!(row);
      } else {
        await openUploadedDocument(() => Supabase.instance.client.storage
            .from('roster-documents').createSignedUrl(row['storage_path'] as String, 300));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open this uploaded document. Please retry.')));
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  String _label(dynamic type) => switch (type?.toString()) {
    '7_day' || '7_day_amendment' || 'seven_day_amendment' => '7-day sheet',
    '10_day' || '10_day_amendment' || 'ten_day_amendment' => '10-day sheet',
    '48_hour' || '48_hour_amendment' || 'forty_eight_hour_amendment' => '48-hour sheet',
    'base_roster' => 'Base Roster',
    'annual_leave_roster' => 'Annual Leave Roster',
    'job_card' => 'Job Card',
    _ => (type?.toString() ?? 'Document').replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _documents,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator());
      }
      if (snapshot.hasError) {
        return TextButton.icon(
          onPressed: () => setState(() => _documents = _load()),
          icon: const Icon(Icons.refresh), label: const Text('Retry uploaded documents'));
      }
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('Uploaded documents', style: TextStyle(fontWeight: FontWeight.w800))),
          if (rows.length > 1)
            IconButton(
              tooltip: _expanded ? 'Show latest upload only' : 'Show all uploads (${rows.length})',
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ),
        ]),
        for (final row in (_expanded ? rows : rows.take(1)))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(_label(row['detected_type'])),
            subtitle: Text(row['original_filename']?.toString() ?? 'Uploaded document'),
            trailing: _opening == row['id'].toString()
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.open_in_new),
            onTap: _opening == null ? () => _open(row) : null,
          ),
        const Divider(),
      ]);
    },
  );
}
