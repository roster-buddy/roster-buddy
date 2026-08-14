import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/annual_leave_block_service.dart';
import '../../core/services/annual_leave_service.dart';
import 'home_screen.dart';

class InitialSetupScreen extends StatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);
  static const Color textGrey = Color(0xFF52667A);
  static const Color leaveRed = Color(0xFFC62828);

  static const int _stepCount = 5;

  final AnnualLeaveService _annualLeaveService = AnnualLeaveService();
  final AnnualLeaveBlockService _annualLeaveBlockService =
      AnnualLeaveBlockService();

  final GlobalKey<FormState> _driverFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _rosterFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _leaveFormKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _depotController = TextEditingController();
  final TextEditingController _driverNumberController = TextEditingController();
  final TextEditingController _rosterNumberController = TextEditingController();
  final TextEditingController _payrollNumberController =
      TextEditingController();
  final TextEditingController _swapPartnerController = TextEditingController();
  final TextEditingController _floatingBalanceController =
      TextEditingController(text: '14');

  int _step = 0;
  bool _saving = false;

  DateTime? _baseRosterCommencementDate;
  bool _hasMutualRosterSwap = false;
  String _baseRosterStartingLine = 'mine';

  int? _blockWeekIndex;
  final List<DateTime> _confirmedFloatingLeaveDates = <DateTime>[];

  bool _permanentlyUnavailableSundays = false;

  int get _currentLeaveYear => DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadExistingMetadata();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _depotController.dispose();
    _driverNumberController.dispose();
    _rosterNumberController.dispose();
    _payrollNumberController.dispose();
    _swapPartnerController.dispose();
    _floatingBalanceController.dispose();
    super.dispose();
  }

  void _loadExistingMetadata() {
    final User? user = Supabase.instance.client.auth.currentUser;
    final Map<String, dynamic> metadata =
        user?.userMetadata ?? <String, dynamic>{};

    _nameController.text = (metadata['full_name'] ?? '').toString();
    _depotController.text = (metadata['depot'] ?? '').toString();
    _driverNumberController.text = (metadata['driver_number'] ?? '').toString();
    _rosterNumberController.text =
        (metadata['roster_number'] ?? metadata['driver_number'] ?? '')
            .toString();
    _payrollNumberController.text = (metadata['payroll_number'] ?? '')
        .toString();

    final String existingPartner =
        (metadata['swap_partner_roster_number'] ??
                metadata['swap_partner_driver_number'] ??
                '')
            .toString()
            .trim();

    if (existingPartner.isNotEmpty) {
      _hasMutualRosterSwap = true;
      _swapPartnerController.text = existingPartner;
    }
  }

  String? _requiredText(String? value, String label) {
    if ((value ?? '').trim().isEmpty) {
      return 'Enter your $label';
    }

    return null;
  }

  String? _requiredNumber(String? value, String label) {
    final String cleaned = (value ?? '').trim();

    if (cleaned.isEmpty) {
      return 'Enter your $label';
    }

    if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) {
      return '$label must contain numbers only';
    }

    return null;
  }

  String? _optionalPartnerNumber(String? value) {
    if (!_hasMutualRosterSwap) {
      return null;
    }

    return _requiredNumber(value, 'swap partner roster code');
  }

  String? _floatingBalanceValidator(String? value) {
    final int? balance = int.tryParse((value ?? '').trim());

    if (balance == null) {
      return 'Enter your remaining floating leave days';
    }

    if (balance < 0) {
      return 'Floating leave balance cannot be negative';
    }

    return null;
  }

  void _goBack() {
    if (_saving || _step == 0) {
      return;
    }

    setState(() {
      _step -= 1;
    });
  }

  void _continueFromDriverDetails() {
    FocusScope.of(context).unfocus();

    if (!_driverFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _step = 1;
    });
  }

  void _continueFromRosterSetup() {
    FocusScope.of(context).unfocus();

    if (!_rosterFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _step = 2;
    });
  }

  void _continueFromAnnualLeave() {
    FocusScope.of(context).unfocus();

    if (!_leaveFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _step = 3;
    });
  }

  void _continueFromWorkPreferences() {
    setState(() {
      _step = 4;
    });
  }

  Future<void> _selectBaseRosterCommencementDate() async {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final int daysUntilSunday =
        (DateTime.sunday - today.weekday) % DateTime.daysPerWeek;

    final DateTime initial =
        _baseRosterCommencementDate ??
        today.add(Duration(days: daysUntilSunday));

    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      selectableDayPredicate: (DateTime date) =>
          date.weekday == DateTime.sunday,
      helpText: 'Select commencement Sunday',
      fieldLabelText: 'Commencement Sunday',
      errorInvalidText: 'The commencement date must be a Sunday',
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _baseRosterCommencementDate = DateUtils.dateOnly(selected);
    });
  }

  Future<void> _addConfirmedFloatingLeaveDate() async {
    final DateTime today = DateUtils.dateOnly(DateTime.now());

    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(today.year, 1, 1),
      lastDate: DateTime(today.year + 2, 12, 31),
      selectableDayPredicate: (DateTime date) =>
          date.weekday != DateTime.sunday,
      helpText: 'Confirmed floating annual leave',
      fieldLabelText: 'Annual leave date',
    );

    if (selected == null || !mounted) {
      return;
    }

    final DateTime dateOnly = DateUtils.dateOnly(selected);

    final bool alreadyAdded = _confirmedFloatingLeaveDates.any(
      (DateTime date) => DateUtils.isSameDay(date, dateOnly),
    );

    if (alreadyAdded) {
      _showMessage('That annual leave date has already been added.');
      return;
    }

    setState(() {
      _confirmedFloatingLeaveDates.add(dateOnly);
      _confirmedFloatingLeaveDates.sort();
    });
  }

  String _formatDate(DateTime date) {
    const List<String> weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    const List<String> months = <String>[
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

  String _databaseDate(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  Future<void> _recordConfirmedFloatingLeave({
    required User user,
    required DateTime date,
  }) async {
    final SupabaseClient supabase = Supabase.instance.client;

    final Map<String, dynamic>? existing = await supabase
        .from('annual_leave_requests')
        .select('id, status')
        .eq('user_id', user.id)
        .eq('leave_date', _databaseDate(date))
        .eq('request_type', 'floating')
        .maybeSingle();

    if (existing != null) {
      final String status = (existing['status'] ?? '').toString();

      if (status == 'granted') {
        return;
      }

      if (status == 'requested' || status == 'abeyance') {
        await _annualLeaveService.markGranted(
          requestId: existing['id'].toString(),
        );
        return;
      }
    }

    final request = await _annualLeaveService.requestFloatingLeave(
      date: date,
      notes: 'Added during Initial Setup - already confirmed',
    );

    await _annualLeaveService.markGranted(requestId: request.id);
  }

  Future<void> _finishSetup() async {
    final SupabaseClient supabase = Supabase.instance.client;
    final User? user = supabase.auth.currentUser;

    if (user == null) {
      _showMessage('You must be signed in to complete setup.', isError: true);
      return;
    }

    final int? enteredRemainingBalance = int.tryParse(
      _floatingBalanceController.text.trim(),
    );

    if (enteredRemainingBalance == null || enteredRemainingBalance < 0) {
      setState(() {
        _step = 2;
      });

      _showMessage('Check your floating annual leave balance.', isError: true);
      return;
    }

    final String displayName = _nameController.text.trim();
    final String depot = _depotController.text.trim();
    final String driverNumber = _driverNumberController.text.trim();
    final String rosterNumber = _rosterNumberController.text.trim();
    final String payrollNumber = _payrollNumberController.text.trim();

    setState(() {
      _saving = true;
    });

    try {
      // --------------------------------------------------------
      // Profile
      // setup_completed remains false until every setup item has
      // been saved successfully.
      // --------------------------------------------------------

      await supabase.from('driver_profiles').upsert(<String, dynamic>{
        'user_id': user.id,
        'display_name': displayName,
        'depot': depot,
        'driver_number': driverNumber,
        'roster_number': rosterNumber,
        'payroll_number': payrollNumber,
        'permanently_unavailable_sundays': _permanentlyUnavailableSundays,
        'base_roster_commencement_date': _baseRosterCommencementDate == null
            ? null
            : _databaseDate(_baseRosterCommencementDate!),
        'has_mutual_roster_swap': _hasMutualRosterSwap,
        'swap_partner_roster_number': _hasMutualRosterSwap
            ? _swapPartnerController.text.trim()
            : null,
        'base_roster_starts_with_line': _hasMutualRosterSwap
            ? _baseRosterStartingLine
            : 'mine',
        'setup_completed': false,
      }, onConflict: 'user_id');

      // --------------------------------------------------------
      // Account metadata
      // --------------------------------------------------------

      await supabase.auth.updateUser(
        UserAttributes(
          data: <String, dynamic>{
            'full_name': displayName,
            'depot': depot,
            'driver_number': driverNumber,
            'roster_number': rosterNumber,
            'payroll_number': payrollNumber,
            'swap_partner_roster_number': _hasMutualRosterSwap
                ? _swapPartnerController.text.trim()
                : null,
          },
        ),
      );

      // --------------------------------------------------------
      // Current block-leave cycle
      // --------------------------------------------------------

      if (_blockWeekIndex != null) {
        await _annualLeaveBlockService.saveCycleForYear(
          leaveYear: _currentLeaveYear,
          weekIndex: _blockWeekIndex!,
          source: 'manual',
        );
      }

      // --------------------------------------------------------
      // Floating annual leave balance
      //
      // User enters the number of days they genuinely have left.
      // Confirmed dates added below become committed days, so current-year
      // confirmed dates are added to the internal starting figure. This
      // ensures the final displayed remaining balance stays exactly equal
      // to the number entered by the user.
      // --------------------------------------------------------

      final int currentYearConfirmedCount = _confirmedFloatingLeaveDates
          .where((DateTime date) => date.year == _currentLeaveYear)
          .length;

      await _annualLeaveService.saveBalanceSetup(
        leaveYear: _currentLeaveYear,
        entitlementDays: 14,
        startingBalanceDays:
            enteredRemainingBalance + currentYearConfirmedCount,
        bonusDays: 0,
        carryOverDays: 0,
        lieuDays: 0,
      );

      // --------------------------------------------------------
      // Already-confirmed floating annual leave
      // --------------------------------------------------------

      for (final DateTime date in _confirmedFloatingLeaveDates) {
        await _recordConfirmedFloatingLeave(user: user, date: date);
      }

      // --------------------------------------------------------
      // Setup is only complete after every section succeeds.
      // --------------------------------------------------------

      await supabase
          .from('driver_profiles')
          .update(<String, dynamic>{'setup_completed': true})
          .eq('user_id', user.id);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        (Route<dynamic> route) => false,
      );
    } on AnnualLeaveException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message, isError: true);
    } on AnnualLeaveBlockException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message, isError: true);
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }

      if (error.code == '23505') {
        _showMessage(
          'One of those work identifiers is already linked to another '
          'Roster Buddy account.',
          isError: true,
        );
      } else {
        _showMessage(
          'Roster Buddy could not save your setup: ${error.message}',
          isError: true,
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Roster Buddy could not complete setup. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? leaveRed : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _progressHeader() {
    const List<String> labels = <String>[
      'Driver',
      'Roster',
      'Leave',
      'Preferences',
      'Review',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step ${_step + 1} of $_stepCount • ${labels[_step]}',
          style: const TextStyle(
            color: railwayBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (_step + 1) / _stepCount,
          minHeight: 7,
          borderRadius: BorderRadius.circular(20),
        ),
      ],
    );
  }

  Widget _pageHeading(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: navy,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(description, style: const TextStyle(color: textGrey, height: 1.4)),
      ],
    );
  }

  Widget _backAndContinue({
    required VoidCallback onContinue,
    String continueLabel = 'Continue',
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : _goBack,
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _saving ? null : onContinue,
            style: FilledButton.styleFrom(
              backgroundColor: railwayBlue,
              foregroundColor: Colors.white,
            ),
            child: Text(
              continueLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _driverDetailsStep() {
    return Form(
      key: _driverFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageHeading(
            'Driver details',
            'These identifiers allow Smart Scan to match you correctly '
                'across Base Rosters, amendments and Annual Leave Rosters.',
          ),
          const SizedBox(height: 26),
          TextFormField(
            controller: _nameController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            validator: (String? value) => _requiredText(value, 'full name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _depotController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Depot',
              prefixIcon: Icon(Icons.location_on_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (String? value) => _requiredText(value, 'depot'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _driverNumberController,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Driver number',
              helperText: 'Used to match you on Annual Leave Rosters.',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (String? value) =>
                _requiredNumber(value, 'driver / roster code'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _rosterNumberController,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Roster number',
              helperText: 'Used to find your line on the Base Roster.',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (String? value) =>
                _requiredNumber(value, 'roster number'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _payrollNumberController,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Payroll number',
              helperText:
                  'Used for 10-Day, 7-Day and 48-Hour amendment sheets.',
              prefixIcon: Icon(Icons.numbers_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (String? value) =>
                _requiredNumber(value, 'payroll number'),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _saving ? null : _continueFromDriverDetails,
              style: FilledButton.styleFrom(
                backgroundColor: railwayBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rosterSetupStep() {
    return Form(
      key: _rosterFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageHeading(
            'Roster setup',
            'Tell Roster Buddy what you already know about your Base Roster. '
                'You can leave the commencement date blank and set it when '
                'you upload the Base Roster.',
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.calendar_month_outlined,
                color: railwayBlue,
              ),
              title: Text(
                _baseRosterCommencementDate == null
                    ? 'Base Roster commencement'
                    : _formatDate(_baseRosterCommencementDate!),
                style: const TextStyle(
                  color: navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                _baseRosterCommencementDate == null
                    ? 'Optional — select the commencement Sunday if known.'
                    : 'Saved commencement Sunday',
              ),
              trailing: _baseRosterCommencementDate == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      tooltip: 'Clear date',
                      onPressed: () {
                        setState(() {
                          _baseRosterCommencementDate = null;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
              onTap: _selectBaseRosterCommencementDate,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              value: _hasMutualRosterSwap,
              onChanged: _saving
                  ? null
                  : (bool value) {
                      setState(() {
                        _hasMutualRosterSwap = value;

                        if (!value) {
                          _swapPartnerController.clear();
                          _baseRosterStartingLine = 'mine';
                        }
                      });
                    },
              secondary: const Icon(
                Icons.swap_horiz_outlined,
                color: railwayBlue,
              ),
              title: const Text(
                'Mutual permanent roster swap',
                style: TextStyle(color: navy, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Switch this on if you alternate roster lines permanently '
                'with another driver.',
              ),
            ),
          ),
          if (_hasMutualRosterSwap) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _swapPartnerController,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Swap partner roster code',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _optionalPartnerNumber,
            ),
            const SizedBox(height: 16),
            const Text(
              'Which roster line applies at commencement?',
              style: TextStyle(color: navy, fontWeight: FontWeight.w800),
            ),
            RadioGroup<String>(
              groupValue: _baseRosterStartingLine,
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _baseRosterStartingLine = value;
                });
              },
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: 'mine',
                    title: Text('My roster line'),
                  ),
                  RadioListTile<String>(
                    value: 'partner',
                    title: Text("Swap partner's roster line"),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          _backAndContinue(onContinue: _continueFromRosterSetup),
        ],
      ),
    );
  }

  Widget _annualLeaveStep() {
    return Form(
      key: _leaveFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageHeading(
            'Annual leave setup',
            'Set your current floating-leave balance and block-week '
                'allocation, then add any floating dates already confirmed '
                'by Rosters or your DTCM.',
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _floatingBalanceController,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Floating days remaining now',
              helperText: 'Enter the balance you genuinely have left today.',
              prefixIcon: Icon(Icons.beach_access_outlined),
              border: OutlineInputBorder(),
            ),
            validator: _floatingBalanceValidator,
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<int?>(
            initialValue: _blockWeekIndex,
            decoration: InputDecoration(
              labelText: '$_currentLeaveYear block-leave week',
              helperText: 'Choose your allocated week number if you know it.',
              prefixIcon: const Icon(Icons.date_range_outlined),
              border: const OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<int?>>[
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('I will add this later'),
              ),
              ...List<DropdownMenuItem<int?>>.generate(
                13,
                (int index) => DropdownMenuItem<int?>(
                  value: index + 1,
                  child: Text('Week ${index + 1}'),
                ),
              ),
            ],
            onChanged: _saving
                ? null
                : (int? value) {
                    setState(() {
                      _blockWeekIndex = value;
                    });
                  },
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Already-confirmed floating leave',
                    style: TextStyle(
                      color: navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Add floating annual leave that has already been '
                    'authorised. These dates will appear as ALD.',
                    style: TextStyle(color: textGrey, height: 1.4),
                  ),
                  if (_confirmedFloatingLeaveDates.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ..._confirmedFloatingLeaveDates.map(
                      (DateTime date) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.check_circle_outline,
                          color: leaveRed,
                        ),
                        title: Text(_formatDate(date)),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() {
                                    _confirmedFloatingLeaveDates.remove(date);
                                  });
                                },
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _addConfirmedFloatingLeaveDate,
                    icon: const Icon(Icons.add),
                    label: const Text('Add confirmed leave date'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            color: Color(0xFFE8F1F8),
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Your entered remaining balance will remain your remaining '
                'balance after these already-confirmed dates are recorded. '
                'Roster Buddy will not deduct them twice.',
                style: TextStyle(height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _backAndContinue(onContinue: _continueFromAnnualLeave),
        ],
      ),
    );
  }

  Widget _workPreferencesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeading(
          'Work preferences',
          'Set your normal Sunday availability. Individual Sundays can still '
              'be changed later from the calendar.',
        ),
        const SizedBox(height: 24),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            value: _permanentlyUnavailableSundays,
            onChanged: _saving
                ? null
                : (bool value) {
                    setState(() {
                      _permanentlyUnavailableSundays = value;
                    });
                  },
            secondary: const Icon(
              Icons.event_busy_outlined,
              color: railwayBlue,
            ),
            title: const Text(
              'Permanently unavailable Sundays',
              style: TextStyle(color: navy, fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Switch this on if you are normally unavailable for Sunday '
              'work. You can still volunteer for an individual Sunday.',
            ),
          ),
        ),
        const SizedBox(height: 28),
        _backAndContinue(onContinue: _continueFromWorkPreferences),
      ],
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: const TextStyle(color: textGrey)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: navy, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeading(
          'Review your setup',
          'Check the details below. Everything can still be changed later '
              'from Settings.',
        ),
        const SizedBox(height: 22),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _reviewRow('Name', _nameController.text.trim()),
                _reviewRow('Depot', _depotController.text.trim()),
                _reviewRow(
                  'Payroll number',
                  _payrollNumberController.text.trim(),
                ),
                _reviewRow(
                  'Roster number',
                  _rosterNumberController.text.trim(),
                ),
                _reviewRow(
                  'Driver number – Annual Leave',
                  _driverNumberController.text.trim(),
                ),
                const Divider(height: 24),
                _reviewRow(
                  'Base Roster commencement',
                  _baseRosterCommencementDate == null
                      ? 'Add later'
                      : _formatDate(_baseRosterCommencementDate!),
                ),
                _reviewRow(
                  'Permanent roster swap',
                  _hasMutualRosterSwap
                      ? 'Yes — ${_swapPartnerController.text.trim()}'
                      : 'No',
                ),
                if (_hasMutualRosterSwap)
                  _reviewRow(
                    'Starting roster line',
                    _baseRosterStartingLine == 'partner'
                        ? "Partner's line"
                        : 'My line',
                  ),
                const Divider(height: 24),
                _reviewRow(
                  'Floating days remaining',
                  _floatingBalanceController.text.trim(),
                ),
                _reviewRow(
                  'Block-leave allocation',
                  _blockWeekIndex == null
                      ? 'Add later'
                      : 'Week $_blockWeekIndex',
                ),
                _reviewRow(
                  'Confirmed floating dates',
                  '${_confirmedFloatingLeaveDates.length}',
                ),
                const Divider(height: 24),
                _reviewRow(
                  'Sunday availability',
                  _permanentlyUnavailableSundays
                      ? 'Normally unavailable'
                      : 'Normally available',
                ),
              ],
            ),
          ),
        ),
        if (_confirmedFloatingLeaveDates.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Confirmed annual leave dates',
                    style: TextStyle(color: navy, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  ..._confirmedFloatingLeaveDates.map(
                    (DateTime date) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• ${_formatDate(date)}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : _goBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving ? null : _finishSetup,
                style: FilledButton.styleFrom(
                  backgroundColor: railwayBlue,
                  foregroundColor: Colors.white,
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _saving ? 'Saving…' : 'Finish setup',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _currentStep() {
    switch (_step) {
      case 0:
        return _driverDetailsStep();
      case 1:
        return _rosterSetupStep();
      case 2:
        return _annualLeaveStep();
      case 3:
        return _workPreferencesStep();
      case 4:
        return _reviewStep();
      default:
        return _driverDetailsStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          foregroundColor: navy,
          elevation: 0,
          title: const Text(
            'Initial Setup',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _progressHeader(),
                  const SizedBox(height: 30),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_step),
                      child: _currentStep(),
                    ),
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
