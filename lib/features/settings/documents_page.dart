import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/formatters/roster_date_format.dart';

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key, this.loadPage, this.signedUrl, this.openDocument});
  final Future<List<Map<String, dynamic>>> Function(int offset)? loadPage;
  final Future<String> Function(String path)? signedUrl;
  final Future<bool> Function(Uri uri)? openDocument;

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  final List<Map<String, dynamic>> _documents = [];
  bool _loading = true;
  bool _hasMore = true;
  String? _error;
  String? _opening;

  @override
  void initState() { super.initState(); _load(); }

  Future<List<Map<String, dynamic>>> _fetch(int offset) async {
    if (widget.loadPage != null) return widget.loadPage!(offset);
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in to view documents');
    return await client.from('roster_documents')
        .select('id,original_filename,storage_path,detected_type,processing_status,file_size_bytes,created_at')
        .eq('user_id', user.id).order('created_at', ascending: false)
        .order('id').range(offset, offset + 49);
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _fetch(refresh ? 0 : _documents.length)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        if (refresh) _documents.clear();
        _documents.addAll(rows);
        _hasMore = rows.length == 50;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Could not load documents. Please try again.';
      });
    }
  }

  Future<void> _showDocument(Map<String, dynamic> row) async {
    if (_opening != null) return;
    setState(() => _opening = row['id'].toString());
    try {
      final path = row['storage_path']?.toString() ?? '';
      if (path.isEmpty) throw StateError('No stored file');
      final url = await (widget.signedUrl?.call(path) ??
          Supabase.instance.client.storage.from('roster-documents').createSignedUrl(path, 300))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() => _opening = null);
      await showModalBottomSheet<void>(
        context: context, showDragHandle: true, isScrollControlled: true,
        builder: (sheetContext) => SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min, children: [
              Text(row['original_filename']?.toString() ?? 'Document',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF102A43))),
              const SizedBox(height: 16),
              Text('Uploaded ${displayStoredDate(row['created_at']?.toString().split('T').first)}'),
              const SizedBox(height: 8),
              Text('Status: ${_label(row['processing_status'])}'),
              const SizedBox(height: 20),
              FilledButton.icon(icon: const Icon(Icons.open_in_new), label: const Text('Open document'),
                onPressed: () async {
                  bool opened = false;
                  try {
                    opened = await (widget.openDocument?.call(Uri.parse(url)) ??
                        launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault, webOnlyWindowName: '_blank'));
                  } catch (_) { /* Show the same retry message for launch errors. */ }
                  if (!opened && sheetContext.mounted) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(
                      content: Text('Could not open the file. Please try again.')));
                  }
                }),
            ]),
        )),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not open this document. Please try again.')));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  String _label(Object? value) {
    final text = (value ?? 'Unknown').toString().replaceAll('_', ' ');
    return text.isEmpty ? 'Unknown' : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Documents')),
    backgroundColor: const Color(0xFFF4F7FA),
    body: RefreshIndicator(onRefresh: () => _load(refresh: true),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
          const Text('Your uploaded rosters, amendments and job cards.', style: TextStyle(color: Color(0xFF52667A))),
          const SizedBox(height: 16),
          for (final row in _documents) Card(child: ListTile(
            leading: const Icon(Icons.description_outlined, color: Color(0xFF1769AA)),
            title: Text(row['original_filename']?.toString() ?? 'Document'),
            subtitle: Text('${_label(row['detected_type'])} · ${_label(row['processing_status'])}'),
            trailing: _opening == row['id'].toString()
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: () => _showDocument(row),
          )),
          if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (!_loading && _documents.isEmpty && _error == null)
            const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No uploaded documents yet. Add a roster using Upload.'))),
          if (_error != null) ...[
            Text(_error!),
            OutlinedButton(onPressed: () => _load(refresh: _documents.isEmpty), child: const Text('Retry')),
          ],
          if (!_loading && _hasMore && _error == null)
            OutlinedButton(onPressed: _load, child: const Text('Load more')),
        ]),
      )),
    ),
  );
}
