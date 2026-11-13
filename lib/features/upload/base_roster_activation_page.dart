import '../../core/formatters/roster_date_format.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'storage_service.dart';

class BaseRosterActivationPage extends StatefulWidget {
  const BaseRosterActivationPage({required this.fileName, this.initial, super.key});

  final String fileName;
  final BaseRosterActivation? initial;

  @override
  State<BaseRosterActivationPage> createState() =>
      _BaseRosterActivationPageState();
}

class _BaseRosterActivationPageState extends State<BaseRosterActivationPage> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);
  static const Color textGrey = Color(0xFF52667A);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  int? _weekNumber;
  int? _swapWeekNumber;

  DateTime? _commencementDate;
  bool _hasMutualSwap = false;
  BaseRosterStartingLine _startingLine = BaseRosterStartingLine.mine;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) {
      _loadSavedBaseRosterSetup();
    } else {
      _commencementDate = initial.commencementDate;
      _weekNumber = initial.startWeekNumber;
      _swapWeekNumber = initial.swapPartnerWeekNumber;
      _hasMutualSwap = initial.hasMutualSwap;
      _startingLine = initial.startingLine;
    }
  }

  Future<void> _loadSavedBaseRosterSetup() async {
    final SupabaseClient supabase = Supabase.instance.client;
    final User? user = supabase.auth.currentUser;

    if (user == null) {
      return;
    }

    final Map<String, dynamic> metadata = user.userMetadata ?? {};

    Map<String, dynamic>? profile;

    try {
      profile = await supabase
          .from('driver_profiles')
          .select(
            'has_mutual_roster_swap, '
            'base_roster_starts_with_line',
          )
          .eq('user_id', user.id)
          .maybeSingle();
    } catch (_) {
      profile = null;
    }

    final bool hasMutualSwap =
        profile?['has_mutual_roster_swap'] == true ||
        metadata['has_mutual_swap'] == true;

    final String startingLine =
        (profile?['base_roster_starts_with_line'] ??
                metadata['mutual_swap_first_line'] ??
                '')
            .toString()
            .trim();

    final bool startsWithPartner =
        startingLine == 'partner' ||
        startingLine == 'swap_partner_line' ||
        startingLine == 'partner_line';

    if (!mounted) {
      return;
    }

    setState(() {
      if (_weekNumber != null || _swapWeekNumber != null) return;
      _hasMutualSwap = hasMutualSwap;
      _startingLine = hasMutualSwap && startsWithPartner
          ? BaseRosterStartingLine.partner
          : BaseRosterStartingLine.mine;
    });
  }

  DateTime _nextSunday() {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final int daysUntilSunday =
        (DateTime.sunday - today.weekday) % DateTime.daysPerWeek;

    return today.add(Duration(days: daysUntilSunday));
  }

  String _formatDate(DateTime date) {
    return displayDate(date);
  }

  Future<void> _selectCommencementDate() async {
    final DateTime initialDate = _commencementDate ?? _nextSunday();

    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      selectableDayPredicate: (date) => date.weekday == DateTime.sunday,
      helpText: 'Select commencement Sunday',
      fieldLabelText: 'Commencement Sunday',
      errorFormatText: 'Enter a valid date',
      errorInvalidText: 'The commencement date must be a Sunday',
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    setState(() {
      _commencementDate = DateUtils.dateOnly(selectedDate);
    });
  }

  void _activateRoster() {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_commencementDate == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Select the Sunday this Base Roster commences.'),
            behavior: SnackBarBehavior.floating,
          ),
        );

      return;
    }

    if (_commencementDate!.weekday != DateTime.sunday) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('A Base Roster must commence on a Sunday.'),
            behavior: SnackBarBehavior.floating,
          ),
        );

      return;
    }

    Navigator.of(context).pop(
      BaseRosterActivation(
        commencementDate: _commencementDate!,
        hasMutualSwap: _hasMutualSwap,
        startWeekNumber: _weekNumber,
        swapPartnerWeekNumber: _hasMutualSwap ? _swapWeekNumber : null,
        startingLine: _hasMutualSwap
            ? _startingLine
            : BaseRosterStartingLine.mine,
      ),
    );
  }

  Widget _weekField({
    required String label,
    required int? selected,
    required ValueChanged<int?> onChanged,
    bool partner = false,
  }) => DropdownButtonFormField<int>(
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    items: [
      for (var week = 1; week <= 54; week++)
        DropdownMenuItem(value: week, child: Text('Week $week')),
    ],
    onChanged: onChanged,
    validator: (value) {
      if (value == null) return 'Select a printed week number.';
      if (partner && value == _weekNumber) return 'Choose a different week.';
      return null;
    },
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color headingColor = isDark ? colors.onSurface : navy;
    final Color descriptionColor = isDark ? colors.onSurfaceVariant : textGrey;
    final Color iconColor = isDark ? colors.primary : railwayBlue;

    return Scaffold(
      backgroundColor: isDark ? theme.scaffoldBackgroundColor : background,
      appBar: AppBar(
        backgroundColor: isDark ? null : Colors.white,
        foregroundColor: isDark ? null : navy,
        elevation: 0,
        title: const Text(
          'Activate Base Roster',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colors.surfaceContainerHigh
                          : railwayBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          color: iconColor,
                          size: 30,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Base Roster detected',
                                style: TextStyle(
                                  color: headingColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                widget.fileName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: descriptionColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Commencement date',
                    style: TextStyle(
                      color: headingColor,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose the first Sunday and the week numbers printed in the first column.',
                    style: TextStyle(color: descriptionColor, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      leading: Icon(
                        Icons.calendar_month_outlined,
                        color: iconColor,
                      ),
                      title: Text(
                        _commencementDate == null
                            ? 'Select commencement Sunday'
                            : _formatDate(_commencementDate!),
                        style: TextStyle(
                          color: headingColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Only Sundays can be selected'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _selectCommencementDate,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _weekField(
                    label: 'Your printed week number',
                    selected: _weekNumber,
                    onChanged: (value) => setState(() => _weekNumber = value),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      title: Text(
                        'Mutual permanent swap',
                        style: TextStyle(
                          color: headingColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Enable this when alternating roster lines with another driver.',
                        ),
                      ),
                      value: _hasMutualSwap,
                      onChanged: (value) {
                        setState(() {
                          _hasMutualSwap = value;

                          if (!value) {
                            _swapWeekNumber = null;
                            _startingLine = BaseRosterStartingLine.mine;
                          }
                        });
                      },
                    ),
                  ),
                  if (_hasMutualSwap) ...[
                    const SizedBox(height: 14),
                    _weekField(
                      label: 'Swap partner’s printed week number',
                      selected: _swapWeekNumber,
                      onChanged: (value) => setState(() => _swapWeekNumber = value),
                      partner: true,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Which line applies on the commencement Sunday?',
                      style: TextStyle(
                        color: headingColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: RadioGroup<BaseRosterStartingLine>(
                        groupValue: _startingLine,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _startingLine = value;
                          });
                        },
                        child: Column(
                          children: [
                            RadioListTile<BaseRosterStartingLine>(
                              title: Text(
                                _weekNumber == null ? 'My week' : 'My week $_weekNumber',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: const Text(
                                'The first week uses my normal roster line.',
                              ),
                              value: BaseRosterStartingLine.mine,
                            ),
                            const Divider(height: 1),
                            RadioListTile<BaseRosterStartingLine>(
                              title: Text(
                                _swapWeekNumber == null ? 'Partner’s week' : 'Partner’s week $_swapWeekNumber',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: const Text(
                                "The first week uses the swap partner's line.",
                              ),
                              value: BaseRosterStartingLine.partner,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _activateRoster,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Continue and upload',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
