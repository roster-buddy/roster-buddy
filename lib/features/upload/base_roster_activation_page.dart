import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'storage_service.dart';

class BaseRosterActivationPage extends StatefulWidget {
  const BaseRosterActivationPage({required this.fileName, super.key});

  final String fileName;

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
  final TextEditingController _swapPartnerController = TextEditingController();

  DateTime? _commencementDate;
  bool _hasMutualSwap = false;
  BaseRosterStartingLine _startingLine = BaseRosterStartingLine.mine;

  @override
  void initState() {
    super.initState();
    _loadSavedBaseRosterSetup();
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
            'base_roster_commencement_date, '
            'has_mutual_roster_swap, '
            'swap_partner_driver_number, '
            'base_roster_starts_with_line',
          )
          .eq('user_id', user.id)
          .maybeSingle();
    } catch (_) {
      profile = null;
    }

    final String commencementValue =
        (profile?['base_roster_commencement_date'] ??
                metadata['base_roster_commencement_date'] ??
                '')
            .toString()
            .trim();

    final DateTime? commencementDate = commencementValue.isEmpty
        ? null
        : DateTime.tryParse(commencementValue);

    final bool hasMutualSwap =
        profile?['has_mutual_roster_swap'] == true ||
        metadata['has_mutual_swap'] == true;

    final String swapPartner =
        (profile?['swap_partner_driver_number'] ??
                metadata['swap_partner_driver_number'] ??
                '')
            .toString()
            .trim();

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
      if (commencementDate != null) {
        _commencementDate = DateUtils.dateOnly(commencementDate);
      }

      _hasMutualSwap = hasMutualSwap;
      _swapPartnerController.text = hasMutualSwap ? swapPartner : '';
      _startingLine = hasMutualSwap && startsWithPartner
          ? BaseRosterStartingLine.partner
          : BaseRosterStartingLine.mine;
    });
  }

  @override
  void dispose() {
    _swapPartnerController.dispose();
    super.dispose();
  }

  DateTime _nextSunday() {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final int daysUntilSunday =
        (DateTime.sunday - today.weekday) % DateTime.daysPerWeek;

    return today.add(Duration(days: daysUntilSunday));
  }

  String _formatDate(DateTime date) {
    const List<String> weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    const List<String> months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${weekdays[date.weekday - 1]} '
        '${date.day} ${months[date.month - 1]} ${date.year}';
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
        swapPartnerDriverNumber: _hasMutualSwap
            ? _swapPartnerController.text.trim()
            : null,
        startingLine: _hasMutualSwap
            ? _startingLine
            : BaseRosterStartingLine.mine,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: navy,
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
                      color: railwayBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          color: railwayBlue,
                          size: 30,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Base Roster detected',
                                style: TextStyle(
                                  color: navy,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                widget.fileName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: textGrey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Commencement date',
                    style: TextStyle(
                      color: navy,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose the Sunday from which this roster becomes effective. Previous roster history will remain unchanged.',
                    style: TextStyle(color: textGrey, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      leading: const Icon(
                        Icons.calendar_month_outlined,
                        color: railwayBlue,
                      ),
                      title: Text(
                        _commencementDate == null
                            ? 'Select commencement Sunday'
                            : _formatDate(_commencementDate!),
                        style: const TextStyle(
                          color: navy,
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
                  Card(
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      title: const Text(
                        'Mutual permanent swap',
                        style: TextStyle(
                          color: navy,
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
                            _swapPartnerController.clear();
                            _startingLine = BaseRosterStartingLine.mine;
                          }
                        });
                      },
                    ),
                  ),
                  if (_hasMutualSwap) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _swapPartnerController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Swap partner Roster Code',
                        hintText: 'Enter their roster code',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (!_hasMutualSwap) {
                          return null;
                        }

                        if (value == null || value.trim().isEmpty) {
                          return 'Enter the swap partner roster code.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Which line applies on the commencement Sunday?',
                      style: TextStyle(
                        color: navy,
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
                        child: const Column(
                          children: [
                            RadioListTile<BaseRosterStartingLine>(
                              title: Text(
                                'My roster line',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                'The first week uses my normal roster line.',
                              ),
                              value: BaseRosterStartingLine.mine,
                            ),
                            Divider(height: 1),
                            RadioListTile<BaseRosterStartingLine>(
                              title: Text(
                                "Swap partner's roster line",
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
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
