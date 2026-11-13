import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/parser/base_roster_parser.dart';
import '../smart_scan/scan_review_page.dart';
import '../../core/models/document_type.dart';
import 'base_roster_activation_page.dart';
import 'document_opener.dart';
import 'storage_service.dart';

class DepotDocumentsPage extends StatefulWidget {
  const DepotDocumentsPage({
    required this.onUpload,
    required this.onRosterChanged,
    super.key,
  });

  final Future<void> Function() onUpload;
  final VoidCallback onRosterChanged;

  @override
  State<DepotDocumentsPage> createState() => _DepotDocumentsPageState();
}

class _DepotDocumentsPageState extends State<DepotDocumentsPage> {
  final _client = Supabase.instance.client;
  late Future<({String depot, List<Map<String, dynamic>> documents})> _data;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<({String depot, List<Map<String, dynamic>> documents})> _load() async {
    final profile = await _client.from('driver_profiles')
        .select('depot').eq('user_id', _client.auth.currentUser!.id).single();
    final depot = (profile['depot'] as String? ?? '').trim();
    if (depot.isEmpty) return (depot: depot, documents: []);
    final documents = await _client.from('roster_documents')
        .select('id, original_filename, detected_type, storage_path, base_roster_commencement')
        .eq('depot', depot.toLowerCase())
        .eq('processing_status', 'processed')
        .order('created_at', ascending: false);
    return (depot: depot, documents: documents);
  }

  Future<void> _useRoster(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final commencement = DateTime.tryParse(row['base_roster_commencement'] as String? ?? '');
    final setup = await Navigator.of(context).push<BaseRosterActivation>(
      MaterialPageRoute(builder: (_) => BaseRosterActivationPage(
        fileName: row['original_filename'] as String,
        earliestCommencement: commencement,
      )),
    );
    if (!mounted || setup == null) return;
    await _run(() async {
      final document = await _client.from('roster_documents')
          .select('base_roster_pages').eq('id', id).single();
      final pages = (document['base_roster_pages'] as List?)?.cast<String>();
      if (pages == null || pages.isEmpty) {
        throw StateError('This older Base Roster needs to be uploaded once with the depot import.');
      }
      final user = _client.auth.currentUser!;
      final profile = await _client.from('driver_profiles').select('roster_number, driver_number')
          .eq('user_id', user.id).single();
      final result = await BaseRosterParser(
        commencementDate: setup.commencementDate,
        rosterNumber: (profile['roster_number'] ?? profile['driver_number']) as String?,
        startWeekNumber: setup.startWeekNumber,
        swapPartnerWeekNumber: setup.swapPartnerWeekNumber,
        initialLine: setup.startingLine == BaseRosterStartingLine.partner
            ? BaseRosterInitialLine.swapPartner : BaseRosterInitialLine.driver,
      ).parse(pageText: pages);
      if (!result.canImport) {
        throw StateError(result.warnings.where((warning) => warning.preventsImport)
            .map((warning) => warning.message).join('\n'));
      }
      await _client.from('base_rosters').upsert({
        'user_id': user.id,
        'document_id': id,
        'commencement_date': setup.commencementDate.toIso8601String().substring(0, 10),
        'has_mutual_swap': setup.hasMutualSwap,
        'start_week_number': setup.startWeekNumber,
        'swap_partner_week_number': setup.swapPartnerWeekNumber,
        'swap_partner_driver_number': null,
        'swap_partner_roster_number': null,
        'starts_with_line': setup.startingLine.name,
      }, onConflict: 'user_id,document_id');
      if (!mounted) return;
      widget.onRosterChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Base Roster added to your calendar.')),
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not complete the depot document action. $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(Object? type) => switch (type) {
    'base_roster' => DocumentType.baseRoster.scanLabel,
    '10_day_amendment' => DocumentType.tenDayAmendment.scanLabel,
    '7_day_amendment' => DocumentType.sevenDayAmendment.scanLabel,
    '48_hour_amendment' => DocumentType.fortyEightHourAmendment.scanLabel,
    'job_card' => DocumentType.jobCard.scanLabel,
    'annual_leave_roster' => DocumentType.annualLeaveRoster.scanLabel,
    _ => 'Roster document',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Depot documents')),
    body: FutureBuilder<({String depot, List<Map<String, dynamic>> documents})>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: TextButton(
            onPressed: () => setState(() => _data = _load()),
            child: const Text('Retry loading depot documents'),
          ));
        }
        final data = snapshot.data;
        if (data == null) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(data.depot, style: Theme.of(context).textTheme.headlineSmall),
            FilledButton.icon(
              onPressed: _busy || data.depot.isEmpty ? null : () => _run(() async {
                await widget.onUpload();
                if (mounted) setState(() => _data = _load());
              }),
              icon: const Icon(Icons.upload_file),
              label: Text('Upload to ${data.depot}'),
            ),
            if (data.documents.isEmpty) const Text('No depot documents have been uploaded yet.'),
            for (final row in data.documents)
              Card(child: Column(children: [
                ListTile(
                  title: Text(row['original_filename'] as String),
                  subtitle: Text(_label(row['detected_type'])),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: _busy ? null : () => _run(() => openUploadedDocument(
                    () => _client.storage.from('roster-documents')
                        .createSignedUrl(row['storage_path'] as String, 300),
                  )),
                ),
                if (row['base_roster_commencement'] != null)
                  TextButton(
                    onPressed: _busy ? null : () => _useRoster(row),
                    child: const Text('Use this Base Roster'),
                  ),
              ])),
          ],
        );
      },
    ),
  );
}
