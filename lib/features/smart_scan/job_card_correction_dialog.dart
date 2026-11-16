import 'package:flutter/material.dart';
import '../../core/models/job_card.dart';
import '../../core/parser/parser_utils.dart';

class JobCardCorrectionDialog extends StatefulWidget {
  const JobCardCorrectionDialog({super.key, required this.pageNumber, required this.rawText});
  final int pageNumber;
  final String rawText;
  @override
  State<JobCardCorrectionDialog> createState() => _JobCardCorrectionDialogState();
}

class _JobCardCorrectionDialogState extends State<JobCardCorrectionDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController turn, day, from, to, bookOn, bookOff;
  @override
  void initState() {
    super.initState();
    final raw = widget.rawText;
    final code = RegExp(r'W[O0Q]\s*(\d{2,4})', caseSensitive: false).firstMatch(raw)?.group(1) ?? '';
    final days = RegExp(r'\b(?:T[O0]|W[O0]|TH[O0]|SX|M[O0]|F[O0])\b', caseSensitive: false).firstMatch(raw)?.group(0) ?? '';
    final dateMatches = RegExp(r'\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b').allMatches(raw).map((m) => m.group(0)!).toList();
    turn = TextEditingController(text: code);
    day = TextEditingController(text: days.toUpperCase().replaceAll('0', 'O'));
    from = TextEditingController(text: dateMatches.isEmpty ? '' : dateMatches.first);
    to = TextEditingController(text: dateMatches.length > 1 ? dateMatches[1] : from.text);
    bookOn = TextEditingController();
    bookOff = TextEditingController();
  }
  @override
  void dispose() {
    for (final c in [turn, day, from, to, bookOn, bookOff]) { c.dispose(); }
    super.dispose();
  }
  String? requiredTurn(String? v) => RegExp(r'^\d{2,4}$').hasMatch(v?.trim() ?? '') ? null : 'Enter turn number';
  String? requiredDay(String? v) => RegExp(r'^[A-Za-z]{1,6}$').hasMatch(v?.trim() ?? '') ? null : 'Enter a day code';
  String? requiredDate(String? v) => ParserUtils.parseDate(v) == null ? 'Use dd/mm/yyyy' : null;
  String? requiredTime(String? v) => ParserUtils.normaliseTime(v) == null ? 'Use HH:mm' : null;
  void save() {
    if (!form.currentState!.validate()) return;
    final start = ParserUtils.parseDate(from.text)!;
    final end = ParserUtils.parseDate(to.text)!;
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date is before start date')));
      return;
    }
    final on = ParserUtils.normaliseTime(bookOn.text)!;
    final off = ParserUtils.normaliseTime(bookOff.text)!;
    final rawUpper = widget.rawText.toUpperCase();
    final plan = rawUpper.contains('VSTP') ? JobCardPlanType.vstp :
        rawUpper.contains('LTP') ? JobCardPlanType.ltp : JobCardPlanType.stp;
    Navigator.pop(context, JobCard(
      turnNumber: turn.text.trim(),
      originalTurnCode: 'WO${turn.text.trim()}',
      dayCode: day.text.trim().toUpperCase().replaceAll('0', 'O'),
      planType: plan, validFrom: start, validTo: end, bookOn: on, bookOff: off,
      rosteredMinutes: ParserUtils.calculateDutyMinutes(on, off),
      rawText: widget.rawText, pageNumber: widget.pageNumber,
    ));
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Correct Job Card — page ${widget.pageNumber}'),
    content: SingleChildScrollView(child: Form(key: form, child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        const Text('Check the card against the original scan before saving.'),
        TextFormField(controller: turn, decoration: const InputDecoration(labelText: 'Turn number'), validator: requiredTurn),
        TextFormField(controller: day, decoration: const InputDecoration(labelText: 'Day code (TO, SX, etc.)'), validator: requiredDay),
        TextFormField(controller: from, decoration: const InputDecoration(labelText: 'Valid from (dd/mm/yyyy)'), validator: requiredDate),
        TextFormField(controller: to, decoration: const InputDecoration(labelText: 'Valid to (dd/mm/yyyy)'), validator: requiredDate),
        TextFormField(controller: bookOn, decoration: const InputDecoration(labelText: 'Book on (HH:mm)'), validator: requiredTime),
        TextFormField(controller: bookOff, decoration: const InputDecoration(labelText: 'Book off (HH:mm)'), validator: requiredTime),
      ],
    ))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: save, child: const Text('Use corrected card')),
    ],
  );
}
