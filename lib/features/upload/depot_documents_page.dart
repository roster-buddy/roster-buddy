import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/formatters/roster_date_format.dart';
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
    if (depot.isEmpty) return (depot: depot, documents: <Map<String, dynamic>>[]);
    final documents = <Map<String, dynamic>>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final page = await _client.from('roster_documents')
          .select('id, user_id, original_filename, detected_type, storage_path, '
              'base_roster_commencement, identified_dates, filing_category, '
              'filing_date, filing_title')
          .eq('depot', depot.toLowerCase())
          .eq('processing_status', 'processed')
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + pageSize - 1);
      documents.addAll(page);
      if (page.length < pageSize) break;
    }
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

  static const _categories = {
    'base_roster': DocumentType.baseRoster,
    '10_day_amendment': DocumentType.tenDayAmendment,
    '7_day_amendment': DocumentType.sevenDayAmendment,
    '48_hour_amendment': DocumentType.fortyEightHourAmendment,
    'annual_leave_roster': DocumentType.annualLeaveRoster,
    'job_card': DocumentType.jobCard,
  };
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String? _category(Map<String, dynamic> row) {
    final category = row['filing_category'];
    return (category == 'automatic' ? row['detected_type'] : category) as String?;
  }

  List<DateTime> _dates(Map<String, dynamic> row) {
    final assigned = DateTime.tryParse(row['filing_date'] as String? ?? '');
    if (assigned != null) return [assigned];
    final commencement = DateTime.tryParse(
      row['base_roster_commencement'] as String? ?? '',
    );
    if (commencement != null) return [commencement];
    return ((row['identified_dates'] as List?) ?? const [])
        .map((value) => DateTime.tryParse(value.toString()))
        .whereType<DateTime>()
        .toList()..sort();
  }

  Future<void> _allocate(Map<String, dynamic> row) async {
    final dates = _dates(row);
    final suggestedCategory = _category(row) ?? row['detected_type'];
    final placement = await showDialog<({String category, DateTime date, String title})>(
      context: context,
      builder: (_) => _DepotFilingDialog(
        category: _categories.containsKey(suggestedCategory)
            ? suggestedCategory as String
            : null,
        date: dates.firstOrNull,
        title: row['filing_title'] as String? ?? '',
        filename: row['original_filename'] as String,
      ),
    );
    if (!mounted || placement == null) return;
    await _run(() async {
      await _client.from('roster_documents').update({
        'filing_category': placement.category,
        'filing_date': placement.date.toIso8601String().substring(0, 10),
        'filing_title': placement.title.isEmpty ? null : placement.title,
      }).eq('id', row['id'] as String).select('id').single();
      if (mounted) setState(() => _data = _load());
    });
  }

  Widget _document(Map<String, dynamic> row, {String? title}) {
    final filename = row['original_filename'] as String;
    final isOwner = row['user_id'] == _client.auth.currentUser?.id;
    return Column(children: [
      ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(title ?? filename),
        subtitle: title != null && title != filename ? Text(filename) : null,
        trailing: isOwner
            ? PopupMenuButton<String>(
                enabled: !_busy,
                onSelected: (_) => _allocate(row),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'file', child: Text('Allocate and rename')),
                ],
              )
            : const Icon(Icons.open_in_new),
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
    ]);
  }

  List<Widget> _folders(List<Map<String, dynamic>> documents) {
    final folders = <String, Map<DateTime, List<({Map<String, dynamic> row, DateTime first, DateTime last})>>>{};
    final unknown = <Map<String, dynamic>>[];
    for (final row in documents) {
      final category = _category(row);
      final dates = _dates(row);
      if (!_categories.containsKey(category) || dates.isEmpty) {
        unknown.add(row);
        continue;
      }
      final byMonth = <DateTime, List<DateTime>>{};
      for (final date in dates) {
        byMonth.putIfAbsent(DateTime(date.year, date.month), () => []).add(date);
      }
      final months = folders.putIfAbsent(category!, () => {});
      for (final entry in byMonth.entries) {
        months.putIfAbsent(entry.key, () => []).add(
          (row: row, first: entry.value.first, last: entry.value.last),
        );
      }
    }
    return [
      for (final category in _categories.entries)
        if (folders[category.key] case final months?)
          Card(child: ExpansionTile(
            key: PageStorageKey(category.key),
            leading: const Icon(Icons.folder_outlined),
            title: Text(category.value.scanLabel),
            children: [
              for (final month in (months.keys.toList()..sort((a, b) => b.compareTo(a))))
                ExpansionTile(
                  key: PageStorageKey((category.key, month)),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text("${_months[month.month - 1]} ${month.year.toString().substring(2)}"),
                  children: [
                    for (final item in (months[month]!..sort((a, b) => b.first.compareTo(a.first))))
                      _document(
                        item.row,
                        title: item.row['filing_title'] as String? ??
                            _dateTitle(item.first, item.last),
                      ),
                  ],
                ),
            ],
          )),
      if (unknown.isNotEmpty)
        Card(child: ExpansionTile(
          key: const PageStorageKey('unknown-depot-documents'),
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Unknown'),
          children: unknown.map((row) => _document(row)).toList(),
        )),
    ];
  }

  String _dateTitle(DateTime first, DateTime last) {
    final start = displayDate(first).substring(0, 5);
    return first == last ? start : '$start–${displayDate(last).substring(0, 5)}';
  }

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
              label: const Text('Upload'),
            ),
            if (data.documents.isEmpty) const Text('No depot documents have been uploaded yet.'),
            ..._folders(data.documents),
          ],
        );
      },
    ),
  );
}


class _DepotFilingDialog extends StatefulWidget {
  const _DepotFilingDialog({
    required this.category,
    required this.date,
    required this.title,
    required this.filename,
  });

  final String? category;
  final DateTime? date;
  final String title;
  final String filename;

  @override
  State<_DepotFilingDialog> createState() => _DepotFilingDialogState();
}

class _DepotFilingDialogState extends State<_DepotFilingDialog> {
  late String? _category = widget.category;
  late DateTime? _date = widget.date;
  late final _title = TextEditingController(text: widget.title);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      helpText: 'Choose document date',
    );
    if (mounted && date != null) setState(() => _date = date);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Allocate and rename'),
    content: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.filename),
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            for (final entry in _DepotDocumentsPageState._categories.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value.scanLabel)),
          ],
          onChanged: (category) => setState(() => _category = category),
        ),
        TextButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(_date == null ? 'Choose document date' : displayDate(_date!)),
        ),
        TextField(
          controller: _title,
          decoration: InputDecoration(
            labelText: 'Title (optional)',
            hintText: _date == null ? null : displayDate(_date!).substring(0, 5),
          ),
        ),
      ],
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: _category == null || _date == null ? null : () {
          Navigator.pop(context, (
            category: _category!, date: _date!, title: _title.text.trim(),
          ));
        },
        child: const Text('Save'),
      ),
    ],
  );
}
