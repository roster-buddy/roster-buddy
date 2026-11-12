import '../../core/models/duty_type.dart';
import '../../core/services/printed_roster_identity.dart';
import 'package:flutter/material.dart';

import '../../core/formatters/roster_date_format.dart';
import '../../core/models/document_type.dart';
import '../../core/models/parse_result.dart';
import '../../core/models/parse_warning.dart';
import '../../core/models/duty.dart';
import '../../core/models/roster_source.dart';
import 'scan_duty_editor.dart';
import '../upload/base_roster_activation_page.dart';
import '../upload/document_processing_service.dart';
import '../upload/storage_service.dart';
import '../upload/upload_service.dart';
import 'smart_scan_engine.dart';
import 'scan_import_policy.dart';
import 'smart_scan_result.dart';

extension ScanDocumentLabel on DocumentType {
  String get scanLabel => switch (this) {
    DocumentType.baseRoster => 'Base Roster',
    DocumentType.tenDayAmendment => '10-Day Amendment',
    DocumentType.sevenDayAmendment => '7-Day Amendment',
    DocumentType.fortyEightHourAmendment => '48-Hour Amendment',
    DocumentType.annualLeaveRoster => 'Annual Leave Roster',
    DocumentType.jobCard => 'Job Card',
    DocumentType.unknown => 'Choose document type',
  };
}

class ReviewedDocument {
  const ReviewedDocument(this.type, this.result, this.activation);
  final DocumentType type;
  final ParseResult result;
  final BaseRosterActivation? activation;
}

typedef ScanReader =
    Future<List<SmartScanResult>> Function(
      void Function(String, double?) progress,
    );
typedef ScanParser =
    Future<ParseResult> Function(
      List<SmartScanResult> pages,
      DocumentType type,
      BaseRosterActivation? activation,
    );

