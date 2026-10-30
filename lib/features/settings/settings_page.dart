import 'documents_page.dart';
import '../../core/formatters/roster_date_format.dart';
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../core/widgets/roster_decision_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/annual_leave_balance.dart';
import '../../core/models/annual_leave_block_cycle.dart';
import '../../core/models/annual_leave_block_override.dart';
import '../../core/models/annual_leave_request.dart';
import '../../core/services/annual_leave_block_pending_action_service.dart';
import '../../core/services/annual_leave_block_service.dart';
import '../../core/services/annual_leave_service.dart';
import '../../core/services/floating_leave_cancellation.dart';
import '../upload/storage_service.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({
    required this.email,
    required this.onSignOut,
    this.onNavigate,
    this.onOpenNotifications,
    super.key,
  });

  final Future<void> Function()? onOpenNotifications;

  final String email;
  final Future<void> Function() onSignOut;
  final Future<void> Function(int destination)? onNavigate;

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

    return 'Name, depot, Driver Number and payroll number';
  }

  String _baseRosterSummary() {
    final String commencementDate =
        (_metadata['base_roster_commencement_date'] ?? '').toString();

    if (commencementDate.isNotEmpty) {
      return 'Active from ${displayStoredDate(commencementDate)}';
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

  Future<void> _openAnnualLeave() async {
    if (widget.onNavigate != null) {
      await widget.onNavigate!(3);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnnualLeaveSettingsPage(
          currentTabIndex: 4,
          onNavigate: widget.onNavigate,
        ),
      ),
    );
  }

  Future<void> _openDocuments() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const DocumentsPage()),
  );

  Future<void> _openAbout() => showModalBottomSheet<void>(
    context: context, showDragHandle: true,
    builder: (_) => const SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Roster Buddy', style: TextStyle(color: navy, fontSize: 24, fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          Text('Version 1.0.0 (1)'),
          SizedBox(height: 16),
          Text('Your railway roster, annual leave and duty history in one place.'),
          SizedBox(height: 12),
          Text('Use Notifications to action pending requests and Documents to open your uploaded files.'),
        ],
      ),
    )),
  );

  Future<void> _openRosterEmail() async {
    final opened = await launchUrl(
      Uri(scheme: 'mailto', path: 'drivers.rosters@wmtrains.co.uk'),
      webOnlyWindowName: '_self',
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open your email app.')),
      );
    }
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
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openProfile,
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
                      onTap: _openAnnualLeave,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.notifications_outlined,
                        color: railwayBlue,
                      ),
                      title: const Text('Notifications'),
                      subtitle: const Text(
                        'Pending requests, approvals and allocations',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: widget.onOpenNotifications,
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
                      onTap: _openDocuments,
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
                      onTap: _openAbout,
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
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openRosterEmail,
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

class AnnualLeaveSettingsPage extends StatefulWidget {
  const AnnualLeaveSettingsPage({
    this.onRosterChanged,
    this.refreshVersion = 0,
    this.currentTabIndex = 3,
    this.onNavigate,
    this.embedded = false,
    super.key,
  });

  final int currentTabIndex;
  final int refreshVersion;
  final VoidCallback? onRosterChanged;
  final Future<void> Function(int destination)? onNavigate;
  final bool embedded;

  @override
  State<AnnualLeaveSettingsPage> createState() =>
      _AnnualLeaveSettingsPageState();
}

class _AnnualLeaveSettingsPageState extends State<AnnualLeaveSettingsPage> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);
  static const Color leaveRed = Color(0xFFD64545);
  static const Color textGrey = Color(0xFF52667A);
  static const Color abeyanceAmber = Color(0xFFF59E0B);

  final AnnualLeaveService _annualLeaveService = AnnualLeaveService();
  final AnnualLeaveBlockService _annualLeaveBlockService =
      AnnualLeaveBlockService();
  final AnnualLeaveBlockPendingActionService
  _annualLeaveBlockPendingActionService =
      AnnualLeaveBlockPendingActionService();

  late int _leaveYear;
  bool _showTakenDays = false;

  bool _loading = true;
  String? _loadError;

  int _entitlementDays = 14;
  int _startingBalanceDays = 14;
  int _bonusDays = 0;
  int _carryOverDays = 0;
  int _lieuDays = 0;
  int _remainingDays = 14;

  List<AnnualLeaveRequest> _requests = <AnnualLeaveRequest>[];
  List<Map<String, dynamic>> _scheduledRequests = <Map<String, dynamic>>[];
  List<_AnnualLeaveBlockPeriod> _blockPeriods = <_AnnualLeaveBlockPeriod>[];

  AnnualLeaveBlockCycle? _blockCycle;
  List<AnnualLeaveBlockOverride> _blockOverrides = <AnnualLeaveBlockOverride>[];

  @override
  void initState() {
    super.initState();

    _leaveYear = DateTime.now().year;
    _load();
  }

  @override
  void didUpdateWidget(covariant AnnualLeaveSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _load();
    }
  }

  int _leaveLoadGeneration = 0;

  Future<void> _load() async {
    final generation = ++_leaveLoadGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final SupabaseClient supabase = Supabase.instance.client;
      final User? user = supabase.auth.currentUser;

      if (user == null) {
        throw const AnnualLeaveException(
          'You must be signed in before loading annual leave.',
        );
      }

      final DateTime yearStart = DateTime(_leaveYear, 1, 1);
      final DateTime yearEnd = DateTime(_leaveYear, 12, 31);

      final results = await Future.wait<Object?>([
        _annualLeaveService.getBalanceForYear(_leaveYear),
        _annualLeaveService.getRequestsForRange(yearStart, yearEnd),
        _annualLeaveService.getScheduledFloatingRequestsForYear(_leaveYear),
        _annualLeaveBlockService.getCycleForYear(_leaveYear),
        _annualLeaveBlockService.getOverridesForYear(_leaveYear),
        supabase
          .from('driver_profiles')
          .select('driver_number')
          .eq('user_id', user.id)
          .maybeSingle(),
      ]);
      final balance = results[0] as AnnualLeaveBalance;
      final requestMap = results[1] as Map<String, AnnualLeaveRequest>;
      final scheduledRequests = results[2] as List<Map<String, dynamic>>;
      final blockCycle = results[3] as AnnualLeaveBlockCycle?;
      final blockOverrides = results[4] as List<AnnualLeaveBlockOverride>;
      final profile = results[5] as Map<String, dynamic>?;

      final String driverNumber = (profile?['driver_number'] ?? '')
          .toString()
          .trim();

      final List<_AnnualLeaveBlockPeriod> blockPeriods =
          <_AnnualLeaveBlockPeriod>[];

      if (driverNumber.isNotEmpty) {
        final List<dynamic> blockResponse = await supabase
            .from('annual_leave_periods')
            .select(
              'period_type, start_date, end_date, '
              'annual_leave_allocations!inner('
              'driver_number, is_confirmed'
              ')',
            )
            .lte('start_date', _databaseDate(yearEnd))
            .gte('end_date', _databaseDate(yearStart))
            .eq('annual_leave_allocations.driver_number', driverNumber)
            .eq('annual_leave_allocations.is_confirmed', true)
            .order('start_date');

        for (final Map<String, dynamic> row
            in blockResponse.whereType<Map<String, dynamic>>()) {
          final DateTime? start = DateTime.tryParse(
            (row['start_date'] ?? '').toString(),
          );
          final DateTime? end = DateTime.tryParse(
            (row['end_date'] ?? '').toString(),
          );

          if (start == null || end == null) {
            continue;
          }

          blockPeriods.add(
            _AnnualLeaveBlockPeriod(
              type: (row['period_type'] ?? '').toString(),
              start: start,
              end: end,
              isOfficial: true,
            ),
          );
        }
      }

      {
        const List<AnnualLeaveBlockPeriodType> periodOrder =
            <AnnualLeaveBlockPeriodType>[
              AnnualLeaveBlockPeriodType.spring,
              AnnualLeaveBlockPeriodType.summerFirstWeek,
              AnnualLeaveBlockPeriodType.summerSecondWeek,
              AnnualLeaveBlockPeriodType.winter,
            ];

        for (final AnnualLeaveBlockPeriodType type in periodOrder) {
          if (blockPeriods.any((period) =>
              period.type == _blockPeriodDatabaseValue(type))) {
            continue;
          }
          AnnualLeaveBlockOverride? stored;

          for (final AnnualLeaveBlockOverride value in blockOverrides) {
            if (value.periodType == type) {
              stored = value;
              break;
            }
          }

          if (stored == null) {
            continue;
          }

          final DateTime baselineStart =
              stored.originalStartDate ?? stored.overrideStartDate;
          final DateTime baselineEnd =
              stored.originalEndDate ?? stored.overrideEndDate;

          blockPeriods.add(
            _AnnualLeaveBlockPeriod(
              type: _blockPeriodDatabaseValue(type),
              start: baselineStart,
              end: baselineEnd,
              isOfficial: false,
            ),
          );
        }
      }

      int blockPeriodOrder(String type) {
        switch (type) {
          case 'spring':
            return 0;
          case 'summer_first_week':
            return 1;
          case 'summer_second_week':
            return 2;
          case 'winter':
            return 3;
          default:
            return 99;
        }
      }

      blockPeriods.sort(
        (_AnnualLeaveBlockPeriod first, _AnnualLeaveBlockPeriod second) =>
            blockPeriodOrder(
              first.type,
            ).compareTo(blockPeriodOrder(second.type)),
      );

      final List<AnnualLeaveRequest> requests = requestMap.values.toList()
        ..sort(
          (AnnualLeaveRequest first, AnnualLeaveRequest second) =>
              first.leaveDate.compareTo(second.leaveDate),
        );

      if (!mounted || generation != _leaveLoadGeneration) {
        return;
      }

      setState(() {
        _entitlementDays = balance.entitlementDays;
        _startingBalanceDays = balance.startingBalanceDays;
        _bonusDays = balance.bonusDays;
        _carryOverDays = balance.carryOverDays;
        _lieuDays = balance.lieuDays;
        _remainingDays = balance.remainingDays;
        _requests = requests;
        _scheduledRequests = scheduledRequests;
        _blockPeriods = blockPeriods;
        _blockCycle = blockCycle;
        _blockOverrides = blockOverrides;
        _loading = false;
      });
    } on AnnualLeaveException catch (error) {
      if (!mounted || generation != _leaveLoadGeneration) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    } on AnnualLeaveBlockPendingActionException catch (error) {
      if (!mounted || generation != _leaveLoadGeneration) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    } catch (_) {
      if (!mounted || generation != _leaveLoadGeneration) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError =
            'Roster Buddy could not load your annual leave information.';
      });
    }
  }

  Future<void> _changeYear(int offset) async {
    setState(() {
      _leaveYear += offset;
      _showTakenDays = false;
    });

    await _load();
  }

  int get _committedDays {
    return _requests.where((AnnualLeaveRequest request) {
      return request.requestType == AnnualLeaveRequestType.floating &&
          request.status == AnnualLeaveRequestStatus.granted;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: widget.embedded
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              foregroundColor: navy,
              elevation: 0,
              title: const Text(
                'Annual Leave',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildYearSelector(),
                        const SizedBox(height: 18),
                        if (_loadError != null)
                          _buildErrorCard()
                        else ...[
                          _buildFloatingBalanceCard(),
                          const SizedBox(height: 18),
                          _buildRequestsCard(),
                          const SizedBox(height: 18),
                          _buildBlockLeaveCard(),
                          const SizedBox(height: 18),
                          _buildScheduledRequestsCard(),
                        ],
                        const SizedBox(height: 30),
                      ],
                    ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: widget.embedded
          ? null
          : NavigationBar(
              selectedIndex: widget.currentTabIndex,
              onDestinationSelected: (int index) async {
                final Future<void> Function(int destination)? onNavigate =
                    widget.onNavigate;

                if (onNavigate == null) {
                  return;
                }

                if (index == 2) {
                  await onNavigate(index);
                  return;
                }

                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }

                await onNavigate(index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Calendar',
                ),
                NavigationDestination(
                  icon: Icon(Icons.upload_file_outlined),
                  selectedIcon: Icon(Icons.upload_file),
                  label: 'Upload',
                ),
                NavigationDestination(
                  icon: Icon(Icons.beach_access_outlined),
                  selectedIcon: Icon(Icons.beach_access),
                  label: 'Annual Leave',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }

  Widget _buildYearSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous leave year',
              onPressed: _loading ? null : () => _changeYear(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '$_leaveYear Annual Leave',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: navy,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '1 January $_leaveYear – 31 December $_leaveYear',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: textGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Next leave year',
              onPressed: _loading ? null : () => _changeYear(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingBalanceCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(0x1A1769AA),
              child: Icon(Icons.beach_access_outlined, color: railwayBlue),
            ),
            title: Text(
              'Floating days left',
              style: TextStyle(color: navy, fontWeight: FontWeight.w900),
            ),
            subtitle: Text('Full days available to take this leave year'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              children: [
                Text(
                  '$_remainingDays',
                  style: const TextStyle(
                    color: leaveRed,
                    fontSize: 48,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _remainingDays == 1
                      ? 'floating day left to take'
                      : 'floating days left to take',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_leaveYear leave year',
                  style: const TextStyle(color: textGrey, fontSize: 12),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showFloatingBalanceBreakdown,
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Breakdown & edit'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFloatingBalanceBreakdown() async {
    final int totalAvailable =
        _startingBalanceDays + _bonusDays + _carryOverDays + _lieuDays;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_leaveYear floating leave',
                  style: const TextStyle(
                    color: navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Allowance breakdown',
                  style: TextStyle(color: textGrey),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: railwayBlue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _AnnualLeaveSummaryRow(
                        label: 'Normal entitlement',
                        value: '$_entitlementDays days',
                      ),
                      const SizedBox(height: 8),
                      _AnnualLeaveSummaryRow(
                        label: 'Starting balance',
                        value: '$_startingBalanceDays days',
                      ),
                      const SizedBox(height: 8),
                      _AnnualLeaveSummaryRow(
                        label: 'Bonus days',
                        value: '+$_bonusDays days',
                      ),
                      const SizedBox(height: 8),
                      _AnnualLeaveSummaryRow(
                        label: 'Carry-over',
                        value: '+$_carryOverDays days',
                      ),
                      const SizedBox(height: 8),
                      _AnnualLeaveSummaryRow(
                        label: 'Days in lieu',
                        value: '+$_lieuDays days',
                      ),
                      const Divider(height: 22),
                      _AnnualLeaveSummaryRow(
                        label: 'Total available',
                        value: '$totalAvailable days',
                        bold: true,
                      ),
                      const SizedBox(height: 8),
                      _AnnualLeaveSummaryRow(
                        label: 'Granted floating leave',
                        value: '-$_committedDays days',
                      ),
                      const Divider(height: 22),
                      _AnnualLeaveSummaryRow(
                        label: 'Days left',
                        value: '$_remainingDays days',
                        bold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _showBalanceSetupDialog();
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit floating allowance'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBalanceSetupDialog() async {
    final TextEditingController startingController = TextEditingController(
      text: _startingBalanceDays.toString(),
    );
    final TextEditingController bonusController = TextEditingController(
      text: _bonusDays.toString(),
    );
    final TextEditingController carryController = TextEditingController(
      text: _carryOverDays.toString(),
    );
    final TextEditingController lieuController = TextEditingController(
      text: _lieuDays.toString(),
    );

    bool saving = false;
    String? errorMessage;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext sheetContext, void Function(void Function()) setSheetState) {
            int? valueOf(TextEditingController controller) {
              return int.tryParse(controller.text.trim());
            }

            Future<void> save() async {
              if (saving) {
                return;
              }

              final int? starting = valueOf(startingController);
              final int? bonus = valueOf(bonusController);
              final int? carry = valueOf(carryController);
              final int? lieu = valueOf(lieuController);

              if (starting == null ||
                  bonus == null ||
                  carry == null ||
                  lieu == null) {
                setSheetState(() {
                  errorMessage = 'Enter whole numbers for all leave values.';
                });
                return;
              }

              if (starting < 0 || bonus < 0 || carry < 0 || lieu < 0) {
                setSheetState(() {
                  errorMessage = 'Annual leave values cannot be negative.';
                });
                return;
              }

              setSheetState(() {
                saving = true;
                errorMessage = null;
              });

              try {
                await _annualLeaveService.saveBalanceSetup(
                  leaveYear: _leaveYear,
                  entitlementDays: 14,
                  startingBalanceDays: starting,
                  bonusDays: bonus,
                  carryOverDays: carry,
                  lieuDays: lieu,
                );

                if (!sheetContext.mounted) {
                  return;
                }

                Navigator.of(sheetContext).pop();

                await _load();

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        '$_leaveYear annual leave allowance updated.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              } on AnnualLeaveException catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  saving = false;
                  errorMessage = error.message;
                });
              } catch (_) {
                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  saving = false;
                  errorMessage =
                      'Roster Buddy could not save the annual leave allowance.';
                });
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_leaveYear floating leave',
                        style: const TextStyle(
                          color: navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Normal yearly entitlement: 14 days',
                        style: TextStyle(color: textGrey),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: startingController,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Starting balance',
                          helperText: _leaveYear == DateTime.now().year
                              ? 'Use your actual remaining balance if joining '
                                    'Roster Buddy part way through the year.'
                              : 'Normally 14 at the start of a new leave year.',
                          prefixIcon: const Icon(Icons.beach_access_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: bonusController,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Bonus days',
                          helperText:
                              'Extra leave awarded during this leave year.',
                          prefixIcon: Icon(Icons.add_circle_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: carryController,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Carry-over days',
                          helperText:
                              'Unused floating leave carried from the previous year.',
                          prefixIcon: Icon(Icons.redo_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: lieuController,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Days in lieu',
                          helperText: 'Additional leave awarded in lieu.',
                          prefixIcon: Icon(Icons.event_repeat_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: leaveRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: leaveRed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: saving ? null : save,
                          icon: saving
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(saving ? 'Saving…' : 'Save allowance'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    startingController.dispose();
    bonusController.dispose();
    carryController.dispose();
    lieuController.dispose();
  }

  static String _blockPeriodDatabaseValue(AnnualLeaveBlockPeriodType value) {
    switch (value) {
      case AnnualLeaveBlockPeriodType.spring:
        return 'spring';
      case AnnualLeaveBlockPeriodType.summerFirstWeek:
        return 'summer_first_week';
      case AnnualLeaveBlockPeriodType.summerSecondWeek:
        return 'summer_second_week';
      case AnnualLeaveBlockPeriodType.winter:
        return 'winter';
    }
  }

  AnnualLeaveBlockPeriodType? _blockPeriodType(String value) {
    switch (value) {
      case 'spring':
        return AnnualLeaveBlockPeriodType.spring;
      case 'summer_first_week':
        return AnnualLeaveBlockPeriodType.summerFirstWeek;
      case 'summer_second_week':
        return AnnualLeaveBlockPeriodType.summerSecondWeek;
      case 'winter':
        return AnnualLeaveBlockPeriodType.winter;
      default:
        return null;
    }
  }

  AnnualLeaveBlockOverride? _overrideForPeriod(String periodType) {
    final AnnualLeaveBlockPeriodType? type = _blockPeriodType(periodType);

    if (type == null) {
      return null;
    }

    final bool hasOfficialPeriod = _blockPeriods.any(
      (_AnnualLeaveBlockPeriod period) =>
          period.type == periodType && period.isOfficial,
    );

    for (final AnnualLeaveBlockOverride override in _blockOverrides) {
      if (override.periodType != type) {
        continue;
      }

      if (hasOfficialPeriod &&
          override.changeType == AnnualLeaveBlockChangeType.manual) {
        return null;
      }

      return override;
    }

    return null;
  }

  String _blockChangeLabel(AnnualLeaveBlockChangeType value) {
    switch (value) {
      case AnnualLeaveBlockChangeType.manual:
        return 'MANUAL';
      case AnnualLeaveBlockChangeType.agreedMove:
        return 'MOVED';
      case AnnualLeaveBlockChangeType.mutualSwap:
        return 'SWAPPED';
    }
  }

  Future<void> _showBlockCycleDialog() async {
    int selectedBlock = _blockCycle?.weekIndex ?? 1;
    bool saving = false;
    String? errorMessage;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext sheetContext,
                void Function(void Function()) setSheetState,
              ) {
                Future<void> save() async {
                  if (saving) {
                    return;
                  }

                  setSheetState(() {
                    saving = true;
                    errorMessage = null;
                  });

                  try {
                    await _annualLeaveBlockService.saveCycleForYear(
                      leaveYear: _leaveYear,
                      weekIndex: selectedBlock,
                    );

                    // Automatically prepare the following year's +5 allocation.
                    await _annualLeaveBlockService.ensureNextYearCycle(
                      currentLeaveYear: _leaveYear,
                    );

                    if (!sheetContext.mounted) {
                      return;
                    }

                    Navigator.of(sheetContext).pop();

                    await _load();

                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            '$_leaveYear block allocation saved as '
                            'Block $selectedBlock.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                  } on AnnualLeaveBlockException catch (error) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      saving = false;
                      errorMessage = error.message;
                    });
                  } catch (_) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      saving = false;
                      errorMessage =
                          'Roster Buddy could not save the block allocation.';
                    });
                  }
                }

                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_leaveYear block allocation',
                            style: const TextStyle(
                              color: navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Choose the block number allocated to you on the '
                            'Annual Leave Roster.',
                            style: TextStyle(color: textGrey, height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          DropdownButtonFormField<int>(
                            value: selectedBlock,
                            decoration: const InputDecoration(
                              labelText: 'Allocated block',
                              prefixIcon: Icon(Icons.date_range_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: List<DropdownMenuItem<int>>.generate(13, (
                              int index,
                            ) {
                              final int value = index + 1;

                              return DropdownMenuItem<int>(
                                value: value,
                                child: Text('Block $value'),
                              );
                            }),
                            onChanged: saving
                                ? null
                                : (int? value) {
                                    if (value == null) {
                                      return;
                                    }

                                    setSheetState(() {
                                      selectedBlock = value;
                                    });
                                  },
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: railwayBlue.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Next year: Block '
                              '${AnnualLeaveBlockCycle.advanceWeekIndex(selectedBlock)} '
                              '(moves forward 5 blocks)',
                              style: const TextStyle(
                                color: navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              errorMessage!,
                              style: const TextStyle(
                                color: leaveRed,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: saving ? null : save,
                              icon: saving
                                  ? const SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                saving ? 'Saving…' : 'Save block allocation',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
        );
      },
    );
  }

  Future<void> _showManualBlockDatesDialog() async {
    final Map<AnnualLeaveBlockPeriodType, DateTime?> starts =
        <AnnualLeaveBlockPeriodType, DateTime?>{
          AnnualLeaveBlockPeriodType.spring: null,
          AnnualLeaveBlockPeriodType.summerFirstWeek: null,
          AnnualLeaveBlockPeriodType.summerSecondWeek: null,
          AnnualLeaveBlockPeriodType.winter: null,
        };

    for (final _AnnualLeaveBlockPeriod period in _blockPeriods) {
      if (period.isOfficial) {
        continue;
      }

      final AnnualLeaveBlockPeriodType? type = _blockPeriodType(period.type);

      if (type != null) {
        starts[type] = period.start;
      }
    }

    bool saving = false;
    String? errorMessage;

    String labelFor(AnnualLeaveBlockPeriodType type) {
      switch (type) {
        case AnnualLeaveBlockPeriodType.spring:
          return 'Spring';
        case AnnualLeaveBlockPeriodType.summerFirstWeek:
          return 'Summer 1';
        case AnnualLeaveBlockPeriodType.summerSecondWeek:
          return 'Summer 2';
        case AnnualLeaveBlockPeriodType.winter:
          return 'Winter';
      }
    }

    DateTime mondayFor(DateTime value) {
      final DateTime clean = DateTime(value.year, value.month, value.day);

      return clean.subtract(Duration(days: clean.weekday - DateTime.monday));
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext sheetContext,
                void Function(void Function()) setSheetState,
              ) {
                Future<void> chooseDate(AnnualLeaveBlockPeriodType type) async {
                  final DateTime initial =
                      starts[type] ?? DateTime(_leaveYear, 1, 5);

                  final DateTime? picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: initial,
                    firstDate: DateTime(_leaveYear, 1, 1),
                    lastDate: DateTime(_leaveYear, 12, 31),
                    helpText: '${labelFor(type)} block week',
                  );

                  if (picked == null || !sheetContext.mounted) {
                    return;
                  }

                  final DateTime monday = mondayFor(picked);

                  if (monday.year != _leaveYear ||
                      monday.add(const Duration(days: 5)).year != _leaveYear) {
                    setSheetState(() {
                      errorMessage =
                          'The complete Monday–Saturday block week must fall '
                          'inside $_leaveYear.';
                    });
                    return;
                  }

                  setSheetState(() {
                    starts[type] = monday;
                    errorMessage = null;
                  });
                }

                Future<void> save() async {
                  if (saving) {
                    return;
                  }

                  final bool missing = starts.values.any(
                    (DateTime? value) => value == null,
                  );

                  if (missing) {
                    setSheetState(() {
                      errorMessage =
                          'Choose all four block weeks before saving.';
                    });
                    return;
                  }

                  setSheetState(() {
                    saving = true;
                    errorMessage = null;
                  });

                  try {
                    for (final MapEntry<AnnualLeaveBlockPeriodType, DateTime?>
                        entry
                        in starts.entries) {
                      final DateTime start = entry.value!;
                      final DateTime end = start.add(const Duration(days: 5));

                      await _annualLeaveBlockService.saveOverride(
                        leaveYear: _leaveYear,
                        periodType: entry.key,
                        originalStartDate: start,
                        originalEndDate: end,
                        overrideStartDate: start,
                        overrideEndDate: end,
                        changeType: AnnualLeaveBlockChangeType.manual,
                        notes: 'Manual block allocation',
                      );
                    }

                    if (!sheetContext.mounted) {
                      return;
                    }

                    Navigator.of(sheetContext).pop();

                    await _load();

                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            '$_leaveYear manual block weeks saved.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                  } on AnnualLeaveBlockException catch (error) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      saving = false;
                      errorMessage = error.message;
                    });
                  } catch (_) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      saving = false;
                      errorMessage =
                          'Roster Buddy could not save the manual block weeks.';
                    });
                  }
                }

                const List<AnnualLeaveBlockPeriodType> order =
                    <AnnualLeaveBlockPeriodType>[
                      AnnualLeaveBlockPeriodType.spring,
                      AnnualLeaveBlockPeriodType.summerFirstWeek,
                      AnnualLeaveBlockPeriodType.summerSecondWeek,
                      AnnualLeaveBlockPeriodType.winter,
                    ];

                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_leaveYear manual block weeks',
                            style: const TextStyle(
                              color: navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Use this when your official Annual Leave Roster '
                            'has not been uploaded yet. Choose a date in each '
                            'block week; Roster Buddy will use the Monday to '
                            'Saturday of that week.',
                            style: TextStyle(color: textGrey, height: 1.4),
                          ),
                          const SizedBox(height: 18),

                          for (final AnnualLeaveBlockPeriodType type in order)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: leaveRed.withValues(alpha: 0.18),
                                  ),
                                ),
                                leading: const Icon(
                                  Icons.date_range_outlined,
                                  color: leaveRed,
                                ),
                                title: Text(
                                  labelFor(type),
                                  style: const TextStyle(
                                    color: navy,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: starts[type] == null
                                    ? const Text('Not set')
                                    : Text(
                                        '${_displayDate(starts[type]!)} – '
                                        '${_displayDate(starts[type]!.add(const Duration(days: 5)))}',
                                      ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: saving ? null : () => chooseDate(type),
                              ),
                            ),

                          if (errorMessage != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              errorMessage!,
                              style: const TextStyle(
                                color: leaveRed,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],

                          const SizedBox(height: 18),

                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: saving ? null : save,
                              icon: saving
                                  ? const SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                saving ? 'Saving…' : 'Save manual block weeks',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
        );
      },
    );
  }

  String _blockWeekGroup(AnnualLeaveBlockPeriodType periodType) {
    switch (periodType) {
      case AnnualLeaveBlockPeriodType.spring:
        return 'spring';
      case AnnualLeaveBlockPeriodType.summerFirstWeek:
      case AnnualLeaveBlockPeriodType.summerSecondWeek:
        return 'summer';
      case AnnualLeaveBlockPeriodType.winter:
        return 'winter';
    }
  }

  DateTime _effectiveBlockPeriodStart(_AnnualLeaveBlockPeriod period) {
    final AnnualLeaveBlockOverride? override = _overrideForPeriod(period.type);

    return override?.overrideStartDate ?? period.start;
  }

  Set<DateTime> _excludedBlockWeekStarts(
    AnnualLeaveBlockPeriodType periodType,
  ) {
    final Set<DateTime> excluded = <DateTime>{};

    for (final _AnnualLeaveBlockPeriod period in _blockPeriods) {
      final bool sameGroup;

      switch (periodType) {
        case AnnualLeaveBlockPeriodType.spring:
          sameGroup = period.type == 'spring';
        case AnnualLeaveBlockPeriodType.summerFirstWeek:
        case AnnualLeaveBlockPeriodType.summerSecondWeek:
          sameGroup =
              period.type == 'summer_first_week' ||
              period.type == 'summer_second_week';
        case AnnualLeaveBlockPeriodType.winter:
          sameGroup = period.type == 'winter';
      }

      if (!sameGroup) {
        continue;
      }

      final DateTime start = _effectiveBlockPeriodStart(period);

      excluded.add(DateTime(start.year, start.month, start.day));
    }

    return excluded;
  }

  Future<_AnnualLeaveRosterWeekChoice?> _showAvailableBlockWeekPicker({
    required AnnualLeaveBlockPeriodType periodType,
  }) async {
    final String group = _blockWeekGroup(periodType);

    final List<dynamic> response = await Supabase.instance.client
        .from('annual_leave_roster_weeks')
        .select('week_start, week_end')
        .eq('leave_year', _leaveYear)
        .eq('period_group', group)
        .order('week_start');

    final Set<DateTime> excluded = _excludedBlockWeekStarts(periodType);

    final List<_AnnualLeaveRosterWeekChoice> choices = response
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> row) {
          final DateTime? start = DateTime.tryParse(
            (row['week_start'] ?? '').toString(),
          );
          final DateTime? end = DateTime.tryParse(
            (row['week_end'] ?? '').toString(),
          );

          if (start == null || end == null) {
            return null;
          }

          return _AnnualLeaveRosterWeekChoice(start: start, end: end);
        })
        .whereType<_AnnualLeaveRosterWeekChoice>()
        .where((choice) {
          final DateTime date = DateTime(
            choice.start.year,
            choice.start.month,
            choice.start.day,
          );

          return !excluded.contains(date);
        })
        .toList(growable: false)
        ..sort((a, b) => a.start.compareTo(b.start));

    if (!mounted) {
      return null;
    }

    if (choices.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'No available ${group.toLowerCase()} block weeks '
              'were found for $_leaveYear.',
            ),
          ),
        );

      return null;
    }

    return showModalBottomSheet<_AnnualLeaveRosterWeekChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.78,
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.calendar_view_week_outlined),
                  ),
                  title: Text(
                    periodType == AnnualLeaveBlockPeriodType.spring
                        ? 'Choose Spring week'
                        : periodType == AnnualLeaveBlockPeriodType.winter
                        ? 'Choose Winter week'
                        : 'Choose Summer week',
                    style: const TextStyle(
                      color: navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    periodType == AnnualLeaveBlockPeriodType.summerFirstWeek ||
                            periodType ==
                                AnnualLeaveBlockPeriodType.summerSecondWeek
                        ? '${choices.length} available weeks. '
                              'Your two existing Summer weeks are excluded.'
                        : '${choices.length} available weeks. '
                              'Your current week is excluded.',
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: choices.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final _AnnualLeaveRosterWeekChoice choice =
                          choices[index];

                      return ListTile(
                        leading: const Icon(
                          Icons.date_range_outlined,
                          color: railwayBlue,
                        ),
                        title: Text(
                          'Week commencing '
                          '${_displayDate(choice.start)}',
                          style: const TextStyle(
                            color: navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          'Ends ${_displayDate(choice.end)} '
                          '• Monday–Saturday',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(sheetContext).pop(choice);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBlockOverrideDialog(_AnnualLeaveBlockPeriod period) async {
    final AnnualLeaveBlockPeriodType? periodType = _blockPeriodType(
      period.type,
    );

    if (periodType == null) {
      return;
    }

    final AnnualLeaveBlockOverride? existing = _overrideForPeriod(period.type);

    DateTime selectedStart = existing?.overrideStartDate ?? period.start;

    DateTime selectedEnd = existing?.overrideEndDate ?? period.end;

    AnnualLeaveBlockChangeType changeType =
        existing?.changeType ?? AnnualLeaveBlockChangeType.agreedMove;

    final TextEditingController driverController = TextEditingController(
      text: existing?.swapDriverNumber ?? '',
    );

    final TextEditingController referenceController = TextEditingController(
      text: existing?.swapReference ?? '',
    );

    final TextEditingController notesController = TextEditingController(
      text: existing?.notes ?? '',
    );

    bool saving = false;
    String? errorMessage;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext sheetContext, void Function(void Function()) setSheetState) {
            Future<void> selectStart() async {
              final _AnnualLeaveRosterWeekChoice? selected =
                  await _showAvailableBlockWeekPicker(periodType: periodType);

              if (selected == null || !sheetContext.mounted) {
                return;
              }

              setSheetState(() {
                selectedStart = selected.start;
                selectedEnd = selected.end;
              });
            }

            Future<void> save() async {
              if (saving) {
                return;
              }

              if (selectedEnd.isBefore(selectedStart)) {
                setSheetState(() {
                  errorMessage =
                      'The block end date cannot be before the start date.';
                });
                return;
              }

              if (changeType == AnnualLeaveBlockChangeType.mutualSwap &&
                  driverController.text.trim().isEmpty) {
                setSheetState(() {
                  errorMessage =
                      'Enter the other driver number for a mutual swap.';
                });
                return;
              }

              setSheetState(() {
                saving = true;
                errorMessage = null;
              });

              try {
                final preparedEmail = await _buildBlockUnionEmail(
                  leaveYear: _leaveYear, blockNumber: _blockCycle?.weekIndex,
                  periodType: periodType, changeType: changeType,
                  originalStart: period.start, originalEnd: period.end,
                  proposedStart: selectedStart, proposedEnd: selectedEnd,
                  swapDriverNumber: changeType == AnnualLeaveBlockChangeType.mutualSwap ? driverController.text : null,
                  swapReference: referenceController.text, notes: notesController.text,
                );
                if (!sheetContext.mounted) return;
                Future<bool>? emailOpening;
                final bool? unionConfirmed = await showCupertinoModalPopup<bool>(
                  context: sheetContext,
                  builder: (BuildContext dialogContext) => CupertinoActionSheet(
                    title: const Text('Has this been actioned by the Union?'),
                    actions: <Widget>[
                      CupertinoActionSheetAction(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: Text(changeType == AnnualLeaveBlockChangeType.mutualSwap
                            ? 'Yes – action swap' : 'Yes – action change'),
                      ),
                      CupertinoActionSheetAction(
                        onPressed: () {
                          emailOpening = _openBlockUnionEmail(subject: preparedEmail.subject, body: preparedEmail.body);
                          Navigator.of(dialogContext).pop(false);
                        },
                        child: const Text('No – email the Union'),
                      ),
                    ],
                    cancelButton: CupertinoActionSheetAction(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                );

                if (unionConfirmed == null) {
                  if (sheetContext.mounted) {
                    setSheetState(() {
                      saving = false;
                    });
                  }
                  return;
                }

                if (unionConfirmed) {
                  await _annualLeaveBlockService.saveOverride(
                    leaveYear: _leaveYear,
                    periodType: periodType,
                    originalStartDate: period.start,
                    originalEndDate: period.end,
                    overrideStartDate: selectedStart,
                    overrideEndDate: selectedEnd,
                    changeType: changeType,
                    swapDriverNumber:
                        changeType == AnnualLeaveBlockChangeType.mutualSwap
                        ? driverController.text
                        : null,
                    swapReference: referenceController.text,
                    notes: notesController.text,
                  );
                } else {
                  final bool opened = await (emailOpening ?? Future<bool>.value(false));
                  if (!opened) {
                    if (sheetContext.mounted) {
                      setSheetState(() {
                        saving = false;
                        errorMessage = 'Roster Buddy could not open your email app. '
                            'Your block allocation has not changed. Please try again.';
                      });
                    }
                    return;
                  }
                  await _annualLeaveBlockPendingActionService.savePendingAction(
                    leaveYear: _leaveYear,
                    periodType: periodType,
                    changeType: changeType,
                    originalStartDate: period.start,
                    originalEndDate: period.end,
                    proposedStartDate: selectedStart,
                    proposedEndDate: selectedEnd,
                    swapDriverNumber: changeType == AnnualLeaveBlockChangeType.mutualSwap
                        ? driverController.text : null,
                    swapReference: referenceController.text,
                    notes: notesController.text,
                  );
                }

                if (!sheetContext.mounted) {
                  return;
                }

                Navigator.of(sheetContext).pop();
                widget.onRosterChanged?.call();

                if (unionConfirmed) {
                  await _load();
                }

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        unionConfirmed
                            ? '${_blockTypeLabel(period.type)} updated.'
                            : '${_blockTypeLabel(period.type)} saved to Pending Actions. '
                                  'Your current block allocation has not changed.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              } on AnnualLeaveBlockException catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  saving = false;
                  errorMessage = error.message;
                });
              } catch (_) {
                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  saving = false;
                  errorMessage =
                      'Roster Buddy could not save the block leave change.';
                });
              }
            }

            Future<void> restoreOriginal() async {
              if (existing == null || saving) {
                return;
              }

              setSheetState(() {
                saving = true;
                errorMessage = null;
              });

              try {
                if (period.isOfficial) {
                  await _annualLeaveBlockService.removeOverride(
                    leaveYear: _leaveYear,
                    periodType: periodType,
                  );
                } else {
                  await _annualLeaveBlockService.saveOverride(
                    leaveYear: _leaveYear,
                    periodType: periodType,
                    originalStartDate: period.start,
                    originalEndDate: period.end,
                    overrideStartDate: period.start,
                    overrideEndDate: period.end,
                    changeType: AnnualLeaveBlockChangeType.manual,
                  );
                }

                if (!sheetContext.mounted) {
                  return;
                }

                Navigator.of(sheetContext).pop();

                await _load();

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        period.isOfficial
                            ? '${_blockTypeLabel(period.type)} restored to '
                                  'the official Annual Leave Roster allocation.'
                            : '${_blockTypeLabel(period.type)} restored to '
                                  'the manually entered allocation.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              } catch (_) {
                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  saving = false;
                  errorMessage =
                      'Roster Buddy could not restore the original block.';
                });
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _blockTypeLabel(period.type),
                        style: const TextStyle(
                          color: navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${period.isOfficial ? 'Official' : 'Manual'} '
                        'allocation: '
                        '${_displayDate(period.start)} – '
                        '${_displayDate(period.end)}',
                        style: const TextStyle(color: textGrey, height: 1.35),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<AnnualLeaveBlockChangeType>(
                        value: changeType,
                        decoration: const InputDecoration(
                          labelText: 'Change type',
                          prefixIcon: Icon(Icons.swap_horiz_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: AnnualLeaveBlockChangeType.agreedMove,
                            child: Text('Agreed move'),
                          ),
                          DropdownMenuItem(
                            value: AnnualLeaveBlockChangeType.mutualSwap,
                            child: Text('Mutual swap'),
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (AnnualLeaveBlockChangeType? value) {
                                if (value != null) {
                                  setSheetState(() {
                                    changeType = value;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: saving ? null : selectStart,
                          icon: const Icon(Icons.calendar_view_week_outlined),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Choose replacement week\n'
                              'Week commencing '
                              '${_displayDate(selectedStart)}\n'
                              'Ends ${_displayDate(selectedEnd)} '
                              '• Monday–Saturday',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      if (changeType ==
                          AnnualLeaveBlockChangeType.mutualSwap) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: driverController,
                          enabled: !saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Other driver number',
                            helperText:
                                'Driver involved in the mutual block swap.',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: referenceController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Swap / agreement reference',
                          hintText: 'Optional',
                          prefixIcon: Icon(Icons.tag_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        enabled: !saving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Optional',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: leaveRed,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: saving ? null : save,
                          icon: saving
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            saving
                                ? 'Saving…'
                                : existing == null
                                ? 'Save block change'
                                : 'Update block change',
                          ),
                        ),
                      ),
                      if (existing != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: saving ? null : restoreOriginal,
                            icon: const Icon(Icons.restore_outlined),
                            label: Text(
                              period.isOfficial
                                  ? 'Restore official allocation'
                                  : 'Restore manual allocation',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    driverController.dispose();
    referenceController.dispose();
    notesController.dispose();
  }

  Widget _buildBlockLeaveCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x1AD64545),
              child: Icon(Icons.date_range_outlined, color: leaveRed),
            ),
            title: const Text(
              'Block annual leave',
              style: TextStyle(color: navy, fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              _blockCycle == null
                  ? 'Block allocation not set'
                  : 'Block ${_blockCycle!.weekIndex} • $_leaveYear',
            ),
            trailing: IconButton(
              tooltip: _blockCycle == null
                  ? 'Set block allocation'
                  : 'Change block allocation',
              onPressed: _showBlockCycleDialog,
              icon: Icon(
                _blockCycle == null ? Icons.add_outlined : Icons.edit_outlined,
              ),
            ),
          ),
          const Divider(height: 1),

          if (_blockPeriods.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No block dates available',
                    style: TextStyle(color: navy, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _blockCycle == null
                        ? 'Set your allocated block number first.'
                        : 'No official block dates have been found for '
                              '$_leaveYear. You can enter your four block '
                              'weeks manually until the Annual Leave Roster '
                              'is available.',
                    style: const TextStyle(color: textGrey, height: 1.4),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                children: [
                  for (final _AnnualLeaveBlockPeriod period in _blockPeriods)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showBlockOverrideDialog(period),
                      child: _buildBlockDateRow(period),
                    ),
                ],
              ),
            ),

          if (_blockCycle != null &&
              !_blockPeriods.any(
                (_AnnualLeaveBlockPeriod period) => period.isOfficial,
              )) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _showManualBlockDatesDialog,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: Text(
                    _blockPeriods.isEmpty
                        ? 'Enter manual block weeks'
                        : 'Edit manual block weeks',
                  ),
                ),
              ),
            ),
          ],

          if (_blockPeriods.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showBlockWeekPicker,
                  icon: const Icon(Icons.swap_horiz_outlined),
                  label: const Text('Move or swap a block week'),
                ),
              ),
            ),
          ],

          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              'Tap a block week for an agreed move or a mutual '
              'swap. Changes apply only to your own leave; the uploaded '
              'Annual Leave Roster remains unchanged.',
              style: TextStyle(color: textGrey, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockDateRow(_AnnualLeaveBlockPeriod period) {
    final AnnualLeaveBlockOverride? override = _overrideForPeriod(period.type);

    final DateTime displayedStart = override?.overrideStartDate ?? period.start;

    final DateTime displayedEnd = override?.overrideEndDate ?? period.end;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: leaveRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: leaveRed.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_available_outlined, color: leaveRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _blockTypeLabel(period.type),
                        style: const TextStyle(
                          color: navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (override != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: railwayBlue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _blockChangeLabel(override.changeType),
                          style: const TextStyle(
                            color: railwayBlue,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${_displayDate(displayedStart)} – '
                  '${_displayDate(displayedEnd)}',
                  style: const TextStyle(
                    color: navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  period.isOfficial
                      ? 'Official Annual Leave Roster'
                      : 'Manual allocation',
                  style: const TextStyle(color: textGrey, fontSize: 11),
                ),
                if (override != null && period.isOfficial) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Official: ${_displayDate(period.start)} – '
                    '${_displayDate(period.end)}',
                    style: const TextStyle(color: textGrey, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showBlockWeekPicker() async {
    if (_blockPeriods.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Edit block weeks',
                    style: TextStyle(
                      color: navy,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    'Choose the block week you want to move or swap.',
                  ),
                ),
                for (final _AnnualLeaveBlockPeriod period in _blockPeriods)
                  ListTile(
                    leading: const Icon(
                      Icons.date_range_outlined,
                      color: leaveRed,
                    ),
                    title: Text(
                      _blockTypeLabel(period.type),
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      '${_displayDate(_overrideForPeriod(period.type)?.overrideStartDate ?? period.start)} – '
                      '${_displayDate(_overrideForPeriod(period.type)?.overrideEndDate ?? period.end)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showBlockOverrideDialog(period);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequestsCard() {
    final List<AnnualLeaveRequest> allFloatingRequests = _requests.where((
      AnnualLeaveRequest request,
    ) {
      return request.requestType == AnnualLeaveRequestType.floating;
    }).toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    bool taken(AnnualLeaveRequest request) =>
        request.status == AnnualLeaveRequestStatus.granted &&
        !request.cancellationPending &&
        DateTime(request.leaveDate.year, request.leaveDate.month, request.leaveDate.day).isBefore(today);
    final takenRequests = allFloatingRequests.where(taken).toList()
      ..sort((a, b) => a.leaveDate.compareTo(b.leaveDate));
    final floatingRequests = allFloatingRequests.where((request) => !taken(request)).toList()
      ..sort((a, b) => a.leaveDate.compareTo(b.leaveDate));

    final int abeyanceCount = floatingRequests.where((
      AnnualLeaveRequest request,
    ) {
      return request.status == AnnualLeaveRequestStatus.abeyance;
    }).length;

    Widget requestRow(AnnualLeaveRequest request) => Column(
                children: [
                  ListTile(
                    leading: Icon(
                      _requestIcon(request),
                      color: _requestColour(request),
                    ),
                    title: Text(
                      _displayDate(request.leaveDate),
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (request.notes?.trim().isNotEmpty == true)
                          Text(request.notes!.trim()),
                        if (request.status ==
                                AnnualLeaveRequestStatus.abeyance &&
                            request.queuePosition != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              'Queue position ${request.queuePosition}',
                              style: const TextStyle(
                                color: abeyanceAmber,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _requestColour(
                              request,
                            ).withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _requestStatusLabel(request),
                            style: TextStyle(
                              color: _requestColour(request),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (request.status !=
                            AnnualLeaveRequestStatus.cancelled) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: textGrey),
                        ],
                      ],
                    ),
                    onTap: request.status == AnnualLeaveRequestStatus.granted
                        ? () => _showGrantedFloatingDetails(request)
                        : () => _showRequestActions(request),
                  ),
                  const Divider(height: 1),
                ],);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x1A1769AA),
              child: Icon(Icons.list_alt_outlined, color: railwayBlue),
            ),
            title: const Text(
              'Floating leave requests',
              style: TextStyle(color: navy, fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              abeyanceCount == 0
                  ? 'Requested, abeyance and granted days'
                  : '$abeyanceCount day${abeyanceCount == 1 ? '' : 's'} '
                        'currently in abeyance',
            ),
          ),
          const Divider(height: 1),
          if (floatingRequests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'You have no active floating annual leave requests '
                'for this leave year.',
                style: TextStyle(color: textGrey, height: 1.4),
              ),
            )
          else
            ...floatingRequests.map(requestRow),
          if (takenRequests.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showTakenDays = !_showTakenDays),
                icon: Icon(_showTakenDays ? Icons.expand_less : Icons.expand_more),
                label: const Text('Days already taken'),
              ),
            ),
            if (_showTakenDays) ...takenRequests.map(requestRow),
          ],
          if (floatingRequests.any((r) => r.status == AnnualLeaveRequestStatus.granted))
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: _selectFloatingCancellations,
                icon: const Icon(Icons.checklist),
                label: const Text('Cancel / action multiple dates'),
              ),
            ),
          if (floatingRequests.isNotEmpty) ...[
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Tap granted leave to cancel or action a pending cancellation. '
                'Use Cancel / action multiple dates to prepare one email for several days.',
                style: TextStyle(color: textGrey, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }


  Future<void> _manageFloatingCancellations(List<AnnualLeaveRequest> requests) async {
    final changed = await manageFloatingLeaveCancellation(context: context, requests: requests);
    if (changed && mounted) {
      widget.onRosterChanged?.call();
      await _load();
    }
  }

  Future<void> _showGrantedFloatingDetails(AnnualLeaveRequest request) async {
    final cancel = await showModalBottomSheet<bool>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(MaterialLocalizations.of(context).formatFullDate(request.leaveDate),
            style: const TextStyle(color: navy, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          const Row(children: [
            Icon(Icons.circle, size: 12, color: leaveRed), SizedBox(width: 8),
            Text('Annual Leave', style: TextStyle(color: navy, fontSize: 20, fontWeight: FontWeight.w800)),
            Spacer(), Chip(label: Text('ALD')),
          ]),
          const SizedBox(height: 18),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: leaveRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: leaveRed.withValues(alpha: 0.35))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(request.cancellationPending ? 'Cancellation pending' : 'Annual leave granted',
                style: const TextStyle(color: leaveRed, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(request.cancellationPending
                ? 'Leave stays granted until Rosters confirms cancellation.'
                : 'This annual leave request has been granted.',
                style: const TextStyle(color: textGrey)),
            ]),
          ),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(sheetContext, true),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(request.cancellationPending ? 'Action pending cancellation' : 'Cancel annual leave'),
            style: OutlinedButton.styleFrom(foregroundColor: leaveRed),
          )),
        ]),
      )),
    );
    if (cancel != true || !mounted) return;
    final scope = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(request.cancellationPending ? 'Action cancellation' : 'Cancel annual leave'),
        message: Text(MaterialLocalizations.of(context).formatFullDate(request.leaveDate)),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(popupContext, 'single'),
            child: const Text('Just this date')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(popupContext, 'multiple'),
            child: const Text('Multiple dates')),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext), child: const Text('Back')),
      ),
    );
    if (!mounted) return;
    if (scope == 'single') await _manageFloatingCancellations([request]);
    if (scope == 'multiple') await _selectFloatingCancellations(initialRequest: request);
  }

  Future<void> _selectFloatingCancellations({AnnualLeaveRequest? initialRequest}) async {
    final available = _requests.where((r) =>
        r.requestType == AnnualLeaveRequestType.floating &&
        r.status == AnnualLeaveRequestStatus.granted).toList();
    final selected = <String>{if (initialRequest != null) initialRequest.id};
    final confirmed = await showModalBottomSheet<bool>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Select floating leave dates',
              style: TextStyle(color: navy, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: available.map((r) => CheckboxListTile(
                  value: selected.contains(r.id),
                  title: Text(_displayDate(r.leaveDate)),
                  subtitle: Text(r.cancellationPending ? 'Pending cancellation' : 'Granted'),
                  onChanged: (value) => setSheetState(() {
                    if (value == true) { selected.add(r.id); } else { selected.remove(r.id); }
                  }),
                )).toList(),
              )),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(sheetContext, true),
              child: Text('Continue (${selected.length})')),
            TextButton(onPressed: () => Navigator.pop(sheetContext, false), child: const Text('Back')),
          ]),
        )),
      ),
    );
    if (confirmed == true && mounted) {
      await _manageFloatingCancellations(available.where((r) => selected.contains(r.id)).toList());
    }
  }

  Future<void> _showRequestActions(AnnualLeaveRequest request) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final bool inAbeyance =
            request.status == AnnualLeaveRequestStatus.abeyance;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    _displayDate(request.leaveDate),
                    style: const TextStyle(
                      color: navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(_requestStatusLabel(request)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.event_available_outlined,
                    color: leaveRed,
                  ),
                  title: const Text('Mark granted'),
                  subtitle: const Text(
                    'Confirm that Rosters has granted this leave.',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _markRequestGranted(request);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.hourglass_top_outlined,
                    color: abeyanceAmber,
                  ),
                  title: Text(
                    inAbeyance
                        ? 'Change abeyance position'
                        : 'Move to abeyance',
                  ),
                  subtitle: const Text(
                    'Record your current position in the waiting list.',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showAbeyanceDialog(request);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: leaveRed),
                  title: const Text('Cancel request'),
                  subtitle: const Text(
                    'Return this floating day to your available balance.',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _cancelFloatingRequest(request);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAbeyanceDialog(AnnualLeaveRequest request) async {
    final TextEditingController controller = TextEditingController(
      text: request.queuePosition?.toString() ?? '',
    );

    String? errorMessage;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext sheetContext,
                void Function(void Function()) setSheetState,
              ) {
                Future<void> save() async {
                  final int? position = int.tryParse(controller.text.trim());

                  if (position == null || position < 1) {
                    setSheetState(() {
                      errorMessage =
                          'Enter an abeyance queue position of 1 or greater.';
                    });
                    return;
                  }

                  setSheetState(() {
                    saving = true;
                    errorMessage = null;
                  });

                  try {
                    await _annualLeaveService.markAbeyance(
                      requestId: request.id,
                      queuePosition: position,
                    );

                    if (!sheetContext.mounted) {
                      return;
                    }

                    Navigator.of(sheetContext).pop();

                    await _load();

                    if (!mounted) {
                      return;
                    }

                    _showAnnualLeaveMessage(
                      '${_displayDate(request.leaveDate)} moved to '
                      'abeyance position $position.',
                    );
                  } on AnnualLeaveException catch (error) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      saving = false;
                      errorMessage = error.message;
                    });
                  } catch (_) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      saving = false;
                      errorMessage =
                          'Roster Buddy could not update this request.';
                    });
                  }
                }

                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Annual leave abeyance',
                          style: TextStyle(
                            color: navy,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _displayDate(request.leaveDate),
                          style: const TextStyle(color: textGrey),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: controller,
                          enabled: !saving,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Queue position',
                            hintText: 'For example 2',
                            prefixIcon: Icon(
                              Icons.format_list_numbered_outlined,
                            ),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: leaveRed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: saving ? null : save,
                            icon: saving
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              saving ? 'Saving…' : 'Save abeyance position',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _markRequestGranted(AnnualLeaveRequest request) async {
    final bool confirmed = await _confirmAnnualLeaveAction(
      title: 'Mark annual leave granted?',
      message:
          'Confirm that annual leave for '
          '${_displayDate(request.leaveDate)} has been granted.',
      confirmLabel: 'Mark granted',
    );

    if (!confirmed) {
      return;
    }

    try {
      await _annualLeaveService.markGranted(requestId: request.id);
      await _load();

      if (!mounted) {
        return;
      }

      _showAnnualLeaveMessage(
        '${_displayDate(request.leaveDate)} marked as granted.',
      );
    } on AnnualLeaveException catch (error) {
      _showAnnualLeaveMessage(error.message);
    } catch (_) {
      _showAnnualLeaveMessage(
        'Roster Buddy could not mark this annual leave as granted.',
      );
    }
  }

  Future<void> _cancelFloatingRequest(AnnualLeaveRequest request) async {
    final bool confirmed = await _confirmAnnualLeaveAction(
      title: 'Cancel annual leave request?',
      message:
          'Cancel the annual leave request for '
          '${_displayDate(request.leaveDate)}? The day will return to '
          'your available floating balance.',
      confirmLabel: 'Cancel request',
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await _annualLeaveService.cancelRequest(requestId: request.id);
      await _load();

      if (!mounted) {
        return;
      }

      _showAnnualLeaveMessage(
        '${_displayDate(request.leaveDate)} request cancelled.',
      );
    } on AnnualLeaveException catch (error) {
      _showAnnualLeaveMessage(error.message);
    } catch (_) {
      _showAnnualLeaveMessage(
        'Roster Buddy could not cancel this annual leave request.',
      );
    }
  }

  Widget _buildScheduledRequestsCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(0x1AF59E0B),
              child: Icon(Icons.schedule_send_outlined, color: abeyanceAmber),
            ),
            title: Text(
              'Scheduled annual leave',
              style: TextStyle(color: navy, fontWeight: FontWeight.w900),
            ),
            subtitle: Text('Requests more than 365 days ahead'),
          ),
          const Divider(height: 1),
          if (_scheduledRequests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'You have no annual leave requests waiting for the '
                '365-day send window in this leave year.',
                style: TextStyle(color: textGrey, height: 1.4),
              ),
            )
          else
            ..._scheduledRequests.map((Map<String, dynamic> scheduled) {
              final DateTime? leaveDate = _scheduledLeaveDate(scheduled);
              final DateTime? scheduledFor = _scheduledLeaveSendDate(scheduled);

              if (leaveDate == null) {
                return const SizedBox.shrink();
              }

              final String notes = (scheduled['notes'] ?? '').toString().trim();

              return Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.schedule_send_outlined,
                      color: abeyanceAmber,
                    ),
                    title: Text(
                      _displayDate(leaveDate),
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (scheduledFor != null)
                          'Scheduled to send '
                              '${_displayDate(scheduledFor.toLocal())}',
                        if (notes.isNotEmpty) notes,
                      ].join('\n'),
                    ),
                    trailing: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'QUEUED',
                          style: TextStyle(
                            color: abeyanceAmber,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right, color: textGrey),
                      ],
                    ),
                    onTap: () =>
                        _showScheduledRequestActions(scheduled, leaveDate),
                  ),
                  if (scheduled != _scheduledRequests.last)
                    const Divider(height: 1),
                ],
              );
            }),
          if (_scheduledRequests.isNotEmpty) ...[
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Queued requests do not use a floating day until they are '
                'actually sent. If Rosters grants a queued date before then, '
                'use Confirm granted to record it immediately and remove the '
                'email from the send queue.',
                style: TextStyle(color: textGrey, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showScheduledRequestActions(
    Map<String, dynamic> scheduled,
    DateTime leaveDate,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    _displayDate(leaveDate),
                    style: const TextStyle(
                      color: navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: const Text('Scheduled annual leave request'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.event_available_outlined,
                    color: leaveRed,
                  ),
                  title: const Text('Confirm granted'),
                  subtitle: const Text(
                    'Record the leave as granted and remove the queued email.',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _confirmScheduledLeaveGranted(leaveDate);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: leaveRed),
                  title: const Text('Cancel queued request'),
                  subtitle: const Text(
                    'Remove this email from the future send queue.',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _cancelScheduledLeave(leaveDate);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmScheduledLeaveGranted(DateTime leaveDate) async {
    final bool confirmed = await _confirmAnnualLeaveAction(
      title: 'Confirm annual leave granted?',
      message:
          'This will mark ${_displayDate(leaveDate)} as granted and remove '
          'its scheduled email from the send queue.',
      confirmLabel: 'Confirm granted',
    );

    if (!confirmed) {
      return;
    }

    try {
      await _annualLeaveService.confirmScheduledFloatingLeaveGranted(
        date: leaveDate,
      );

      await _load();

      if (!mounted) {
        return;
      }

      _showAnnualLeaveMessage(
        '${_displayDate(leaveDate)} confirmed as granted.',
      );
    } on AnnualLeaveException catch (error) {
      _showAnnualLeaveMessage(error.message);
    } catch (_) {
      _showAnnualLeaveMessage(
        'Roster Buddy could not confirm this annual leave.',
      );
    }
  }

  Future<void> _cancelScheduledLeave(DateTime leaveDate) async {
    final bool confirmed = await _confirmAnnualLeaveAction(
      title: 'Cancel queued annual leave?',
      message:
          'The scheduled annual leave request for '
          '${_displayDate(leaveDate)} will be removed from the send queue.',
      confirmLabel: 'Cancel request',
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await _annualLeaveService.cancelScheduledFloatingLeaveRequest(
        date: leaveDate,
      );

      await _load();

      if (!mounted) {
        return;
      }

      _showAnnualLeaveMessage(
        '${_displayDate(leaveDate)} removed from the send queue.',
      );
    } on AnnualLeaveException catch (error) {
      _showAnnualLeaveMessage(error.message);
    } catch (_) {
      _showAnnualLeaveMessage(
        'Roster Buddy could not cancel this queued request.',
      );
    }
  }

  DateTime? _scheduledLeaveDate(Map<String, dynamic> row) {
    return DateTime.tryParse((row['leave_date'] ?? '').toString());
  }

  DateTime? _scheduledLeaveSendDate(Map<String, dynamic> row) {
    return DateTime.tryParse((row['scheduled_for'] ?? '').toString());
  }

  Future<bool> _confirmAnnualLeaveAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final bool? result = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Back'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: destructive
                  ? TextButton.styleFrom(foregroundColor: leaveRed)
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  void _showAnnualLeaveMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: leaveRed, size: 36),
            const SizedBox(height: 10),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: textGrey, height: 1.4),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  String _requestStatusLabel(AnnualLeaveRequest request) {
    if (request.cancellationPending) return 'PENDING CANCELLATION';
    switch (request.status) {
      case AnnualLeaveRequestStatus.requested:
        return 'REQUESTED';

      case AnnualLeaveRequestStatus.abeyance:
        if (request.queuePosition != null) {
          return 'ABEYANCE #${request.queuePosition}';
        }

        return 'ABEYANCE';

      case AnnualLeaveRequestStatus.granted:
        return 'GRANTED';

      case AnnualLeaveRequestStatus.cancelled:
        return 'CANCELLED';
    }
  }

  Color _requestColour(AnnualLeaveRequest request) {
    switch (request.status) {
      case AnnualLeaveRequestStatus.requested:
        return railwayBlue;
      case AnnualLeaveRequestStatus.abeyance:
        return abeyanceAmber;
      case AnnualLeaveRequestStatus.granted:
        return leaveRed;
      case AnnualLeaveRequestStatus.cancelled:
        return textGrey;
    }
  }

  IconData _requestIcon(AnnualLeaveRequest request) {
    switch (request.status) {
      case AnnualLeaveRequestStatus.requested:
        return Icons.schedule_outlined;
      case AnnualLeaveRequestStatus.abeyance:
        return Icons.hourglass_top_outlined;
      case AnnualLeaveRequestStatus.granted:
        return Icons.event_available_outlined;
      case AnnualLeaveRequestStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  String _blockPeriodEmailLabel(AnnualLeaveBlockPeriodType type) {
    switch (type) {
      case AnnualLeaveBlockPeriodType.spring:
        return 'Spring';
      case AnnualLeaveBlockPeriodType.summerFirstWeek:
        return 'Summer Week 1';
      case AnnualLeaveBlockPeriodType.summerSecondWeek:
        return 'Summer Week 2';
      case AnnualLeaveBlockPeriodType.winter:
        return 'Winter';
    }
  }

  String _blockChangeEmailLabel(AnnualLeaveBlockChangeType type) {
    switch (type) {
      case AnnualLeaveBlockChangeType.manual:
        return 'Manual allocation';
      case AnnualLeaveBlockChangeType.agreedMove:
        return 'Block leave exchange request';
      case AnnualLeaveBlockChangeType.mutualSwap:
        return 'Mutual block leave swap';
    }
  }

  Future<Map<String, String>> _blockRequestIdentity() async {
    final SupabaseClient supabase = Supabase.instance.client;
    final User? user = supabase.auth.currentUser;

    if (user == null) {
      return <String, String>{};
    }

    final Map<String, dynamic>? profile = await supabase
        .from('driver_profiles')
        .select('display_name, depot, driver_number, payroll_number')
        .eq('user_id', user.id)
        .maybeSingle();

    final Map<String, dynamic> metadata =
        user.userMetadata ?? <String, dynamic>{};

    return <String, String>{
      'name': (profile?['display_name'] ?? metadata['full_name'] ?? '')
          .toString()
          .trim(),
      'depot': (profile?['depot'] ?? metadata['depot'] ?? '').toString().trim(),
      'driverNumber':
          (profile?['driver_number'] ?? metadata['driver_number'] ?? '')
              .toString()
              .trim(),
      'payrollNumber':
          (profile?['payroll_number'] ?? metadata['payroll_number'] ?? '')
              .toString()
              .trim(),
    };
  }

  Future<({String subject, String body})> _buildBlockUnionEmail({
    required int leaveYear,
    required int? blockNumber,
    required AnnualLeaveBlockPeriodType periodType,
    required AnnualLeaveBlockChangeType changeType,
    required DateTime originalStart,
    required DateTime originalEnd,
    required DateTime proposedStart,
    required DateTime proposedEnd,
    String? swapDriverNumber,
    String? swapReference,
    String? notes,
  }) async {
    final Map<String, String> identity = await _blockRequestIdentity();

    final String periodLabel = _blockPeriodEmailLabel(periodType);
    final String changeLabel = _blockChangeEmailLabel(changeType);

    final String subject =
        '$leaveYear ${blockNumber == null ? 'Block leave' : 'Block $blockNumber'} – $periodLabel – $changeLabel';

    final List<String> lines = <String>[
      'Hello,',
      '',
      changeType == AnnualLeaveBlockChangeType.mutualSwap
          ? 'Please can you record the following mutual block annual leave swap.'
          : 'Please can you consider moving my block annual leave to the dates below. '
            'This is not a mutual swap with another driver.',
      '',
      'Leave year: $leaveYear',
      if (blockNumber != null) 'Block: $blockNumber',
      'Period: $periodLabel',
      'Current dates: ${_displayDate(originalStart)} to ${_displayDate(originalEnd)}',
      'Requested dates: ${_displayDate(proposedStart)} to ${_displayDate(proposedEnd)}',
      if (changeType == AnnualLeaveBlockChangeType.mutualSwap &&
          swapDriverNumber?.trim().isNotEmpty == true)
        'Other driver number: ${swapDriverNumber!.trim()}',
      if (swapReference?.trim().isNotEmpty == true)
        'Swap / agreement reference: ${swapReference!.trim()}',
      if (notes?.trim().isNotEmpty == true) 'Notes: ${notes!.trim()}',
      '',
      if (identity['driverNumber']?.isNotEmpty == true)
        'Driver Number: ${identity['driverNumber']}',
      if (identity['payrollNumber']?.isNotEmpty == true)
        'Payroll Number: ${identity['payrollNumber']}',
      if (identity['depot']?.isNotEmpty == true) identity['depot']!,
    ];

    return (subject: subject, body: lines.join('\n'));
  }

  Future<bool> _openBlockUnionEmail({
    required String subject,
    required String body,
  }) async {
    final Uri uri = Uri.parse(
      'mailto:wolves.driversllc@wmtrains.co.uk'
      '?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}',
    );

    return launchUrl(uri, webOnlyWindowName: '_self');
  }

  String _blockTypeLabel(String value) {
    switch (value) {
      case 'spring':
        return 'Spring block';
      case 'summer_first_week':
        return 'Summer block – first week';
      case 'summer_second_week':
        return 'Summer block – second week';
      case 'winter':
        return 'Winter block';
      default:
        return 'Block annual leave';
    }
  }

  String _displayDate(DateTime date) {
    return displayDate(date);
  }

  static String _databaseDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }
}

class _AnnualLeaveRosterWeekChoice {
  const _AnnualLeaveRosterWeekChoice({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _AnnualLeaveBlockPeriod {
  const _AnnualLeaveBlockPeriod({
    required this.type,
    required this.start,
    required this.end,
    this.isOfficial = true,
  });

  final String type;
  final DateTime start;
  final DateTime end;
  final bool isOfficial;
}

class _AnnualLeaveSummaryRow extends StatelessWidget {
  const _AnnualLeaveSummaryRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: const Color(0xFF52667A),
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: const Color(0xFF102A43),
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
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
  final TextEditingController _rosterCodeController = TextEditingController();
  final TextEditingController _payrollNumberController =
      TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _permanentlyUnavailableSundays = false;
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
    _rosterCodeController.dispose();
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
    _rosterCodeController.text = (metadata['roster_number'] ?? '').toString();
    _payrollNumberController.text = (metadata['payroll_number'] ?? '')
        .toString();

    try {
      final Map<String, dynamic>? profile = await supabase
          .from('driver_profiles')
          .select(
            'display_name, depot, driver_number, roster_number, payroll_number, '
            'permanently_unavailable_sundays',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      if (profile != null) {
        _nameController.text = (profile['display_name'] ?? '').toString();
        _depotController.text = (profile['depot'] ?? '').toString();
        _driverNumberController.text = (profile['driver_number'] ?? '')
            .toString();
        _rosterCodeController.text = (profile['roster_number'] ?? '').toString();
        _payrollNumberController.text = (profile['payroll_number'] ?? '')
            .toString();

        _permanentlyUnavailableSundays =
            profile['permanently_unavailable_sundays'] == true;
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
    final String rosterCode = _rosterCodeController.text.trim();
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
        'roster_number': rosterCode,
        'payroll_number': payrollNumber,
        'permanently_unavailable_sundays': _permanentlyUnavailableSundays,
      }, onConflict: 'user_id');

      try {
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'full_name': displayName,
              'depot': depot,
              'driver_number': driverNumber,
        'roster_number': rosterCode,
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
            'That Driver Number is already linked to another Roster Buddy '
            'account.',
            isError: true,
          );
        } else {
          _showMessage(
            'That payroll number or Driver Number is already linked to '
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
                          controller: _rosterCodeController,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Roster Code',
                            helperText: 'Used to find your line on the Base Roster.',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => _requiredNumber(value, 'Roster Code'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _driverNumberController,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Driver Number',
                            helperText:
                                'Your Driver Number, used on Annual Leave Rosters and emails.',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              _requiredNumber(value, 'Driver Number'),
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
                              style: TextStyle(
                                color: navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: const Text(
                              'Keep this on if you are normally unavailable '
                              'for Sunday work. You can still volunteer for '
                              'an individual Sunday later.',
                            ),
                          ),
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
    _loadSavedSetup();
  }

  Future<void> _loadSavedSetup() async {
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
            'swap_partner_roster_number, swap_partner_driver_number, '
            'base_roster_starts_with_line',
          )
          .eq('user_id', user.id)
          .maybeSingle();
    } catch (_) {
      profile = null;
    }

    final String storedDate =
        (profile?['base_roster_commencement_date'] ??
                metadata['base_roster_commencement_date'] ??
                '')
            .toString()
            .trim();

    final bool hasMutualSwap =
        profile != null && profile['has_mutual_roster_swap'] != null
        ? profile['has_mutual_roster_swap'] == true
        : metadata['has_mutual_swap'] == true;

    final String swapPartner =
        (profile?['swap_partner_roster_number'] ??
                profile?['swap_partner_driver_number'] ??
                metadata['swap_partner_roster_number'] ??
                metadata['swap_partner_driver_number'] ??
                '')
            .toString()
            .trim();

    final String storedFirstLine =
        (profile?['base_roster_starts_with_line'] ??
                metadata['mutual_swap_first_line'] ??
                '')
            .toString()
            .trim();

    if (!mounted) {
      return;
    }

    setState(() {
      _commencementDate = storedDate.isEmpty
          ? null
          : DateTime.tryParse(storedDate);
      _hasMutualSwap = hasMutualSwap;
      _swapPartnerController.text = hasMutualSwap ? swapPartner : '';
      _firstLine =
          hasMutualSwap &&
              (storedFirstLine == 'partner' ||
                  storedFirstLine == 'swap_partner_line' ||
                  storedFirstLine == 'partner_line')
          ? 'swap_partner_line'
          : 'my_line';
    });
  }

  @override
  void dispose() {
    _swapPartnerController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return displayDate(date);
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
      final SupabaseClient supabase = Supabase.instance.client;
      final User? user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('You must be signed in to save Base Roster setup.');
      }

      final String commencementDate = _storageDate(_commencementDate!);
      final String? swapPartner = _hasMutualSwap
          ? _swapPartnerController.text.trim()
          : null;
      final String profileStartingLine =
          _hasMutualSwap && _firstLine == 'swap_partner_line'
          ? 'partner'
          : 'mine';

      await supabase
          .from('driver_profiles')
          .update({
            'base_roster_commencement_date': commencementDate,
            'has_mutual_roster_swap': _hasMutualSwap,
            'swap_partner_roster_number': swapPartner,
            'base_roster_starts_with_line': profileStartingLine,
          })
          .eq('user_id', user.id);

      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'base_roster_commencement_date': commencementDate,
            'has_mutual_swap': _hasMutualSwap,
            'swap_partner_roster_number': swapPartner,
            'mutual_swap_first_line': _hasMutualSwap ? _firstLine : 'my_line',
          },
        ),
      );

      final reprocessResult = await StorageService.reprocessActiveBaseRoster(
        commencementDate: _commencementDate!,
        hasMutualSwap: _hasMutualSwap,
        swapPartnerRosterNumber: swapPartner,
        startsWithPartner: _hasMutualSwap && _firstLine == 'swap_partner_line',
      );

      if (!mounted) {
        return;
      }

      final String saveMessage;

      if (reprocessResult == null) {
        saveMessage =
            'Base Roster setup saved. It will be used when a Base Roster is uploaded.';
      } else if (reprocessResult.wasProcessed) {
        saveMessage = 'Base Roster setup saved and roster updated.';
      } else {
        saveMessage =
            'Base Roster setup saved. The roster update will complete in the native app.';
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(saveMessage)));

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

