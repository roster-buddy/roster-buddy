import 'duty.dart';
import 'roster_source.dart';

class DutyHistory {
  const DutyHistory({required this.date, this.versions = const []});

  final DateTime date;
  final List<Duty> versions;

  Duty? get current {
    if (versions.isEmpty) return null;

    final sorted = List<Duty>.from(versions)
      ..sort((a, b) => b.source.priority.compareTo(a.source.priority));

    return sorted.first;
  }
}