class ScanReviewPage extends StatefulWidget {
  const ScanReviewPage({
    required this.upload,
    this.readDocument,
    this.parseDocument,
    super.key,
  });
  final PickedUpload upload;
  final ScanReader? readDocument;
  final ScanParser? parseDocument;

  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends State<ScanReviewPage> {
  List<SmartScanResult>? _pages;
  DocumentType _type = DocumentType.unknown;
  ParseResult? _parsed;
  BaseRosterActivation? _activation;
  String _progressMessage = 'Preparing scanner…';
  double? _progress;
  String? _error;
  bool _busy = true;
  bool _excludeUnreadable = false;
  bool _completed = false;
  bool _baseRosterOrientationChecked = false;
  bool get _daily => [
    DocumentType.tenDayAmendment,
    DocumentType.sevenDayAmendment,
    DocumentType.fortyEightHourAmendment,
  ].contains(_type);
  bool _unreadable(ParseWarning w) =>
      w.preventsImport &&
      w.message.startsWith('A roster row could not be read safely');
  ParseResult? get _effective {
    final parsed = _parsed;
    if (parsed == null || !_excludeUnreadable) return parsed;
    return parsed.copyWith(
      warnings: parsed.warnings
          .map(
            (w) => _unreadable(w)
                ? ParseWarning(
                    message: w.message,
                    pageNumber: w.pageNumber,
                    severity: ParseWarningSeverity.warning,
                  )
                : w,
          )
          .toList(),
    );
  }

  Future<void> _editRecord([int? index, ParseWarning? warning]) async {
    final parsed = _parsed!;
    final source = switch (_type) {
      DocumentType.tenDayAmendment => RosterSource.tenDay,
      DocumentType.fortyEightHourAmendment => RosterSource.fortyEightHour,
      _ => RosterSource.sevenDay,
    };
    final rowText = warning?.message.split(': ').last;
    final row = rowText == null ? null : RegExp(
      r'^(.+?)\s+([0-9]{4,8})\s+([A-Za-z]{2,5})\b(.*)$',
    ).firstMatch(rowText);
    final date = parsed.duties.isNotEmpty
        ? parsed.duties.first.date
        : parsed.identifiedDates.isNotEmpty ? parsed.identifiedDates.first : null;
    final seed = row == null || date == null ? null : Duty(
      date: date, source: source, dutyType: DutyType.unknown,
      payrollNumber: row.group(2), driverName: row.group(1),
      depot: row.group(3), rawText: rowText, pageNumber: warning?.pageNumber,
    );
    final duty = await showDialog<Duty>(
      context: context,
      builder: (_) => ScanDutyEditor(
        source: source,
        initial: index == null ? seed : parsed.duties[index],
        date: date,
        payroll: warning == null ? parsed.payrollNumber : row?.group(2),
      ),
    );
    if (!mounted || duty == null) return;
    final duties = List<Duty>.from(parsed.duties);
    if (index != null) duties.removeAt(index);
    duties.removeWhere(
      (d) => d.payrollNumber == duty.payrollNumber && d.date == duty.date,
    );
    duties.insert(0, duty);
    setState(
      () => _parsed = parsed.copyWith(
        duties: duties,
        warnings: parsed.warnings.where((w) => w.message != warning?.message ||
            w.pageNumber != warning?.pageNumber).toList(),
        ownRecordCount: parsed.payrollNumber == null
            ? null
            : duties
                  .where((d) => PrintedRosterIdentity.payrollMatches(d.payrollNumber, parsed.payrollNumber))
                  .length,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    if (_busy && widget.readDocument == null) SmartScanEngine.cancel();
    super.dispose();
  }

  void _report(String message, double? fraction) {
    if (mounted) {
      setState(() {
        _progressMessage = message;
        _progress = fraction;
      });
    }
  }

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _error = null;
      _parsed = null;
      _type = DocumentType.unknown;
      _excludeUnreadable = false;
      _progress = null;
      _baseRosterOrientationChecked = false;
    });
    try {
      final List<SmartScanResult> pages;
      if (widget.readDocument != null) {
        pages = await widget.readDocument!(_report);
      } else if (widget.upload.photoPages.isNotEmpty) {
        final photos = widget.upload.photoPages;
        pages = [];
        for (var index = 0; index < photos.length; index++) {
          final photo = photos[index];
          final pageLabel = 'Page ${index + 1} of ${photos.length}';
          try {
            final page = await SmartScanEngine.recogniseImage(
              bytes: photo.bytes,
              fileName: photo.fileName,
              onProgress: (message, fraction) => _report(
                '$pageLabel · $message',
                fraction == null ? null : (index + fraction) / photos.length,
              ),
            );
            if (!mounted) return;
            if (!page.hasText) {
              throw const SmartScanException('No readable text was found.');
            }
            pages.add(page);
          } on SmartScanException catch (error) {
            throw SmartScanException('$pageLabel: ${error.message}');
          }
        }
      } else if (widget.upload.fileName.toLowerCase().endsWith('.pdf')) {
        pages = await SmartScanEngine.recognisePdf(
          bytes: widget.upload.bytes,
          fileName: widget.upload.fileName,
          onProgress: _report,
        );
      } else {
        pages = [
          await SmartScanEngine.recogniseImage(
            bytes: widget.upload.bytes,
            fileName: widget.upload.fileName,
            onProgress: _report,
          ),
        ];
      }
      if (!mounted) return;
      if (pages.isEmpty || pages.any((page) => !page.hasText)) {
        throw const SmartScanException(
          'No readable text was found. Take a clearer photo and try again.',
        );
      }
      setState(() {
        _pages = pages;
        _type = DocumentType.unknown;
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _prepare({bool automatic = false}) async {
    if (_type == DocumentType.baseRoster && _activation == null) {
      final activation = await Navigator.of(context).push<BaseRosterActivation>(
        MaterialPageRoute(
          builder: (_) =>
              BaseRosterActivationPage(fileName: widget.upload.fileName),
        ),
      );
      if (!mounted || activation == null) return;
      _activation = activation;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
      _progressMessage = 'Checking dates and shifts…';
    });
    try {
      if (_type == DocumentType.baseRoster &&
          !_baseRosterOrientationChecked &&
          widget.readDocument == null &&
          widget.upload.photoPages.isEmpty &&
          widget.upload.fileName.toLowerCase().endsWith('.pdf')) {
        _pages = await SmartScanEngine.recogniseBaseRosterPdf(
          bytes: widget.upload.bytes,
          fileName: widget.upload.fileName,
          onProgress: _report,
        );
        _baseRosterOrientationChecked = true;
      }
      final result = widget.parseDocument != null
          ? await widget.parseDocument!(_pages!, _type, _activation)
          : await DocumentProcessingService.parseScanResults(
              scanResults: _pages!,
              documentType: _type,
              baseRosterCommencementDate: _activation?.commencementDate,
              baseRosterSwapPartnerRosterNumber:
                  _activation?.hasMutualSwap == true
                  ? _activation?.swapPartnerRosterNumber
                  : null,
              baseRosterStartsWithPartner:
                  _activation?.startingLine == BaseRosterStartingLine.partner,
            );
      if (mounted) {
        setState(() {
          _parsed = result;
          _busy = false;
        });
        if (automatic && !_completed &&
            ScanImportPolicy.allRowsRead(result, _pages!)) {
          _completed = true;
          Navigator.pop(context, ReviewedDocument(_type, result.copyWith(allRowsRead: true), _activation));
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  bool _canEditBaseRosterRow(ParseWarning warning) {
    final page = warning.pageNumber;
    return _type == DocumentType.baseRoster &&
        warning.weekNumber != null &&
        page != null &&
        page > 0 &&
        page <= _pages!.length &&
        _pages![page - 1].lines.isEmpty &&
        _pages![page - 1].fullText.startsWith('WEEK | SUNDAY | MONDAY |');
  }

  Future<void> _editBaseRosterRow(ParseWarning warning, {bool showAll = false}) async {
    if (warning.weekNumber == null) return;
    final pageIndex = warning.pageNumber! - 1;
    final page = _pages![pageIndex];
    final lines = page.fullText.split('\n');
    final index = lines.indexWhere(
      (line) => line.startsWith('${warning.weekNumber} |'),
    );
    if (index < 0 || index + 1 >= lines.length) return;

    final cells = lines[index].split('|').map((cell) => cell.trim()).toList();
    if (cells.length != 8) return;
    final identity = lines[index + 1];
    final corrections = await showDialog<List<String>>(
      context: context,
      builder: (_) => _BaseRosterRowCorrection(
        lineNumber: warning.weekNumber!,
        pageNumber: warning.pageNumber!,
        cells: cells,
        identity: identity,
        showAll: showAll,
      ),
    );
    if (!mounted || corrections == null) return;

    lines[index] = corrections.take(8).join(' | ');
    lines[index + 1] = corrections.last;
    setState(() {
      _pages = List<SmartScanResult>.of(_pages!)
        ..[pageIndex] = SmartScanResult(
          fullText: lines.join('\n'),
          lines: const [],
          confidence: page.confidence,
        );
    });
    await _prepare();
  }

  Widget _recognisedPage(int pageIndex, SmartScanResult page) {
    if (_type != DocumentType.baseRoster ||
        page.lines.isNotEmpty ||
        !page.fullText.startsWith('WEEK | SUNDAY | MONDAY |')) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText('Page ${pageIndex + 1}\n${page.fullText}'),
      );
    }

    final rows = page.fullText.split('\n');
    return ExpansionTile(
      title: Text('Page ${pageIndex + 1}'),
      children: [
        for (var index = 1; index + 1 < rows.length; index += 2)
          ListTile(
            title: Text('Roster line ${rows[index].split('|').first.trim()}'),
            subtitle: Text(rows[index + 1] == '?'
                ? 'Check roster number'
                : 'Roster number ${rows[index + 1]}'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editBaseRosterRow(
              ParseWarning(
                message: '',
                pageNumber: pageIndex + 1,
                weekNumber: int.tryParse(rows[index].split('|').first.trim()),
              ),
              showAll: true,
            ),
          ),
      ],
    );
  }

  Widget _header() {
    final parsed = _effective;
    final reviewReasons = parsed == null || !_daily
        ? const <String>[]
        : ScanImportPolicy.reviewReasons(parsed, _pages!);
    final unmatchedRows = parsed == null || !_daily
        ? const <ParseWarning>[]
        : ScanImportPolicy.unmatchedRows(parsed, _pages!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.upload.fileName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Choose the document type, then check the rows. Complete shift sheets are applied automatically; anything unclear stays here for correction.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<DocumentType>(
          key: ValueKey(_type),
          initialValue: _type == DocumentType.unknown ? null : _type,
          decoration: const InputDecoration(
            labelText: 'Document type',
            border: OutlineInputBorder(),
          ),
          items: DocumentType.values
              .where((type) => type != DocumentType.unknown)
              .map(
                (type) =>
                    DropdownMenuItem(value: type, child: Text(type.scanLabel)),
              )
              .toList(),
          onChanged: (type) {
            if (type != null) {
              setState(() {
                _type = type;
                _parsed = null;
                _excludeUnreadable = false;
                _activation = null;
                _error = null;
              });
            }
          },
        ),
        if (_type == DocumentType.unknown) ...[
          const SizedBox(height: 12),
          const Text(
            'Choose which kind of roster or document you are uploading.',
          ),
        ],
        if (_pages!.any((p) => p.confidence != null && p.confidence! < 65))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Some text may be unclear. Check the dates, times and driver numbers carefully.',
            ),
          ),
        ExpansionTile(
          title: Text('Recognised text · ${_pages!.length} page(s)'),
          children: [
            for (final entry in _pages!.asMap().entries)
              _recognisedPage(entry.key, entry.value),
          ],
        ),
        if (parsed != null) ...[
          const SizedBox(height: 12),
          Text(
            '${parsed.calculatedRecordCount} records found',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (parsed.ownRecordCount != null)
            Text('${parsed.ownRecordCount} records match your calendar.'),
          if (parsed.ownRecordCount == 0)
            const Text(
              'No rows matched your profile. This import will not update your own shifts.',
            ),
          if (_daily)
            for (final reason in reviewReasons)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('Review needed: $reason'),
              ),
          if (unmatchedRows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${unmatchedRows.length} rows need correction. '
              'The ${parsed.duties.length} correctly read rows are kept and hidden below.',
            ),
            for (final warning in unmatchedRows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(warning.message.split(': ').last),
                subtitle: const Text('Tap to correct only this row'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editRecord(null, warning),
              ),
          ] else if (reviewReasons.isEmpty && parsed.duties.isNotEmpty)
            const Text('All recognised records passed the automatic checks.')
          else if (_type == DocumentType.baseRoster)
            const Text('Check the flagged lines below. The readable shifts are shown in the preview.')
          else
            const Text(
              'Only the unresolved items shown above need checking. '
              'Correctly read rows are kept automatically.',
            ),
          for (final warning in parsed.warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _unreadable(warning)
                  ? ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(warning.message),
                      subtitle: const Text('Tap to correct this row'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editRecord(null, warning),
                    )
                  : _canEditBaseRosterRow(warning)
                  ? ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(warning.message),
                      subtitle: const Text('Tap to correct this row'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editBaseRosterRow(warning),
                    )
                  : Text(warning.message),
            ),
          if (_daily) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _editRecord(),
              icon: const Icon(Icons.add),
              label: const Text('Add missing shift'),
            ),
          ],
          if (!parsed.canImport && !parsed.warnings.any(_canEditBaseRosterRow))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'This scan cannot be imported. Choose the correct document type or take a clearer photo.',
              ),
            ),
        ],
      ],
    );
  }

  String _label(String value) {
    final words = value.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    );
    return words[0].toUpperCase() + words.substring(1);
  }

  Widget _record(int index) {
    final result = _parsed!;
    if (index < result.duties.length) {
      final d = result.duties[index];
      return ListTile(
        title: Text(
          '${displayDate(d.date)} · ${_label(d.dutyType.name)} · Turn ${d.turnNumber ?? "—"}',
        ),
        subtitle: Text(
          '${d.driverName ?? (d.driverNumber == null ? "Driver" : "Driver ${d.driverNumber}")} · Payroll ${d.payrollNumber ?? "—"}\n'
          '${d.bookOn ?? "—"}–${d.bookOff ?? "—"}${d.remarks == null ? "" : "\n${d.remarks}"}',
        ),
        isThreeLine: true,
        trailing: _daily
            ? IconButton(
                tooltip: 'Correct record',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editRecord(index),
              )
            : null,
      );
    }
    index -= result.duties.length;
    if (index < result.jobCards.length) {
      final c = result.jobCards[index];
      return ListTile(
        title: Text(
          'Turn ${c.turnNumber} · ${c.dayCode} · ${c.planType.name.toUpperCase()}',
        ),
        subtitle: Text(
          '${displayDate(c.validFrom)}–${displayDate(c.validTo)}\n'
          '${c.bookOn}–${c.bookOff}',
        ),
        isThreeLine: true,
      );
    }
    final a = result.annualLeaveAllocations[index - result.jobCards.length];
    return ListTile(
      title: Text(
        '${a.driverNumber} ${a.surname} · Block ${a.blockNumber} · ${a.leaveYear}',
      ),
      subtitle: Text(
        a.periods
            .map(
              (p) =>
                  '${_label(p.type.name)}: ${displayDate(p.startDate)}–${displayDate(p.endDate)}',
            )
            .join('\n'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _effective;
    final needsDailyReview = parsed != null &&
        _daily &&
        ScanImportPolicy.unmatchedRows(parsed, _pages!).isNotEmpty;
    final visibleRecordCount = needsDailyReview
        ? 0
        : (parsed?.calculatedRecordCount ?? 0);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan and review')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _busy
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(value: _progress),
                            const SizedBox(height: 20),
                            Text(_progressMessage, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: 1 + visibleRecordCount,
                      itemBuilder: (_, index) => index == 0
                          ? Column(
                              children: [
                                if (_error != null) ...[
                                  Text(
                                    _error!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (_pages == null)
                                    FilledButton(
                                      onPressed: _read,
                                      child: const Text('Retry scan'),
                                    ),
                                ],
                                if (_pages != null) _header(),
                              ],
                            )
                          : _record(index - 1),
                    ),
            ),
            if (parsed != null && !parsed.canImport)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  parsed.warnings.any(_unreadable)
                    ? 'Import paused: some rows are unreadable. Check them above, then exclude those rows or add a corrected shift.'
                    : 'Import paused: check the warnings above.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (parsed != null && (parsed.warnings.any(_unreadable) || _excludeUnreadable))
              CheckboxListTile(
                value: _excludeUnreadable,
                onChanged: (value) => setState(() => _excludeUnreadable = value ?? false),
                title: const Text('Import reviewed records only'),
                subtitle: const Text('Exclude unreadable rows. Missing shifts will not be guessed.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(_busy ? 'Cancel scan' : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          _busy ||
                              _pages == null ||
                              _type == DocumentType.unknown
                          ? null
                          : parsed == null
                          ? () => _prepare(automatic: true)
                          : !parsed.canImport
                          ? null
                          : () => Navigator.pop(
                              context,
                              ReviewedDocument(_type,
                                ScanImportPolicy.allRowsRead(parsed, _pages!)
                                    ? parsed.copyWith(allRowsRead: true) : parsed,
                                _activation),
                            ),
                      child: Text(
                        parsed == null ? 'Check and apply' : 'Import records',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BaseRosterRowCorrection extends StatefulWidget {
  const _BaseRosterRowCorrection({
    required this.lineNumber,
    required this.pageNumber,
    required this.cells,
    required this.identity,
    required this.showAll,
  });

  final int lineNumber;
  final int pageNumber;
  final List<String> cells;
  final String identity;
  final bool showAll;

  @override
  State<_BaseRosterRowCorrection> createState() => _BaseRosterRowCorrectionState();
}

class _BaseRosterRowCorrectionState extends State<_BaseRosterRowCorrection> {
  static const _dayLabels = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];
  static final _duty = RegExp(
    r'^((?:[01]\d|2[0-3]):[0-5]\d) +((?:[01]\d|2[0-3]):[0-5]\d) +(?:\d{1,2}:[0-5]\d) +(?:\d{1,4}|Sp)$',
    caseSensitive: false,
  );

  final _form = GlobalKey<FormState>();
  late final List<String> _values = [...widget.cells, widget.identity];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Base Roster line ${widget.lineNumber}, page ${widget.pageNumber}'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showAll || widget.identity == '?')
              TextFormField(
                initialValue: widget.identity == '?' ? '' : widget.identity,
                decoration: const InputDecoration(labelText: 'Roster number'),
                keyboardType: TextInputType.number,
                onChanged: (value) => _values[8] = value.trim(),
                validator: (_) => RegExp(r'^\d{4}$').hasMatch(_values[8])
                    ? null
                    : 'Enter the four-digit roster number.',
              ),
            for (var day = 0; day < _dayLabels.length; day++)
              if (widget.showAll || widget.cells[day + 1] == '?')
                TextFormField(
                  initialValue: widget.cells[day + 1] == '?' ? '' : widget.cells[day + 1],
                  decoration: InputDecoration(
                    labelText: _dayLabels[day],
                    hintText: '06:00 14:45 08:45 201',
                    helperText: day == 0
                        ? 'Start, finish, hours, turn. Enter No Duty or leave blank for an empty cell.'
                        : 'Start, finish, hours, turn, or No Duty.',
                    helperMaxLines: 2,
                  ),
                  onChanged: (value) => _values[day + 1] = value.trim(),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (((day == 0 || widget.cells[day + 1].isEmpty) && text.isEmpty) ||
                        text.toLowerCase() == 'no duty' ||
                        _duty.hasMatch(text)) {
                      _values[day + 1] = text;
                      return null;
                    }
                    return 'Enter four values, or No Duty.';
                  },
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) Navigator.pop(context, _values);
          },
          child: const Text('Save correction'),
        ),
      ],
    );
  }
}
