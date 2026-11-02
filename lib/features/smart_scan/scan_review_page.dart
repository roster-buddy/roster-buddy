import '../../core/services/printed_roster_identity.dart';
import 'package:flutter/material.dart';

import '../../core/formatters/roster_date_format.dart';
import '../../core/models/document_type.dart';
import '../../core/models/parse_result.dart';
import '../../core/models/parse_warning.dart';
import '../../core/models/duty.dart';
import '../../core/models/roster_source.dart';
import 'scan_duty_editor.dart';
import '../../core/parser/document_classifier.dart';
import '../upload/base_roster_activation_page.dart';
import '../upload/document_processing_service.dart';
import '../upload/storage_service.dart';
import '../upload/upload_service.dart';
import 'smart_scan_engine.dart';
import 'smart_scan_page_text_reconstructor.dart';
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

  Future<void> _editRecord([int? index]) async {
    final parsed = _parsed!;
    final source = switch (_type) {
      DocumentType.tenDayAmendment => RosterSource.tenDay,
      DocumentType.fortyEightHourAmendment => RosterSource.fortyEightHour,
      _ => RosterSource.sevenDay,
    };
    final duty = await showDialog<Duty>(
      context: context,
      builder: (_) => ScanDutyEditor(
        source: source,
        initial: index == null ? null : parsed.duties[index],
        date: parsed.duties.isEmpty ? null : parsed.duties.first.date,
        payroll: parsed.payrollNumber,
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
      _excludeUnreadable = false;
      _progress = null;
    });
    try {
      final List<SmartScanResult> pages;
      if (widget.readDocument != null) {
        pages = await widget.readDocument!(_report);
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
      final type = const DocumentClassifier().classify(
        SmartScanPageTextReconstructor.reconstructPages(pages),
      );
      setState(() {
        _pages = pages;
        _type = type;
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

  Future<void> _prepare() async {
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

  Widget _header() {
    final parsed = _effective;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.upload.fileName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Nothing is uploaded or added to your calendar until you confirm the import.',
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
            'The heading was unclear. Choose the document type above.',
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _pages!
                    .asMap()
                    .entries
                    .map(
                      (entry) =>
                          'Page ${entry.key + 1}\n${entry.value.fullText}',
                    )
                    .join('\n\n'),
              ),
            ),
          ],
        ),
        if (parsed != null) ...[
          const SizedBox(height: 12),
          Text(
            '${parsed.calculatedRecordCount} records to review',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (parsed.ownRecordCount != null)
            Text('${parsed.ownRecordCount} records match your calendar.'),
          if (parsed.ownRecordCount == 0)
            const Text(
              'No rows matched your profile. This import will not update your own shifts.',
            ),
          const Text(
            'Check these records against your document. Shared sheets include records for other drivers; each calendar uses its matching driver or payroll number.',
          ),
          for (final warning in parsed.warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(warning.message),
            ),
          if (_daily) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _editRecord(),
              icon: const Icon(Icons.add),
              label: const Text('Add missing shift'),
            ),
          ],
          if (parsed.warnings.any(_unreadable) || _excludeUnreadable)
            CheckboxListTile(
              value: _excludeUnreadable,
              onChanged: (value) =>
                  setState(() => _excludeUnreadable = value ?? false),
              title: const Text('Exclude unreadable rows'),
              subtitle: const Text(
                'Only the reviewed records below will be imported. Missing rows are not added or guessed.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          if (!parsed.canImport)
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
          'Driver ${d.driverNumber ?? "—"} · Payroll ${d.payrollNumber ?? "—"}\n'
          '${d.bookOn ?? "—"}–${d.bookOff ?? "—"}${d.remarks == null ? "" : "\n${d.remarks}"}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Correct record',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _editRecord(index),
        ),
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
                      itemCount: 1 + (parsed?.calculatedRecordCount ?? 0),
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
                          ? _prepare
                          : !parsed.canImport
                          ? null
                          : () => Navigator.pop(
                              context,
                              ReviewedDocument(_type, parsed, _activation),
                            ),
                      child: Text(
                        parsed == null ? 'Review records' : 'Import records',
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
