import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/duty.dart';
import '../../core/models/duty_type.dart';
import '../../core/models/roster_source.dart';
import '../../core/services/duty_resolver.dart';
import '../upload/base_roster_activation_page.dart';
import '../upload/storage_service.dart';
import '../upload/upload_service.dart';
import '../smart_scan/smart_scan_debug_page.dart';
import '../settings/settings_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);

  int _selectedIndex = 0;
  int _dashboardRefreshVersion = 0;

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _pickDocument(UploadSource source) async {
    try {
      final PickedUpload? picked = await UploadService.pickDocument(source);

      if (picked == null || !mounted) {
        return;
      }

      await _showSmartScanDialog(picked);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Unable to open the document picker: $error')),
        );
    }
  }

  String? _detectDocumentType(String fileName) {
    final String name = fileName.toLowerCase();

    if (name.contains('annual') && name.contains('leave')) {
      return 'Annual Leave Roster';
    }

    if (name.contains('job') && name.contains('card')) {
      return 'Job Card';
    }

    if (name.contains('48')) {
      return '48-Hour Amendment';
    }

    if (name.contains('10')) {
      return '10-Day Amendment';
    }

    if (name.contains('7')) {
      return '7-Day Amendment';
    }

    if (name.contains('base')) {
      return 'Base Roster';
    }

    return null;
  }

  Future<void> _showSmartScanDialog(PickedUpload picked) async {
    final String fileName = picked.fileName;

    const List<String> documentTypes = [
      'Base Roster',
      '10-Day Amendment',
      '7-Day Amendment',
      '48-Hour Amendment',
      'Job Card',
      'Annual Leave Roster',
    ];

    final String? detectedType = _detectDocumentType(fileName);
    String? selectedType = detectedType;

    final String? confirmedType = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    detectedType == null
                        ? Icons.help_outline
                        : Icons.auto_awesome_outlined,
                    color: railwayBlue,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Smart Scan')),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      detectedType == null
                          ? 'Smart Scan is not certain what type of document this is. Please label it manually.'
                          : 'Smart Scan thinks this is a $detectedType. Confirm or change the document type.',
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Document type',
                        border: OutlineInputBorder(),
                      ),
                      items: documentTypes
                          .map(
                            (type) => DropdownMenuItem<String>(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedType = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selectedType == null
                      ? null
                      : () {
                          Navigator.pop(dialogContext, selectedType);
                        },
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmedType == null || !mounted) return;

    final bool manuallyLabelled =
        detectedType == null || confirmedType != detectedType;

    final bool? continueAfterScan = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SmartScanDebugPage(
          bytes: picked.bytes,
          fileName: picked.fileName,
          documentType: confirmedType,
        ),
      ),
    );

    if (continueAfterScan != true || !mounted) {
      return;
    }

    BaseRosterActivation? baseRosterActivation;

    if (confirmedType == 'Base Roster') {
      baseRosterActivation = await Navigator.of(context)
          .push<BaseRosterActivation>(
            MaterialPageRoute(
              builder: (context) =>
                  BaseRosterActivationPage(fileName: picked.fileName),
            ),
          );

      if (baseRosterActivation == null || !mounted) {
        return;
      }
    }

    final bool uploaded = await UploadService.uploadPickedDocument(
      context,
      picked,
      detectedType: confirmedType,
      manuallyLabelled: manuallyLabelled,
      baseRosterActivation: baseRosterActivation,
    );

    if (!uploaded || !mounted) return;

    setState(() {
      _dashboardRefreshVersion++;
      _selectedIndex = 0;
    });
  }

  void _openUploadPage() {
    _pickDocument(UploadSource.file);
  }

  @override
  Widget build(BuildContext context) {
    final String email =
        Supabase.instance.client.auth.currentUser?.email ?? 'Roster Buddy user';

    final List<Widget> pages = [
      DashboardPage(
        email: email,
        onUpload: _openUploadPage,
        refreshVersion: _dashboardRefreshVersion,
      ),
      const CalendarPage(),
      DashboardPage(
        email: email,
        onUpload: _openUploadPage,
        refreshVersion: _dashboardRefreshVersion,
      ),
      const TimelinePage(),
      AppSettingsPage(email: email, onSignOut: _signOut),
    ];

    const List<String> titles = [
      'Roster Buddy',
      'Calendar',
      'Upload',
      'Timeline',
      'Settings',
    ];

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        foregroundColor: navy,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.train, color: railwayBlue),
            const SizedBox(width: 10),
            Text(
              titles[_selectedIndex],
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) async {
          if (index == 2) {
            await _pickDocument(UploadSource.file);
            return;
          }

          setState(() {
            _selectedIndex = index;
          });
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
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: 'Timeline',
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
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.email,
    required this.onUpload,
    required this.refreshVersion,
    super.key,
  });

  final String email;
  final VoidCallback onUpload;
  final int refreshVersion;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color workingGreen = Color(0xFF2E7D32);
  static const Color restYellow = Color(0xFFFFD54F);
  static const Color leaveRed = Color(0xFFD64545);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color textGrey = Color(0xFF52667A);

  final DutyResolver _dutyResolver = DutyResolver();

  Duty? _todayDuty;
  Duty? _nextWorkingDuty;

  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDashboardDuties();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _loadDashboardDuties();
    }
  }

  Future<void> _loadDashboardDuties() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);

      final Duty? todayDuty = await _dutyResolver.getDutyForDate(today);
      Duty? nextWorkingDuty;

      // Start tomorrow so today's duty is not repeated in both cards.
      for (int offset = 1; offset <= 370; offset++) {
        final DateTime date = today.add(Duration(days: offset));
        final Duty? duty = await _dutyResolver.getDutyForDate(date);

        if (duty != null && duty.dutyType.countsAsWorking) {
          nextWorkingDuty = duty;
          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _todayDuty = todayDuty;
        _nextWorkingDuty = nextWorkingDuty;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _todayDuty = null;
        _nextWorkingDuty = null;
        _isLoading = false;
        _loadError = error is DutyResolverException
            ? error.message
            : 'Roster Buddy could not load your roster.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadDashboardDuties,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Welcome back',
                style: TextStyle(
                  color: navy,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(widget.email, style: const TextStyle(color: textGrey)),
              const SizedBox(height: 22),

              const SectionTitle(icon: Icons.today_outlined, title: 'Today'),
              const SizedBox(height: 10),
              _buildTodayCard(),

              const SizedBox(height: 22),
              const SectionTitle(
                icon: Icons.train_outlined,
                title: "Next shift I'm working",
              ),
              const SizedBox(height: 10),
              _buildNextShiftCard(),

              const SizedBox(height: 22),
              const SectionTitle(
                icon: Icons.verified_outlined,
                title: 'Latest roster source',
              ),
              const SizedBox(height: 10),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SourceBadge(label: '10D'),
                  SourceBadge(label: '7D'),
                  SourceBadge(label: '48HR'),
                  SourceBadge(label: 'M'),
                  SourceBadge(label: 'AW'),
                ],
              ),

              const SizedBox(height: 22),
              const SectionTitle(
                icon: Icons.calendar_view_week_outlined,
                title: 'This week',
              ),
              const SizedBox(height: 10),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: DayTile(
                          day: 'Sun',
                          status: 'Rest',
                          colour: restYellow,
                          darkText: true,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: DayTile(
                          day: 'Mon',
                          status: 'Duty',
                          colour: workingGreen,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: DayTile(
                          day: 'Tue',
                          status: 'Duty',
                          colour: workingGreen,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: DayTile(
                          day: 'Wed',
                          status: 'Duty',
                          colour: workingGreen,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: DayTile(
                          day: 'Thu',
                          status: 'Rest',
                          colour: restYellow,
                          darkText: true,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: DayTile(
                          day: 'Fri',
                          status: 'Leave',
                          colour: leaveRed,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: DayTile(
                          day: 'Sat',
                          status: 'Rest',
                          colour: restYellow,
                          darkText: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),
              const SectionTitle(
                icon: Icons.bolt_outlined,
                title: 'Quick actions',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: QuickAction(
                      icon: Icons.upload_file,
                      label: 'Upload roster',
                      onTap: widget.onUpload,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: QuickAction(
                      icon: Icons.event_available_outlined,
                      label: 'Request leave',
                      onTap: () {
                        showMessage(
                          context,
                          'Annual leave requests will be added later.',
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: QuickAction(
                      icon: Icons.mail_outline,
                      label: 'Offer availability',
                      onTap: () {
                        showMessage(
                          context,
                          'Availability email drafting will be added later.',
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: QuickAction(
                      icon: Icons.warning_amber_rounded,
                      label: 'Fatigue check',
                      iconColour: warningOrange,
                      onTap: () {
                        showMessage(
                          context,
                          'No fatigue warnings currently detected.',
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayCard() {
    if (_isLoading) {
      return _buildLoadingCard('Loading today’s roster…');
    }

    if (_loadError != null) {
      return _buildErrorCard();
    }

    final Duty? duty = _todayDuty;

    if (duty == null) {
      return _buildInformationCard(
        icon: Icons.help_outline,
        iconColour: railwayBlue,
        title: _fullDate(DateTime.now()),
        description: 'No roster information is available for today.',
      );
    }

    final _DutyPresentation presentation = _presentationFor(duty);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showMessage(
            context,
            '${presentation.title} • ${presentation.description}',
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: presentation.colour.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  presentation.icon,
                  color: presentation.colour,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      presentation.title,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      presentation.description,
                      style: const TextStyle(color: textGrey),
                    ),
                    if (presentation.detail != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              presentation.detail!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: presentation.colour,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _RosterSourceBadge(source: duty.source),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 5),
                      _RosterSourceBadge(source: duty.source),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: textGrey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextShiftCard() {
    if (_isLoading) {
      return _buildLoadingCard('Finding your next working shift…');
    }

    if (_loadError != null) {
      return _buildErrorCard();
    }

    final Duty? duty = _nextWorkingDuty;

    if (duty == null) {
      return _buildInformationCard(
        icon: Icons.event_busy_outlined,
        iconColour: railwayBlue,
        title: 'No upcoming shift found',
        description:
            'No working duty was found in the available roster information.',
      );
    }

    final String turnText = duty.turnNumber?.trim().isNotEmpty == true
        ? 'Turn ${duty.turnNumber!.trim()}'
        : _dutyTypeLabel(duty.dutyType);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showMessage(
            context,
            '${_fullDate(duty.date)} • ${_timeDescription(duty)} • $turnText',
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: workingGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.schedule,
                  color: workingGreen,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fullDate(duty.date),
                      style: const TextStyle(
                        color: navy,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeDescription(duty),
                      style: const TextStyle(color: textGrey),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            turnText,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: railwayBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RosterSourceBadge(source: duty.source),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: textGrey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: leaveRed, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Unable to load roster information',
                    style: TextStyle(
                      color: navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _loadError!,
                    style: const TextStyle(color: textGrey, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _loadDashboardDuties,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInformationCard({
    required IconData icon,
    required Color iconColour,
    required String title,
    required String description,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: iconColour.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconColour, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(color: textGrey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _DutyPresentation _presentationFor(Duty duty) {
    final String dateTitle = _fullDate(duty.date);

    switch (duty.dutyType) {
      case DutyType.working:
        return _DutyPresentation(
          icon: Icons.schedule,
          colour: workingGreen,
          title: dateTitle,
          description: _timeDescription(duty),
          detail: duty.turnNumber?.trim().isNotEmpty == true
              ? 'Turn ${duty.turnNumber!.trim()}'
              : 'Working duty',
        );

      case DutyType.training:
        return _DutyPresentation(
          icon: Icons.school_outlined,
          colour: workingGreen,
          title: dateTitle,
          description: _timeDescriptionOrLabel(duty, 'Training'),
          detail: 'Training',
        );

      case DutyType.medical:
        return _DutyPresentation(
          icon: Icons.medical_services_outlined,
          colour: workingGreen,
          title: dateTitle,
          description: _timeDescriptionOrLabel(duty, 'Medical'),
          detail: 'Medical',
        );

      case DutyType.restDay:
        return _DutyPresentation(
          icon: Icons.weekend_outlined,
          colour: const Color(0xFFB88700),
          title: dateTitle,
          description: 'Rest day',
        );

      case DutyType.annualLeave:
        return _DutyPresentation(
          icon: Icons.beach_access_outlined,
          colour: leaveRed,
          title: dateTitle,
          description: 'Annual leave',
        );

      case DutyType.sick:
        return _DutyPresentation(
          icon: Icons.sick_outlined,
          colour: leaveRed,
          title: dateTitle,
          description: 'Sick',
        );

      case DutyType.publicHoliday:
        return _DutyPresentation(
          icon: Icons.celebration_outlined,
          colour: leaveRed,
          title: dateTitle,
          description: 'Public holiday',
        );

      case DutyType.unavailable:
        return _DutyPresentation(
          icon: Icons.block_outlined,
          colour: const Color(0xFFB88700),
          title: dateTitle,
          description: 'Unavailable',
        );

      case DutyType.unknown:
        return _DutyPresentation(
          icon: Icons.help_outline,
          colour: railwayBlue,
          title: dateTitle,
          description: duty.remarks?.trim().isNotEmpty == true
              ? duty.remarks!.trim()
              : 'Roster status requires review',
        );
    }
  }

  String _timeDescriptionOrLabel(Duty duty, String fallback) {
    if (duty.bookOn?.trim().isNotEmpty == true ||
        duty.bookOff?.trim().isNotEmpty == true) {
      return _timeDescription(duty);
    }

    return fallback;
  }

  String _timeDescription(Duty duty) {
    final String? bookOn = duty.bookOn?.trim();
    final String? bookOff = duty.bookOff?.trim();

    if (bookOn != null &&
        bookOn.isNotEmpty &&
        bookOff != null &&
        bookOff.isNotEmpty) {
      return 'Book on $bookOn  •  Book off $bookOff';
    }

    if (bookOn != null && bookOn.isNotEmpty) {
      return 'Book on $bookOn';
    }

    if (bookOff != null && bookOff.isNotEmpty) {
      return 'Book off $bookOff';
    }

    return 'Duty times not available';
  }

  String _fullDate(DateTime date) {
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
        '${date.day} ${months[date.month - 1]}';
  }

  String _dutyTypeLabel(DutyType type) {
    switch (type) {
      case DutyType.working:
        return 'Working duty';
      case DutyType.training:
        return 'Training';
      case DutyType.medical:
        return 'Medical';
      case DutyType.restDay:
        return 'Rest day';
      case DutyType.annualLeave:
        return 'Annual leave';
      case DutyType.sick:
        return 'Sick';
      case DutyType.publicHoliday:
        return 'Public holiday';
      case DutyType.unavailable:
        return 'Unavailable';
      case DutyType.unknown:
        return 'Duty';
    }
  }

  static void showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DutyPresentation {
  const _DutyPresentation({
    required this.icon,
    required this.colour,
    required this.title,
    required this.description,
    this.detail,
  });

  final IconData icon;
  final Color colour;
  final String title;
  final String description;
  final String? detail;
}

class _RosterSourceBadge extends StatelessWidget {
  const _RosterSourceBadge({required this.source});

  final RosterSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1769AA).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          color: Color(0xFF1769AA),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String get _label {
    switch (source) {
      case RosterSource.baseRoster:
        return 'BASE';
      case RosterSource.tenDay:
        return '10D';
      case RosterSource.sevenDay:
        return '7D';
      case RosterSource.fortyEightHour:
        return '48HR';
      case RosterSource.annualLeave:
        return 'AW';
      case RosterSource.manual:
        return 'M';
    }
  }
}

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      icon: Icons.calendar_month_outlined,
      title: 'Calendar',
      description:
          'Your Day, Week, Month and Year roster views will appear here. Every week will start on Sunday.',
    );
  }
}

class UploadPage extends StatelessWidget {
  const UploadPage({
    required this.onCamera,
    required this.onPhotoLibrary,
    required this.onFile,
    required this.lastFileName,
    required this.lastDocumentType,
    super.key,
  });

  final VoidCallback onCamera;
  final VoidCallback onPhotoLibrary;
  final VoidCallback onFile;
  final String? lastFileName;
  final String? lastDocumentType;

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color textGrey = Color(0xFF52667A);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Add a roster document',
              style: TextStyle(
                color: navy,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose how you want to add the document. Smart Scan will identify its type after selection.',
              style: TextStyle(color: textGrey, height: 1.4),
            ),
            const SizedBox(height: 22),
            UploadOption(
              icon: Icons.camera_alt_outlined,
              title: 'Camera',
              subtitle: 'Photograph a paper roster or amendment',
              onTap: onCamera,
            ),
            const SizedBox(height: 12),
            UploadOption(
              icon: Icons.photo_library_outlined,
              title: 'Photo Library',
              subtitle: 'Choose an existing roster photograph',
              onTap: onPhotoLibrary,
            ),
            const SizedBox(height: 12),
            UploadOption(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF / File',
              subtitle: 'Choose a PDF or document from Files',
              onTap: onFile,
            ),
            if (lastFileName != null && lastDocumentType != null) ...[
              const SizedBox(height: 22),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  leading: const CircleAvatar(
                    child: Icon(Icons.description_outlined),
                  ),
                  title: Text(
                    lastFileName!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(lastDocumentType!),
                  ),
                  trailing: const Icon(Icons.check_circle, color: Colors.green),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              color: railwayBlue.withValues(alpha: 0.08),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_outlined, color: railwayBlue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Smart Scan recognises Base Rosters, 10-Day, 7-Day and 48-Hour amendments, Job Cards and Annual Leave Rosters. If detection is uncertain, you can label the document manually.',
                        style: TextStyle(color: navy, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      icon: Icons.timeline_outlined,
      title: 'Timeline',
      description:
          'Your duties, book-on times, book-off times, leave and amendments will appear here in date order.',
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.email, required this.onSignOut, super.key});

  final String email;
  final Future<void> Function() onSignOut;

  static const Color navy = Color(0xFF102A43);
  static const Color textGrey = Color(0xFF52667A);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Account',
              style: TextStyle(
                color: navy,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: const Text(
                  'Signed in as',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(email),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.badge_outlined),
                    title: Text('Driver profile'),
                    subtitle: Text('Roster Code, payroll number and depot'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                  const Divider(height: 1),
                  const ListTile(
                    leading: Icon(Icons.notifications_outlined),
                    title: Text('Notifications'),
                    subtitle: Text('Shift reminders and amendments'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                  const Divider(height: 1),
                  const ListTile(
                    leading: Icon(Icons.email_outlined),
                    title: Text('Roster email'),
                    subtitle: Text('drivers.rosters@wmtrains.co.uk'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text(
                      'Sign out',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Sign out of this device',
                      style: TextStyle(color: textGrey),
                    ),
                    onTap: () async {
                      await onSignOut();
                    },
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

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.icon, required this.title, super.key});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1769AA)),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF102A43),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF102A43),
          fontWeight: FontWeight.w800,
        ),
      ),
      avatar: const Icon(
        Icons.description_outlined,
        size: 18,
        color: Color(0xFF1769AA),
      ),
    );
  }
}

class DayTile extends StatelessWidget {
  const DayTile({
    required this.day,
    required this.status,
    required this.colour,
    this.darkText = false,
    super.key,
  });

  final String day;
  final String status;
  final Color colour;
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final Color textColour = darkText ? const Color(0xFF102A43) : Colors.white;

    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day,
            style: TextStyle(color: textColour, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColour, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColour = const Color(0xFF1769AA),
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColour;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: iconColour, size: 28),
              const SizedBox(height: 9),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF102A43),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UploadOption extends StatelessWidget {
  const UploadOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFF1769AA).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF1769AA)),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF102A43),
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 72, color: const Color(0xFF1769AA)),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF102A43),
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF52667A),
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
