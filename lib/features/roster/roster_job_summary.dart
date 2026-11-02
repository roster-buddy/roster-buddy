import 'package:flutter/material.dart';
import '../../core/models/duty.dart';
import '../../core/models/duty_type.dart';

/// Compact start, finish and turn, shared by roster calendar previews.
class RosterJobSummary extends StatelessWidget {
  const RosterJobSummary({
    required this.duty,
    required this.foreground,
    this.fontSize = 9,
    this.showTurn = true,
    super.key,
  });
  final Duty duty;
  final Color foreground;
  final double fontSize;
  final bool showTurn;

  static bool appliesTo(Duty? duty) =>
      duty != null &&
      duty.dutyType.countsAsWorking &&
      duty.remarks?.contains('awaiting allocation') != true &&
      [duty.bookOn, duty.bookOff, duty.turnNumber]
          .any((value) => value?.trim().isNotEmpty == true);

  String _time(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? '—' : text.replaceAll(':', '');
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final value in [
        _time(duty.bookOn),
        _time(duty.bookOff),
        if (showTurn) duty.turnNumber?.trim().isNotEmpty == true ? duty.turnNumber!.trim() : '—',
      ])
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: foreground, fontSize: fontSize, fontWeight: FontWeight.w800, height: 1.25),
        ),
    ],
  );
}
