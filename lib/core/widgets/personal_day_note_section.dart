import 'package:flutter/material.dart';

import '../services/personal_day_note_service.dart';

class PersonalDayNoteSection extends StatefulWidget {
  const PersonalDayNoteSection({required this.date, this.onChanged, super.key});
  final DateTime date;
  final VoidCallback? onChanged;
  @override
  State<PersonalDayNoteSection> createState() => _PersonalDayNoteSectionState();
}

class _PersonalDayNoteSectionState extends State<PersonalDayNoteSection> {
  final PersonalDayNoteService _service = PersonalDayNoteService();
  String? _note;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final note = await _service.getNote(widget.date);
      if (mounted) setState(() => _note = note);
    } catch (_) {
      // Keep the day details usable if notes are temporarily unavailable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final controller = TextEditingController(text: _note ?? '');
    final String? result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_note == null ? 'Add plans or note' : 'Edit plans or note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 7,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'For example: Theatre at 19:30',
            labelText: 'Personal note',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    try {
      await _service.saveNote(widget.date, result);
      final saved = result.trim().isEmpty ? null : result.trim();
      if (!mounted) return;
      setState(() => _note = saved);
      widget.onChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved == null ? 'Note removed' : 'Note saved')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The note could not be saved. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    try {
      await _service.deleteNote(widget.date);
      if (!mounted) return;
      setState(() => _note = null);
      widget.onChanged?.call();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note removed')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The note could not be removed. Try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color red = Theme.of(context).colorScheme.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _note == null ? Icons.event_note_outlined : Icons.circle,
                    color: _note == null ? null : red,
                    size: _note == null ? 26 : 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _note == null ? 'Plans & notes' : 'Your plans',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(_note ?? 'Add a private note for this date.'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _edit,
                              icon: Icon(
                                _note == null ? Icons.add : Icons.edit,
                              ),
                              label: Text(
                                _note == null ? 'Add note' : 'Edit note',
                              ),
                            ),
                            if (_note != null)
                              TextButton.icon(
                                onPressed: _delete,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Remove'),
                              ),
                          ],
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
