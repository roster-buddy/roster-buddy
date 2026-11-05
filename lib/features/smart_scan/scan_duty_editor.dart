import 'package:flutter/material.dart';
import '../../core/models/duty.dart';
import '../../core/models/duty_type.dart';
import '../../core/models/roster_source.dart';
import '../../core/formatters/roster_date_format.dart';

class ScanDutyEditor extends StatefulWidget {
  const ScanDutyEditor({
    required this.source,
    this.initial,
    this.date,
    this.payroll,
    super.key,
  });
  final RosterSource source;
  final Duty? initial;
  final DateTime? date;
  final String? payroll;
  @override
  State<ScanDutyEditor> createState() => _ScanDutyEditorState();
}

class _ScanDutyEditorState extends State<ScanDutyEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _date, _pay, _turn, _on, _off;
  late DutyType _type;
  String? _availabilityCode;
  bool get _needsTimes =>
      _type == DutyType.working ||
      _type == DutyType.training ||
      _type == DutyType.medical;
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

  String? _clock(String? value) =>
      RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value ?? '')
      ? null
      : 'Use 24-hour HH:mm';
  void _save() {
    if (!_form.currentState!.validate()) return;
    int? minutes;
    if (_needsTimes) {
      final a = _on.text.split(':').map(int.parse).toList();
      final b = _off.text.split(':').map(int.parse).toList();
      minutes = (b[0] * 60 + b[1] - (a[0] * 60 + a[1]) + 1440) % 1440;
    }
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
        turnNumber: _needsTimes && _turn.text.trim().isNotEmpty
            ? _turn.text.trim()
            : null,
        bookOn: _needsTimes ? _on.text.trim() : null,
        bookOff: _needsTimes ? _off.text.trim() : null,
        rosteredMinutes: minutes,
        amendmentCode: _availabilityCode ?? (_type == DutyType.annualLeave
            ? 'ALD'
            : (_type == widget.initial?.dutyType ? widget.initial?.amendmentCode : null)),
        remarks: _availabilityCode == 'ND'
            ? 'No shift allocated — available to work'
            : _availabilityCode == 'NDNA'
            ? 'No shift allocated — not available to work'
            : 'Checked against the document',
        rawText: widget.initial?.rawText,
        pageNumber: widget.initial?.pageNumber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Add missing shift' : 'Correct record',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the values printed on the roster. Nothing changes until you confirm the import.',
            ),
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
                if (v != null) setState(() {
                  _availabilityCode = ['ND', 'NDNA'].contains(v) ? v : null;
                  _type = v == 'ND' ? DutyType.restDay
                      : v == 'NDNA' ? DutyType.unavailable
                      : DutyType.values.byName(v);
                });
              },
            ),
            if (_needsTimes) ...[
              TextFormField(
                controller: _turn,
                decoration: const InputDecoration(
                  labelText: 'Turn number (optional)',
                ),
                validator: (v) =>
                    (v ?? '').isEmpty || RegExp(r'^\d{2,4}$').hasMatch(v!)
                    ? null
                    : 'Use the numeric turn',
              ),
              TextFormField(
                controller: _on,
                decoration: const InputDecoration(labelText: 'Book on (HH:mm)'),
                validator: _clock,
              ),
              TextFormField(
                controller: _off,
                decoration: const InputDecoration(
                  labelText: 'Book off (HH:mm)',
                ),
                validator: _clock,
              ),
            ],
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
