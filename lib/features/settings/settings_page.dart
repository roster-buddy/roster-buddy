// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({
    required this.email,
    required this.onSignOut,
    super.key,
  });

  final String email;
  final Future<void> Function() onSignOut;

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);
  static const Color textGrey = Color(0xFF52667A);

  Map<String, dynamic>? _driverProfile;
  bool _loadingProfile = true;

  Map<String, dynamic> get _metadata =>
      Supabase.instance.client.auth.currentUser?.userMetadata ?? {};

  @override
  void initState() {
    super.initState();
    _loadDriverProfile();
  }

  Future<void> _loadDriverProfile() async {
    final User? user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _driverProfile = null;
          _loadingProfile = false;
        });
      }
      return;
    }

    try {
      final Map<String, dynamic>? profile = await Supabase.instance.client
          .from('driver_profiles')
          .select('display_name, depot, driver_number, payroll_number')
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) {
        return;
      }

      setState(() {
        _driverProfile = profile;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _driverProfile = null;
        _loadingProfile = false;
      });
    }
  }

  String _profileSummary() {
    if (_loadingProfile) {
      return 'Loading driver profile...';
    }

    final String tableName = (_driverProfile?['display_name'] ?? '')
        .toString()
        .trim();

    final String tableDriverNumber = (_driverProfile?['driver_number'] ?? '')
        .toString()
        .trim();

    final String metadataName = (_metadata['full_name'] ?? '')
        .toString()
        .trim();

    final String metadataDriverNumber = (_metadata['driver_number'] ?? '')
        .toString()
        .trim();

    final String name = tableName.isNotEmpty ? tableName : metadataName;

    final String driverNumber = tableDriverNumber.isNotEmpty
        ? tableDriverNumber
        : metadataDriverNumber;

    if (name.isNotEmpty && driverNumber.isNotEmpty) {
      return '$name • Driver $driverNumber';
    }

    if (name.isNotEmpty) {
      return name;
    }

    return 'Name, depot, roster code and payroll number';
  }

  String _baseRosterSummary() {
    final String commencementDate =
        (_metadata['base_roster_commencement_date'] ?? '').toString();

    if (commencementDate.isNotEmpty) {
      return 'Active from $commencementDate';
    }

    return 'Commencement date and mutual swap';
  }

  Future<void> _openProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DriverProfilePage()));

    await _loadDriverProfile();
  }

  Future<void> _openBaseRoster() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BaseRosterSetupPage()),
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$feature will be added later.')));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  color: navy,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Manage your driver details, roster setup and app preferences.',
                style: TextStyle(color: textGrey, height: 1.4),
              ),
              const SizedBox(height: 22),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: const Text(
                    'Signed in as',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(widget.email),
                ),
              ),
              const SizedBox(height: 22),
              const _SettingsSectionTitle(title: 'Roster Buddy setup'),
              const SizedBox(height: 10),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.badge_outlined,
                        color: railwayBlue,
                      ),
                      title: const Text(
                        'My Profile',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_profileSummary()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openProfile,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.train_outlined,
                        color: railwayBlue,
                      ),
                      title: const Text(
                        'Base Roster',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_baseRosterSummary()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openBaseRoster,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const _SettingsSectionTitle(title: 'Other settings'),
              const SizedBox(height: 10),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.event_available_outlined,
                        color: railwayBlue,
                      ),
                      title: const Text('Annual Leave'),
                      subtitle: const Text(
                        'Leave blocks, floating days and carry-over',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showComingSoon('Annual Leave'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.notifications_outlined,
                        color: railwayBlue,
                      ),
                      title: const Text('Notifications'),
                      subtitle: const Text(
                        'Shift reminders and amendment alerts',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showComingSoon('Notifications'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.description_outlined,
                        color: railwayBlue,
                      ),
                      title: const Text('Documents'),
                      subtitle: const Text(
                        'Uploaded rosters, amendments and job cards',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showComingSoon('Documents'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.info_outline,
                        color: railwayBlue,
                      ),
                      title: const Text('About'),
                      subtitle: const Text('Roster Buddy Version 1'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showComingSoon('About'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Roster email'),
                  subtitle: const Text('drivers.rosters@wmtrains.co.uk'),
                ),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: () async {
                  await widget.onSignOut();
                },
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Sign out',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key});

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _depotController = TextEditingController();
  final TextEditingController _driverNumberController = TextEditingController();
  final TextEditingController _payrollNumberController =
      TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _depotController.dispose();
    _driverNumberController.dispose();
    _payrollNumberController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SupabaseClient supabase = Supabase.instance.client;
    final User? user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'You must be signed in to edit your driver profile.';
        });
      }
      return;
    }

    final Map<String, dynamic> metadata = user.userMetadata ?? {};

    _nameController.text = (metadata['full_name'] ?? '').toString();
    _depotController.text = (metadata['depot'] ?? '').toString();
    _driverNumberController.text = (metadata['driver_number'] ?? '').toString();
    _payrollNumberController.text = (metadata['payroll_number'] ?? '')
        .toString();

    try {
      final Map<String, dynamic>? profile = await supabase
          .from('driver_profiles')
          .select('display_name, depot, driver_number, payroll_number')
          .eq('user_id', user.id)
          .maybeSingle();

      if (profile != null) {
        _nameController.text = (profile['display_name'] ?? '').toString();
        _depotController.text = (profile['depot'] ?? '').toString();
        _driverNumberController.text = (profile['driver_number'] ?? '')
            .toString();
        _payrollNumberController.text = (profile['payroll_number'] ?? '')
            .toString();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError =
            'The saved database profile could not be loaded. '
            'Existing account details are shown instead.';
      });
    }
  }

  String? _requiredValue(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your $label';
    }

    return null;
  }

  String? _requiredNumber(String? value, String label) {
    final String cleaned = value?.trim() ?? '';

    if (cleaned.isEmpty) {
      return 'Enter your $label';
    }

    if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) {
      return '$label must contain numbers only';
    }

    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final SupabaseClient supabase = Supabase.instance.client;
    final User? user = supabase.auth.currentUser;

    if (user == null) {
      _showMessage(
        'You must be signed in before saving your driver profile.',
        isError: true,
      );
      return;
    }

    final String displayName = _nameController.text.trim();
    final String depot = _depotController.text.trim();
    final String driverNumber = _driverNumberController.text.trim();
    final String payrollNumber = _payrollNumberController.text.trim();

    setState(() {
      _saving = true;
    });

    try {
      await supabase.from('driver_profiles').upsert({
        'user_id': user.id,
        'display_name': displayName,
        'depot': depot,
        'driver_number': driverNumber,
        'payroll_number': payrollNumber,
      }, onConflict: 'user_id');

      try {
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'full_name': displayName,
              'depot': depot,
              'driver_number': driverNumber,
              'payroll_number': payrollNumber,
            },
          ),
        );
      } catch (_) {
        if (!mounted) {
          return;
        }

        _showMessage(
          'Your driver profile was saved for roster matching, but the '
          'account summary could not be synchronised.',
          isError: true,
        );

        Navigator.of(context).pop();
        return;
      }

      if (!mounted) {
        return;
      }

      _showMessage('Driver profile saved.');

      Navigator.of(context).pop();
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }

      if (error.code == '23505') {
        final String message = error.message.toLowerCase();

        if (message.contains('payroll')) {
          _showMessage(
            'That payroll number is already linked to another Roster Buddy '
            'account.',
            isError: true,
          );
        } else if (message.contains('driver')) {
          _showMessage(
            'That roster code is already linked to another Roster Buddy '
            'account.',
            isError: true,
          );
        } else {
          _showMessage(
            'That payroll number or roster code is already linked to '
            'another Roster Buddy account.',
            isError: true,
          );
        }
      } else {
        _showMessage(
          'Unable to save driver profile: ${error.message}',
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to save driver profile. Please try again.',
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
          backgroundColor: isError ? const Color(0xFFC62828) : null,
          behavior: SnackBarBehavior.floating,
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
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text(
                          'These details allow Smart Scan to match your duties '
                          'when another user uploads a roster or amendment '
                          'document containing several drivers.',
                          style: TextStyle(height: 1.4),
                        ),
                        if (_loadError != null) ...[
                          const SizedBox(height: 16),
                          Card(
                            color: const Color(0xFFFFF3CD),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.warning_amber_outlined),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(_loadError!)),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
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
                          validator: (value) =>
                              _requiredValue(value, 'full name'),
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
                          validator: (value) => _requiredValue(value, 'depot'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _driverNumberController,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Roster Code',
                            helperText:
                                'Used to locate your position on a Base Roster.',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              _requiredNumber(value, 'roster code'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _payrollNumberController,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_saving) {
                              _save();
                            }
                          },
                          decoration: const InputDecoration(
                            labelText: 'Payroll number',
                            helperText:
                                'Used to find your row on amendment sheets.',
                            prefixIcon: Icon(Icons.numbers_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              _requiredNumber(value, 'payroll number'),
                        ),
                        const SizedBox(height: 16),
                        const Card(
                          color: Color(0xFFE8F1F8),
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.sync_outlined, color: railwayBlue),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Once saved, duties uploaded by any '
                                    'applicable Roster Buddy user can be '
                                    'matched to your account automatically.',
                                    style: TextStyle(height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: railwayBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving...' : 'Save profile'),
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

class BaseRosterSetupPage extends StatefulWidget {
  const BaseRosterSetupPage({super.key});

  @override
  State<BaseRosterSetupPage> createState() => _BaseRosterSetupPageState();
}

class _BaseRosterSetupPageState extends State<BaseRosterSetupPage> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _swapPartnerController = TextEditingController();

  DateTime? _commencementDate;
  bool _hasMutualSwap = false;
  String _firstLine = 'my_line';
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final Map<String, dynamic> metadata =
        Supabase.instance.client.auth.currentUser?.userMetadata ?? {};

    final String storedDate = (metadata['base_roster_commencement_date'] ?? '')
        .toString();

    if (storedDate.isNotEmpty) {
      _commencementDate = DateTime.tryParse(storedDate);
    }

    _hasMutualSwap = metadata['has_mutual_swap'] == true;
    _swapPartnerController.text = (metadata['swap_partner_driver_number'] ?? '')
        .toString();

    final String storedFirstLine = (metadata['mutual_swap_first_line'] ?? '')
        .toString();

    if (storedFirstLine == 'swap_partner_line') {
      _firstLine = 'swap_partner_line';
    }
  }

  @override
  void dispose() {
    _swapPartnerController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final String day = date.day.toString().padLeft(2, '0');
    final String month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  String _storageDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  Future<void> _chooseDate() async {
    final DateTime now = DateTime.now();

    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _commencementDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
      helpText: 'Select Base Roster commencement date',
    );

    if (selected != null) {
      setState(() {
        _commencementDate = selected;
      });
    }
  }

  String? _validateSwapPartner(String? value) {
    if (!_hasMutualSwap) {
      return null;
    }

    final String cleaned = value?.trim() ?? '';

    if (cleaned.isEmpty) {
      return 'Enter the swap partner’s roster code';
    }

    if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) {
      return 'Roster Code must contain numbers only';
    }

    return null;
  }

  Future<void> _save() async {
    if (_commencementDate == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Select the Base Roster commencement date.'),
          ),
        );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'base_roster_commencement_date': _storageDate(_commencementDate!),
            'has_mutual_swap': _hasMutualSwap,
            'swap_partner_driver_number': _hasMutualSwap
                ? _swapPartnerController.text.trim()
                : null,
            'mutual_swap_first_line': _hasMutualSwap ? _firstLine : 'my_line',
          },
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Base Roster setup saved.')),
        );

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Unable to save Base Roster setup: $error')),
        );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
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
          'Base Roster Setup',
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
                  const Text(
                    'The commencement date is entered by you because it is not '
                    'printed on the Base Roster. The roster will continue from '
                    'this date until a newer Base Roster is uploaded.',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.event_outlined,
                        color: railwayBlue,
                      ),
                      title: const Text('Commencement date'),
                      subtitle: Text(
                        _commencementDate == null
                            ? 'Not selected'
                            : _formatDate(_commencementDate!),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _chooseDate,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: SwitchListTile(
                      value: _hasMutualSwap,
                      activeThumbColor: railwayBlue,
                      title: const Text(
                        'Mutual permanent swap',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Alternate between your line and your swap partner’s '
                        'line while moving down one roster week each week.',
                      ),
                      onChanged: (value) {
                        setState(() {
                          _hasMutualSwap = value;

                          if (!value) {
                            _firstLine = 'my_line';
                          }
                        });
                      },
                    ),
                  ),
                  if (_hasMutualSwap) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _swapPartnerController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Swap partner Roster Code',
                        prefixIcon: Icon(Icons.swap_horiz),
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateSwapPartner,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Which line supplies the commencement week?',
                      style: TextStyle(
                        color: navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            value: 'my_line',
                            groupValue: _firstLine,
                            title: const Text('My line'),
                            subtitle: const Text(
                              'Week 1 uses my line. Week 2 moves down one '
                              'roster week and uses my partner’s line.',
                            ),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _firstLine = value;
                                });
                              }
                            },
                          ),
                          const Divider(height: 1),
                          RadioListTile<String>(
                            value: 'swap_partner_line',
                            groupValue: _firstLine,
                            title: const Text('Swap partner’s line'),
                            subtitle: const Text(
                              'Week 1 uses my partner’s line. Week 2 moves '
                              'down one roster week and uses my line.',
                            ),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _firstLine = value;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: railwayBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving ? 'Saving...' : 'Save Base Roster setup',
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

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF102A43),
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
