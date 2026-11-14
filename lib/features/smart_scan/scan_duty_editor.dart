import 'package:flutter/material.dart';
import '../../core/models/duty.dart';
import '../../core/parser/parser_utils.dart';
import '../../core/models/duty_type.dart';
import '../../core/models/roster_source.dart';
import '../../core/formatters/roster_date_format.dart';

class ScanDutyEditor extends StatefulWidget {
  const ScanDutyEditor({
    required this.source,
    this.initial,
    this.date,
    this.payroll,
    this.scannedRow,
    super.key,
  });
  final RosterSource source;
  final Duty? initial;
  final DateTime? date;
  final String? payroll;
  final String? scannedRow;
  @override
  State<ScanDutyEditor> createState() => _ScanDutyEditorState();
}

class _ScanDutyEditorState extends State<ScanDutyEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _date, _pay, _turn, _on, _off;
  late DutyType _type;
  String? _availabilityCode;
  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _date = TextEditingController(
      text: (d?.date ?? widget.date) == null
          ? ''
          : displayDate((d?.date ?? widget.date)!),
    );
    _pay = TextEditingController(
      text: d?.payrollNumber ?? widget.payroll ?? '',
    );
    _turn = TextEditingController(text: d?.turnNumber ?? '');
    _on = TextEditingController(text: d?.bookOn ?? '');
    _off = TextEditingController(text: d?.bookOff ?? '');
    _type = d?.dutyType ?? DutyType.working;
    _availabilityCode = ['ND', 'NDNA'].contains(d?.amendmentCode)
        ? d?.amendmentCode : null;
  }

  @override
  void dispose() {
    for (final c in [_date, _pay, _turn, _on, _off]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? _readDate() {
    final m = RegExp(
      r'^(\d{2})/(\d{2})/(\d{4})$',
    ).firstMatch(_date.text.trim());
    if (m == null) return null;
    final d = DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    return displayDate(d) == _date.text.trim() ? d : null;
  }

  String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

  String? _clock(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (RegExp(r'^(?:[01]\d|2[0-3]):?[0-5]\d$').hasMatch(text)) return null;
    return 'Use HH:mm or HHmm';
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final start = ParserUtils.normaliseTime(_on.text);
    final end = ParserUtils.normaliseTime(_off.text);
    final minutes = start == null || end == null
        ? null
        : ParserUtils.calculateDutyMinutes(start, end);
    Navigator.pop(
      context,
      Duty(
        date: _readDate()!,
        source: widget.source,
        dutyType: _type,
        payrollNumber: _pay.text.trim(),
        driverName: widget.initial?.driverName,
        driverNumber: widget.initial?.driverNumber,
        depot: widget.initial?.depot,
        turnNumber: _optional(_turn.text),
        bookOn: start,
        bookOff: end,
        rosteredMinutes: minutes,
        amendmentCode: _availabilityCode ?? (_type == DutyType.annualLeave
            ? 'ALD'
            : (_type == widget.initial?.dutyType ? widget.initial?.amendmentCode : null)),
        remarks: _availabilityCode == 'ND'
            ? 'No shift allocated — available to work'
            : _availabilityCode == 'NDNA'
            ? 'No shift allocated — not available to work'
            : 'Checked against the document',
        rawText: widget.initial?.rawText ?? widget.scannedRow,
        pageNumber: widget.initial?.pageNumber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null && widget.scannedRow == null
          ? 'Add missing shift'
          : 'Correct record',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.scannedRow case final String row) Text(row),
            TextFormField(
              controller: _date,
              decoration: const InputDecoration(labelText: 'Date (dd/mm/yyyy)'),
              validator: (_) =>
                  _readDate() == null ? 'Enter a valid date' : null,
            ),
            TextFormField(
              controller: _pay,
              decoration: const InputDecoration(labelText: 'Payroll number'),
              validator: (v) => RegExp(r'^\d{4,8}$').hasMatch(v ?? '')
                  ? null
                  : 'Enter the payroll number',
            ),
            DropdownButtonFormField<String>(
              initialValue: _availabilityCode ?? _type.name,
              decoration: const InputDecoration(labelText: 'Day type'),
              items:
                  [
                        DutyType.working,
                        DutyType.training,
                        DutyType.medical,
                        DutyType.restDay,
                        DutyType.annualLeave,
                        DutyType.sick,
                        DutyType.publicHoliday,
                        DutyType.unavailable,
                        DutyType.unknown,
                      ]
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.name,
                          child: Text(switch (t) {
                            DutyType.restDay => 'Rest day',
                            DutyType.annualLeave => 'Annual leave',
                            DutyType.publicHoliday => 'Public holiday',
                            _ => t.name,
                          }),
                        ),
                      )
                      .toList()
                      ..addAll(const [
                        DropdownMenuItem(value: 'ND', child: Text('ND — available, no shift allocated')),
                        DropdownMenuItem(value: 'NDNA', child: Text('NDNA — unavailable, no shift allocated')),
                      ]),
              validator: (v) =>
                  v == DutyType.unknown.name ? 'Choose a day type' : null,
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                  _availabilityCode = ['ND', 'NDNA'].contains(v) ? v : null;
                  _type = v == 'ND' ? DutyType.restDay
                      : v == 'NDNA' ? DutyType.unavailable
                      : DutyType.values.byName(v);
                  });
                }
              },
            ),
            TextFormField(
              controller: _turn,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Turn'),
            ),
            TextFormField(
              controller: _on,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(labelText: 'Start (optional)'),
              validator: _clock,
            ),
            TextFormField(
              controller: _off,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(labelText: 'End (optional)'),
              validator: _clock,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Use these values')),
    ],
  );
}
