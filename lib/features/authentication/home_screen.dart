Warning: truncated output (original token count: 101304)
Total output lines: 11372

import '../upload/depot_documents_page.dart';
import '../notifications/shift_reminder_link.dart';
import '../../core/widgets/top_notice_banner.dart';
import '../../core/widgets/day_details_panel.dart';
import '../../core/widgets/personal_day_note_section.dart';
import '../../core/services/personal_day_note_service.dart';
import 'package:flutter/services.dart';
import '../upload/roster_updates_section.dart';
import '../smart_scan/scan_duty_editor.dart';
import '../upload/roster_update_card.dart';
import '../upload/day_document_links.dart';
import '../upload/document_opener.dart';
import '../upload/job_card_viewer.dart';
import '../../core/services/roster_update_service.dart';
import '../roster/roster_job_summary.dart';
import 'sign_out.dart';
import '../upload/upload_source_picker.dart';
import '../../core/services/driver_email_identity.dart';
import '../../core/formatters/roster_date_format.dart';
import 'dart:async';
import '../../core/services/duty_history_service.dart';
import 'package:flutter/cupertino.dart';
import '../../core/services/rest_day_move.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/roster_decision_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/annual_leave_block_override.dart';
import '../../core/models/annual_leave_block_pending_action.dart';
import '../../core/models/annual_leave_request.dart';
import '../../core/models/duty.dart';
import '../../core/models/duty_type.dart';
import '../../core/models/roster_source.dart';
import '../../core/services/annual_leave_block_pending_action_service.dart';
import '../../core/services/annual_leave_block_service.dart';
import '../../core/services/annual_leave_service.dart';
import '../../core/services/floating_leave_cancellation.dart';
import '../../core/services/duty_resolver.dart';
import '../../core/services/hidden_18_service.dart';
import '../../core/services/job_card_service.dart';
import '../../core/services/manual_duty_service.dart';
import '../../core/services/sunday_availability_service.dart';
import '../../core/services/shift_swap_service.dart';
import '../upload/upload_service.dart';
import '../smart_scan/scan_review_page.dart';
import '../settings/settings_page.dart';

Uri _rosterBuddyMailUri({required String subject, required String body}) {
  return Uri.parse(
    'mailto:drivers.rosters@wmtrains.co.uk'
    '?subject=${Uri.encodeComponent(subject)}'
    '&body=${Uri.encodeComponent(body)}',
  );
}

Future<bool> _openAnnualLeaveRequestCancellationEmail({
  required String dateLabel,
}) async {
  final SupabaseClient supabase = Supabase.instance.client;
  final User? user = supabase.auth.currentUser;

  String depot = '';
  String payrollNumber = '';

  if (user != null) {
    final Map<String, dynamic>? profile = await supabase
        .from('driver_profiles')
        .select('display_name, depot, payroll_number')
        .eq('user_id', user.id)
        .maybeSingle();

    final Map<String, dynamic> metadata =
        user.userMetadata ?? <String, dynamic>{};


    depot = (profile?['depot'] ?? metadata['depot'] ?? '').toString().trim();

    payrollNumber =
        (profile?['payroll_number'] ?? metadata['payroll_number'] ?? '')
            .toString()
            .trim();
  }

  final List<String> signature = <String>[
          await driverNumberEmailLine(),
    if (payrollNumber.isNotEmpty) 'Payroll Number: $payrollNumber',
    if (depot.isNotEmpty) depot,
  ];

  final String subject = 'Annual Leave Request Cancellation - $dateLabel';

  final String body =
      'Please can I cancel my floating annual leave request for:\n\n'
      '$dateLabel\n\n'
      '${signature.isEmpty ? '' : '\n${signature.join('\n')}'}';

  return launchUrl(
    _rosterBuddyMailUri(subject: subject, body: body),
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_self',
  );
}

String _openJobCardLabel(JobCardMatch match) {
  final plan = match.jobCard.planType.name;
  return plan == 'unknown'
      ? 'Open Job Card'
      : 'Open ${plan.toUpperCase()} Job Card';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({this.showDepotDocuments = false, super.key});

  final bool showDepotDocuments;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);

  int _selectedIndex = 0;
  bool _annualLeaveFromSettings = false;
  final TopNoticeBanner _rosterBanner = TopNoticeBanner();
  int _dashboardRefreshVersion = 0;
  int _pendingActionCount = 0;
  Timer? _rosterNoticeTimer;
  bool _checkingNotices = false;
  DateTime? _lastRosterNotice;
  bool _noticesInitialised = false;

  final GlobalKey<_CalendarPageState> _calendarKey =
      GlobalKey<_CalendarPageState>();

  DateTime? _calendarRequestedDate;
  _CalendarDayAction? _calendarRequestedAction;
  int _calendarRequestVersion = 0;

  @override
  void initState() {
    super.initState();
    _refreshPendingActionCount();
    final reminderDate = shiftReminderDate(Uri.base);
    if (reminderDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedIndex = 1);
        _openCalendarAction(reminderDate, _CalendarDayAction.viewDay);
      });
    } else if (Uri.base.queryParameters['notifications'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _openPendingActions(); });
    }
    if (widget.showDepotDocuments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openDepotDocuments();
      });
    }
    _rosterNoticeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshPendingActionCount());
  }

  @override
  void dispose() {
    _rosterNoticeTimer?.cancel();
    _rosterBanner.dismiss();
    super.dispose();
  }

  Future<void> _refreshPendingActionCount() async {
    if (_checkingNotices) return;
    _checkingNotices = true;
    try {
      final SupabaseClient supabase = Supabase.instance.client;
      final User? user = supabase.auth.currentUser;

      if (user == null) {
        return;
      }

      final Map<String, dynamic>? profile = await supabase
          .from('driver_profiles')
          .select('pending_actions_last_seen_at')
          .eq('user_id', user.id)
          .maybeSingle();

      final DateTime? lastSeen = DateTime.tryParse(
        (profile?['pending_actions_last_seen_at'] ?? '').toString(),
      );

      dynamic floatingQuery = supabase
          .from('annual_leave_requests')
          .select('id, requested_at')
          .eq('user_id', user.id)
          .eq('request_type', 'floating')
          .inFilter('status', <String>['requested', 'abeyance']);

      dynamic blockQuery = supabase
          .from('annual_leave_block_pending_actions')
          .select('id, updated_at')
          .eq('user_id', user.id)
          .inFilter('status', <String>['awaiting_union', 'scheduled']);

      if (lastSeen != null) {
        final String cutoff = lastSeen.toUtc().toIso8601String();

        floatingQuery = floatingQuery.gt('requested_at', cutoff);
        blockQuery = blockQuery.gt('updated_at', cutoff);
      }

      dynamic cancellationQuery = supabase.from('annual_leave_requests')
          .select('id').eq('user_id', user.id)
          .eq('request_type', 'floating').eq('status', 'granted')
          .eq('cancellation_pending', true);
      if (lastSeen != null) {
        cancellationQuery = cancellationQuery.gt('updated_at', lastSeen.toUtc().toIso8601String());
      }
      final List<dynamic> cancellationRows = await cancellationQuery;
      final List<dynamic> floatingRows = await floatingQuery;
      final List<dynamic> blockRows = await blockQuery;

      final List<dynamic> shiftSwapRows = await supabase
          .from('shift_swaps')
          .select('id, notes')
          .eq('user_id', user.id)
          .eq('status', 'pending');

      int newShiftSwapCount = 0;

      for (final dynamic value in shiftSwapRows) {
        if (value is! Map) {
          continue;
        }

        final String notes = (value['notes'] ?? '').toString();
        DateTime? createdAt;

        for (final String line in notes.split('\n')) {
          if (line.startsWith('CREATED_AT=')) {
            createdAt = DateTime.tryParse(
              line.substring('CREATED_AT='.length).trim(),
            );
            break;
          }
        }

        if (lastSeen == null) {
          newShiftSwapCount++;
        } else if (createdAt != null && createdAt.isAfter(lastSeen)) {
          newShiftSwapCount++;
        }
      }

      List<RosterUpdateNotice> rosterUpdates = [];
      try {
        rosterUpdates = await RosterUpdateService().load();
      } catch (_) {
        // A roster notice failure must not hide pending leave or swap actions.
      }
      if (mounted && rosterUpdates.isNotEmpty) {
        final latest = rosterUpdates.first.receivedAt;
        if ((!_noticesInitialised || _lastRosterNotice == null || latest.isAfter(_lastRosterNotice!))) {
          _rosterBanner.show(context,
            message: rosterUpdates.any((notice) => notice.needsInvestigation)
                ? 'Annual leave conflict: a roster sheet lists you working. Open the bell to review.'
                : 'Roster update: ${rosterUpdates.length} duty record(s) received. Open the bell for details.',
            onView: _openPendingActions,
          );
        }
        _lastRosterNotice = latest;
      }
      _noticesInitialised = true;
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingActionCount =
            floatingRows.length + cancellationRows.length + blockRows.length + newShiftSwapCount + rosterUpdates.length;
      });
    } catch (_) {
      // Badge loading must never prevent the main app from loading.
    } finally {
      _checkingNotices = false;
    }
  }

  Future<void> _markPendingActionsSeen() async {
    try {
      final SupabaseClient supabase = Supabase.instance.client;
      final User? user = supabase.auth.currentUser;

      if (user == null) {
        return;
      }

      final DateTime seenAt = DateTime.now().toUtc();

      await supabase
          .from('driver_profiles')
          .update(<String, dynamic>{
            'pending_actions_last_seen_at': seenAt.toIso8601String(),
          })
          .eq('user_id', user.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _pendingActionCount = 0;
      });
    } catch (_) {
      // Failure to update seen state must not stop Pending Actions opening.
    }
  }

  void _openCalendarAction(DateTime date, _CalendarDayAction action) {
    final _CalendarPageState? calendarState = _calendarKey.currentState;

    if (calendarState == null) {
      setState(() {
        _calendarRequestedDate = date;
        _calendarRequestedAction = action;
        _calendarRequestVersion++;
        _selectedIndex = 1;
      });
      return;
    }

    calendarState.openExternalAction(date, action);
  }

  Future<void> _signOut() async {
    await signOutAndResetNavigation(
      context, signOut: () => Supabase.instance.client.auth.signOut(),
    );
  }

  Future<void> _navigateFromChild(int destination) async {
    if (destination == 2) {
      await _pickDocument(UploadSource.file);
      return;
    }

    if (!mounted) {
      return;
    }

    if (destination == 1) {
      _calendarKey.currentState?.showCurrentMonth();
    }
    setState(() {
      if (destination == 0 || destination == 1) {
        _dashboardRefreshVersion++;
      }

      _annualLeaveFromSettings = destination == 3 && _selectedIndex == 4;
      _selectedIndex = destination;
    });
  }

  Future<void> _pickDocument(UploadSource source) async {
    try {
      final UploadSource? selectedSource = source == UploadSource.file
          ? await chooseUploadSource(context)
          : source;
      if (selectedSource == null || !mounted) return;
      final PickedUpload? picked = await UploadService.pickDocument(selectedSource);

      if (picked == null || !mounted) {
        return;
      }

      final document = await UploadService.collectPages(context, picked);
      if (document == null || !mounted) return;
      await _showSmartScanDialog(document);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Unable to open the document picker: $error')),
        );
    }
  }

  Future<void> _showSmartScanDialog(PickedUpload picked) async {
    final reviewed = await Navigator.of(context).push<ReviewedDocument>(
      MaterialPageRoute(builder: (_) => ScanReviewPage(upload: picked)),
    );
    if (reviewed == null || !mounted) return;
    final uploaded = await UploadService.uploadPickedDocument(
      context, picked,
      detectedType: reviewed.type.scanLabel,
      manuallyLabelled: true,
      baseRosterActivation: reviewed.activation,
      baseRosterPages: reviewed.baseRosterPages,
      reviewedResult: reviewed.result,
    );
    if (!uploaded || !mounted) return;
    setState(() { _dashboardRefreshVersion++; _selectedIndex = 0; });
  }

  Future<void> _openDepotDocuments() => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => DepotDocumentsPage(
      onUpload: () => _pickDocument(UploadSource.file),
      onRosterChanged: _notifyRosterChanged,
    )),
  );

  void _openUploadPage() {
    _pickDocument(UploadSource.file);
  }

  void _notifyRosterChanged() {
    setState(() {
      _dashboardRefreshVersion++;
    });

    _refreshPendingActionCount();
  }

  final AnnualLeaveService _pendingActionsAnnualLeaveService =
      AnnualLeaveService();

  Future<void> _openPendingActions() async {
    await _markPendingActionsSeen();

    if (!mounted) {
      return;
    }

    final int? destination = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (BuildContext context) {
          return _PendingActionsPage(
            annualLeaveService: _pendingActionsAnnualLeaveService,
            onChanged: _notifyRosterChanged,
            currentTabIndex: _selectedIndex,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }

    _notifyRosterChanged();

    if (destination == null) {
      return;
    }

    if (destination == 2) {
      await _pickDocument(UploadSource.file);
      return;
    }

    setState(() {
      if (destination == 0 || destination == 1) {
        _dashboardRefreshVersion++;
      }

      _selectedIndex = destination;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String email =
        Supabase.instance.client.auth.currentUser?.email ?? 'Roster Buddy user';

    final List<Widget> pages = [
      _DashboardPage(
        email: email,
        onUpload: _openUploadPage,
        onCalendarAction: _openCalendarAction,
        onRosterChanged: _notifyRosterChanged,
        refreshVersion: _dashboardRefreshVersion,
      ),
      _CalendarPage(
        key: _calendarKey,
        refreshVersion: _dashboardRefreshVersion,
        requestedDate: _calendarRequestedDate,
        requestedAction: _calendarRequestedAction,
        requestVersion: _calendarRequestVersion,
        onRosterChanged: _notifyRosterChanged,
        onOpenCalendar: () {
          setState(() {
            _selectedIndex = 1;
          });
        },
      ),
      _DashboardPage(
        email: email,
        onUpload: _openUploadPage,
        onCalendarAction: _openCalendarAction,
        onRosterChanged: _notifyRosterChanged,
        refreshVersion: _dashboardRefreshVersion,
      ),
      AnnualLeaveSettingsPage(
        embedded: true,
        onRosterChanged: _notifyRosterChanged,
        refreshVersion: _dashboardRefreshVersion,
      ),
      AppSettingsPage(
        onOpenNotifications: _openPendingActions,
        email: email,
        onSignOut: _signOut,
        onNavigate: _navigateFromChild,
      ),
    ];

    const List<String> titles = [
      'Roster Buddy',
      'Calendar',
      'Upload',
      'Annual Leave',
      'Settings',
    ];

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? Theme.of(context).scaffoldBackgroundColor : background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: _selectedIndex == 3 && _annualLeaveFromSettings
            ? BackButton(onPressed: () => setState(() {
                _annualLeaveFromSettings = false;
                _selectedIndex = 4;
              }))
            : null,
        backgroundColor: dark ? const Color(0xFF101C2B) : Colors.white,
        foregroundColor: dark ? Colors.white : navy,
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
        actions: [
          IconButton(
            tooltip: _pendingActionCount == 0
                ? 'Pending Actions'
                : 'Pending Actions ($_pendingActionCount)',
            onPressed: _openPendingActions,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (_pendingActionCount > 0)
                  Positioned(
                    right: -7,
                    top: -7,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Color(0xFFD64545),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        _pendingActionCount > 99
                            ? '99+'
                            : '$_pendingActionCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) async {
          if (index == 2) {
            await _openDepotDocuments();
            return;
          }

          if (index == 1) {
            _calendarKey.currentState?.showCurrentMonth();
          }

          setState(() {
            if (index == 0 || index == 1) {
              _dashboardRefreshVersion++;
            }

            _annualLeaveFromSettings = false;
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
            icon: Icon(Icons.flight_takeoff),
            selectedIcon: Icon(Icons.flight),
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
}

class _PendingActionsPage extends StatefulWidget {
  const _PendingActionsPage({
    required this.annualLeaveService,
    required this.onChanged,
    required this.currentTabIndex,
  });

  final AnnualLeaveService annualLeaveService;
  final VoidCallback onChanged;
  final int currentTabIndex;

  @override
  State<_PendingActionsPage> createState() => _PendingActionsPageState();
}

class _PendingActionsPageState extends State<_PendingActionsPage> {
  static const Color leaveRed = Color(0xFFD64545);
  static const Color textGrey = Color(0xFF52667A);

  final AnnualLeaveBlockPendingActionService _blockPendingService =
      AnnualLeaveBlockPendingActionService();
  final AnnualLeaveBlockService _blockService = AnnualLeaveBlockService();
  final ShiftSwapService _shiftSwapService = ShiftSwapService();
  final DutyResolver _shiftSwapDutyResolver = DutyResolver();
  final ManualDutyService _shiftSwapManualDutyService = ManualDutyService();
  final JobCardService _shiftSwapJobCardService = JobCardService();

  List<RosterUpdateNotice> _rosterUpdates = [];
  bool _isLoading = true;
  String? _errorMessage;
  List<AnnualLeaveRequest> _requests = <AnnualLeaveRequest>[];
  List<AnnualLeaveBlockPendingAction> _blockActions =
      <AnnualLeaveBlockPendingAction>[];
  List<ShiftSwap> _shiftSwaps = <ShiftSwap>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _viewedRosterUpdates(List<RosterUpdateNotice> viewed) async {
    await RosterUpdateService().markViewed(viewed);
    if (!mounted) return;
    final keys = viewed.where((n) => !n.needsInvestigation).map((n) => n.viewKey).toSet();
    setState(() => _rosterUpdates.removeWhere((notice) =>
        !notice.needsInvestigation && keys.contains(notice.viewKey)));
    widget.onChanged();
  }

  Future<void> _openRosterDocument(RosterUpdateNotice notice) async {
    try {
      await openUploadedDocument(() async {
        final client = Supabase.instance.client;
        final document = await client.from('roster_documents')
            .select('storage_path').eq('id', notice.documentId!).single();
        return client.storage.from('roster-documents').createSignedUrl(document['storage_path'] as String, 300);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open the uploaded sheet. Please retry.')));
      }
    }
  }

  Future<void> _useRosteredShift(RosterUpdateNotice notice) async {
    var selected = notice.rosteredDuty;
    if (selected == null) {
      final date = DateTime.tryParse(notice.date);
      if (date == null) return;
      selected = await showDialog<Duty>(context: context, builder: (_) => ScanDutyEditor(
        source: const {'10D': RosterSource.tenDay, '7D': RosterSource.sevenDay, '48HR': RosterSource.fortyEightHour}[notice.source] ?? RosterSource.sevenDay,
        initial: Duty(date: date, source: RosterSource.sevenDay, dutyType: DutyType.working,
          bookOn: notice.start == '—' ? null : notice.start,
          bookOff: notice.finish == '—' ? null : notice.finish, turnNumber: notice.turn),
      ));
    }
    if (selected == null || !mounted) return;
    final chosen = selected;
    final confirmed = await showRosterDecisionSheet<bool>(context: context,
      builder: (dialogContext) => RosterDecisionSheet(
        title: const Text('Use this rostered shift?'),
        content: Text('Replace your annual-leave entry on ${displayDate(chosen.date)} with ${notice.detail}? Only continue if the annual leave was entered in error.'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep annual leave')),
          CupertinoDialogAction(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Use rostered shift')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final current = await DutyResolver().getDutyForDate(chosen.date);
      if (!mounted) return;
      if (current == null) {
        await _load();
        return;
      }
      final requests = await widget.annualLeaveService.getRequestsForRange(chosen.date, chosen.date);
      final floating = requests.values.where((request) =>
          request.requestType == AnnualLeaveRequestType.floating &&
          request.status == AnnualLeaveRequestStatus.granted).firstOrNull;
      if (!mounted) return;
      if (current.dutyType != DutyType.annualLeave && floating == null) {
        await _load();
        return;
      }
      if (floating != null) {
        final changed = await manageFloatingLeaveCancellation(
          context: context, requests: [floating],
          historyRestore: DutyHistoryService.restorationPayload(chosen, current),
        );
        if (!changed || !mounted) return;
      } else {
        await DutyHistoryService().revert(chosen, current);
      }
      if (!mounted) return;
      widget.onChanged();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not allocate the rostered shift. Check the day and try again.')));
      }
    }
  }

  String _dateLabel(DateTime date) {
    return displayDate(date);
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<AnnualLeaveRequest> requests = await widget.annualLeaveService
          .getPendingFloatingRequests();

      final List<AnnualLeaveBlockPendingAction> blockActions =
          await _blockPendingService.getPendingActions();

      final List<ShiftSwap> shiftSwaps = await _shiftSwapService.getRequests();

      List<RosterUpdateNotice> rosterUpdates = [];
      try { rosterUpdates = await RosterUpdateService().load(); } catch (_) {}
      if (!mounted) {
        return;
      }

      final List<AnnualLeaveRequest> orderedRequests =
          List<AnnualLeaveRequest>.of(requests)..sort(
            (AnnualLeaveRequest a, AnnualLeaveRequest b) =>
                a.leaveDate.compareTo(b.leaveDate),
          );

      final List<AnnualLeaveBlockPendingAction> orderedBlockActions =
          List<AnnualLeaveBlockPendingAction>.of(blockActions)..sort(
            (
              AnnualLeaveBlockPendingAction a,
              AnnualLeaveBlockPendingAction b,
            ) => a.proposedStartDate.compareTo(b.proposedStartDate),
          );

      final List<ShiftSwap> orderedShiftSwaps =
          shiftSwaps
              .where((ShiftSwap swap) => swap.status == ShiftSwapStatus.pending)
              .toList()
            ..sort(
              (ShiftSwap a, ShiftSwap b) =>
                  a.originalDate.compareTo(b.originalDate),
            );

      setState(() {
        _rosterUpdates = rosterUpdates;
        _requests = orderedRequests;
        _blockActions = orderedBlockActions;
        _shiftSwaps = orderedShiftSwaps;
        _isLoading = false;
      });
    } on AnnualLeaveException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    } on AnnualLeaveBlockPendingActionException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Roster Buddy could not load Pending Actions.';
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _grant(AnnualLeaveRequest request) async {
    try {
      await widget.annualLeaveService.markGranted(requestId: request.id);

      widget.onChanged();
      await _load();

      _showMessage(
        'Annual leave granted for ${_dateLabel(request.leaveDate)}.',
      );
    } on AnnualLeaveException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Roster Buddy could not grant this annual leave request.');
    }
  }

  Future<void> _moveToAbeyance(AnnualLeaveRequest request) async {
    final TextEditingController controller = TextEditingController(
      text: request.queuePosition?.toString() ?? '',
    );

    final int? queuePosition = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) {
        String? errorText;

        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setDialogState,
              ) {
                return AlertDialog(
                  title: Text(
                    request.status == AnnualLeaveRequestStatus.abeyance
                        ? 'Update abeyance position'
                        : 'Move to abeyance',
                  ),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Queue position',
                      hintText: 'For example 3',
                      errorText: errorText,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final int? value = int.tryParse(controller.text.trim());

                        if (value == null || value < 1) {
                          setDialogState(() {
                            errorText = 'Enter a queue position of 1 or more.';
                          });
                          return;
                        }

                        Navigator.of(dialogContext).pop(value);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                );
              },
        );
      },
    );

    controller.dispose();

    if (queuePosition == null || !mounted) {
      return;
    }

    try {
      await widget.annualLeaveService.markAbeyance(
        requestId: request.id,
        queuePosition: queuePosition,
      );

      widget.onChanged();
      await _load();

      _showMessage(
        'Annual leave held in abeyance at queue position #$queuePosition.',
      );
    } on AnnualLeaveException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Roster Buddy could not update the abeyance position.');
    }
  }

  Future<void> _cancel(AnnualLeaveRequest request) async {
    final bool? alreadyConfirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Cancellation confirmed?'),
          content: Text(
            'Has the cancellation of your annual leave request for '
            '${_dateLabel(request.leaveDate)} already been confirmed '
            'by Rosters / DTCM?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('No'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (alreadyConfirmed == null || !mounted) {
      return;
    }

    try {
      if (alreadyConfirmed) {
        await widget.annualLeaveService.cancelRequest(requestId: request.id);

        widget.onChanged();
        await _load();

        _showMessage(
          'Annual leave request cancelled for '
          '${_dateLabel(request.leaveDate)}.',
        );

        return;
      }

      final bool opened = await _openAnnualLeaveRequestCancellationEmail(
        dateLabel: _dateLabel(request.leaveDate),
      );

      if (!mounted) {
        return;
      }

      if (opened) {
        _showMessage(
          'Cancellation email prepared. The annual leave request '
          'will remain active until Rosters / DTCM confirms cancellation.',
        );
      } else {
        _showMessage(
          'Roster Buddy could not open your email app. '
          'The annual leave request remains active.',
        );
      }
    } on AnnualLeaveException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        'Roster Buddy could not process this annual leave cancellation.',
      );
    }
  }

  String? _shiftSwapMetadata(ShiftSwap swap, String key) {
    final String? notes = swap.notes;

    if (notes == null || notes.trim().isEmpty) {
      return null;
    }

    final String prefix = '$key=';

    for (final String line in notes.split('\n')) {
      if (line.startsWith(prefix)) {
        final String value = line.substring(prefix.length).trim();
        return value.isEmpty ? null : value;
      }
    }

    return null;
  }

  bool _sameCalendarDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  Future<void> _approveShiftSwap(ShiftSwap swap) async {
    final bool? confirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Swap confirmed?'),
          content: Text(
            'Has Rosters / DTCM confirmed this mutual swap?\n\n'
            '${_dateLabel(swap.originalDate)}'
            '${swap.originalTurnNumber == null ? '' : ' • Turn ${swap.originalTurnNumber}'}'
            '\n→\n'
            '${_dateLabel(swap.requestedDate)}'
            '${swap.requestedTurnNumber == null ? '' : ' • Turn ${swap.requestedTurnNumber}'}',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Not yet'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Yes, confirmed'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final String? requestedTurn = swap.requestedTurnNumber?.trim();

      if (requestedTurn == null || requestedTurn.isEmpty) {
        _showMessage(
          'This swap does not contain the other driver’s turn number.',
        );
        return;
      }

      final Duty? originalDuty = await _shiftSwapDutyResolver.getDutyForDate(
        swap.originalDate,
      );

      if (originalDuty == null || !originalDuty.dutyType.countsAsWorking) {
        _showMessage(
          'Your original date no longer contains a working duty. '
          'Roster Buddy has not applied the swap.',
        );
        return;
      }

      final String? storedOriginalTurn = swap.originalTurnNumber?.trim();
      final String? currentOriginalTurn = originalDuty.turnNumber?.trim();

      if (storedOriginalTurn != null &&
          storedOriginalTurn.isNotEmpty &&
          currentOriginalTurn != storedOriginalTurn) {
        _showMessage(
          'Your duty on ${_dateLabel(swap.originalDate)} has changed since '
          'this swap was requested. Review the new duty before applying it.',
        );
        return;
      }

      final JobCardMatch? jobCardMatch = await _shiftSwapJobCardService
          .findMatchingJobCard(
            turnNumber: requestedTurn,
            dutyDate: swap.requestedDate,
          );

      String incomingTurnNumber = requestedTurn;
      String incomingBookOn = '';
      String incomingBookOff = '';

      if (jobCardMatch != null &&
          incomingBookOn.trim().isNotEmpty &&
          incomingBookOff.trim().isNotEmpty) {
        incomingTurnNumber = jobCardMatch.jobCard.turnNumber;
        incomingBookOn = jobCardMatch.jobCard.bookOn.trim();
        incomingBookOff = jobCardMatch.jobCard.bookOff.trim();
      } else {
        if (!mounted) {
          return;
        }

        final TextEditingController bookOnController = TextEditingController();
        final TextEditingController bookOffController = TextEditingController();

        final List<String>? manualTimes = await showDialog<List<String>>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            String? errorText;

            bool validTime(String value) {
              final String cleaned = value.trim().replaceAll(':', '');

              if (cleaned.length != 4) {
                return false;
              }

              final int? hour = int.tryParse(cleaned.substring(0, 2));
              final int? minute = int.tryParse(cleaned.substring(2, 4));

              if (hour == null || minute == null) {
                return false;
              }

              return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
            }

            return StatefulBuilder(
              builder:
                  (
                    BuildContext context,
                    void Function(void Function()) setDialogState,
                  ) {
                    return AlertDialog(
                      title: const Text('No valid Job Card'),
                      content: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No valid Job Card was found for Turn '
                              '$requestedTurn on '
                              '${_dateLabel(swap.requestedDate)}. '
                              'Please input the times manually.',
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: bookOnController,
                              autofocus: true,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: 'Book on',
                                hintText: '0800',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: bookOffController,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: 'Book off',
                                hintText: '1600',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (errorText != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                errorText!,
                                style: const TextStyle(
                                  color: Color(0xFFD64545),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              'Enter times as 4 digits, for example 0800 or 1630.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                          },
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            final String bookOn = bookOnController.text.trim();
                            final String bookOff = bookOffController.text
                                .trim();

                            if (!validTime(bookOn) || !validTime(bookOff)) {
                              setDialogState(() {
                                errorText =
                                    'Enter times as 4 digits, for example 0800 or 1630.';
                              });
                              return;
                            }

                            Navigator.of(
                              dialogContext,
                            ).pop(<String>[bookOn, bookOff]);
                          },
                          child: const Text('Use times'),
                        ),
                      ],
                    );
                  },
            );
          },
        );

        bookOnController.dispose();
        bookOffController.dispose();

        if (manualTimes == null || !mounted) {
          return;
        }

        final String rawBookOn = manualTimes[0].trim().replaceAll(':', '');
        final String rawBookOff = manualTimes[1].trim().replaceAll(':', '');

        incomingBookOn =
            '${rawBookOn.substring(0, 2)}:${rawBookOn.substring(2, 4)}';
        incomingBookOff =
            '${rawBookOff.substring(0, 2)}:${rawBookOff.substring(2, 4)}';
      }

      final bool sameDate = _sameCalendarDate(
        swap.originalDate,
        swap.requestedDate,
      );

      Duty? targetOriginalDuty;

      if (!sameDate) {
        targetOriginalDuty = await _shiftSwapDutyResolver.getDutyForDate(
          swap.requestedDate,
        );

        if (targetOriginalDuty?.dutyType.countsAsWorking == true) {
          _showMessage(
            'You already have a working duty on '
            '${_dateLabel(swap.requestedDate)}. '
            'Roster Buddy will not apply this swap automatically.',
          );
          return;
        }
      }

      final String otherDriver = _shiftSwapMetadata(swap, 'OTHER_DRIVER') ?? '';
      final String otherPayroll =
          _shiftSwapMetadata(swap, 'OTHER_PAYROLL') ?? '';

      if (sameDate) {
        await _shiftSwapManualDutyService.saveMutualSwapWorkingDuty(
          date: swap.originalDate,
          turnNumber: incomingTurnNumber,
          bookOn: incomingBookOn,
          bookOff: incomingBookOff,
          otherDriverName: otherDriver,
          otherPayrollNumber: otherPayroll,
          originalDuty: originalDuty,
        );
      } else {
        await _shiftSwapManualDutyService.saveMutualSwapRestDay(
          date: swap.originalDate,
          originalDuty: originalDuty,
          otherDriverName: otherDriver,
          otherPayrollNumber: otherPayroll,
        );

        await _shiftSwapManualDutyService.saveMutualSwapWorkingDuty(
          date: swap.requestedDate,
          turnNumber: incomingTurnNumber,
          bookOn: incomingBookOn,
          bookOff: incomingBookOff,
          otherDriverName: otherDriver,
          otherPayrollNumber: otherPayroll,
          originalDuty: targetOriginalDuty,
        );
      }

      // Mark approved only after the diary changes succeed.
      // If this status update fails, retrying is safe because the manual-duty
      // writes are upserts.
      await _shiftSwapService.markApproved(
        requestId: swap.id,
        requestedBookOn: incomingBookOn,
        requestedBookOff: incomingBookOff,
      );

      widget.onChanged();
      await _load();

      if (!mounted) {
        return;
      }

      _showMessage(
        sameDate
            ? 'Mutual swap confirmed. Turn $incomingTurnNumber '
                  'is now shown on ${_dateLabel(swap.originalDate)}.'
            : 'Mutual swap confirmed. '
                  '${_dateLabel(swap.originalDate)} is now a Rest Day and '
                  'Turn $incomingTurnNumber is shown on '
                  '${_dateLabel(swap.requestedDate)}.',
      );
    } catch (error) {
      debugPrint('Mutual shift swap apply failed: $error');

      if (!mounted) {
        return;
      }

      _showMessage(
        'Roster Buddy could not apply this mutual shift swap. '
        'Error: $error',
      );
    }
  }

  Future<void> _cancelShiftSwap(ShiftSwap swap) async {
    final bool? confirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Cancel swap request?'),
          content: Text(
            'Cancel the pending mutual swap from '
            '${_dateLabel(swap.originalDate)} to '
            '${_dateLabel(swap.requestedDate)}?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Keep'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Cancel request'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _shiftSwapService.cancelRequest(requestId: swap.id);

      widget.onChanged();
      await _load();

      _showMessage('Mutual shift swap request cancelled.');
    } catch (_) {
      _showMessage(
        'Roster Buddy could not cancel this mutual shift swap request.',
      );
    }
  }

  Widget _buildShiftSwapCard(ShiftSwap swap) {
    if (swap.notes?.startsWith('TYPE=Rest day move') == true) {
      final pairs = restDayMovePairs(swap.notes!);
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(swap.notes?.contains('ALLOCATION_REQUIRED=true') == true ? 'Rest day move — awaiting allocation' : 'Rest day move — pending', style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final pair in pairs) Text("${displayStoredDate(pair['rest'])} → ${displayStoredDate(pair['work'])}"),
          TextButton(onPressed: () async {
            try {
              final changed = await actionRestDayMove(context, pairs, id: swap.id, awaitingAllocation: swap.notes?.contains('ALLOCATION_REQUIRED=true') == true);
              if (changed && mounted) { widget.onChanged(); await _load(); }
            } catch (_) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not action rest day move. Please try again.')));
            }
          }, child: const Text('Action')),
        ],
      )));
    }

    final String? otherDriver = _shiftSwapMetadata(swap, 'OTHER_DRIVER');
    final String? otherPayroll = _shiftSwapMetadata(swap, 'OTHER_PAYROLL');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz_outlined, color: Color(0xFF1769AA)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mutual shift swap',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ROSTERS',
                    style: TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Your duty: ${_dateLabel(swap.originalDate)}'
              '${swap.originalTurnNumber == null ? '' : ' • Turn ${swap.originalTurnNumber}'}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Requested duty: ${_dateLabel(swap.requestedDate)}'
              '${swap.requestedTurnNumber == null ? '' : ' • Turn ${swap.requestedTurnNumber}'}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
            ),
            if (otherDriver != null) ...[
              const SizedBox(height: 6),
              Text(
                'Other driver: $otherDriver'
                '${otherPayroll == null ? '' : ' • Payroll $otherPayroll'}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Awaiting confirmation from Rosters / DTCM.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _approveShiftSwap(swap),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirm approved'),
                style: FilledButton.styleFrom(
                  backgroundColor: Color(0xFF1769AA),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _cancelShiftSwap(swap),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel request'),
                style: OutlinedButton.styleFrom(foregroundColor: leaveRed),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _blockPeriodLabel(AnnualLeaveBlockPendingAction action) {
    switch (action.periodType) {
      case AnnualLeaveBlockPeriodType.spring:
        return 'Spring block leave';
      case AnnualLeaveBlockPeriodType.summerFirstWeek:
        return 'Summer block leave – Week 1';
      case AnnualLeaveBlockPeriodType.summerSecondWeek:
        return 'Summer block leave – Week 2';
      case AnnualLeaveBlockPeriodType.winter:
        return 'Winter block leave';
    }
  }

  String _blockScheduledTimeLabel(AnnualLeaveBlockPendingAction action) {
    final DateTime? scheduledFor = action.scheduledFor;

    if (scheduledFor == null) {
      return 'Send time unavailable';
    }

    /*
     * The current scheduled block dates are stored as UTC timestamps
     * representing the required UK send time.
     */
    final DateTime local = scheduledFor.toLocal();

    final String minute = local.minute.toString().padLeft(2, '0');

    return '${local.hour.toString().padLeft(2, '0')}:$minute on ${displayDate(local)}';
  }

  String _blockChangeTypeLabel(AnnualLeaveBlockPendingAction action) {
    switch (action.changeType) {
      case AnnualLeaveBlockChangeType.manual:
        return 'Manual';
      case AnnualLeaveBlockChangeType.agreedMove:
        return 'Block move';
      case AnnualLeaveBlockChangeType.mutualSwap:
        return 'Mutual swap';
    }
  }

  Future<void> _confirmBlockAction(AnnualLeaveBlockPendingAction action) async {
    final bool? confirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Union confirmed?'),
          content: Text(
            'Has the Union confirmed this ${_blockChangeTypeLabel(action).toLowerCase()} '
            'for ${_blockPeriodLabel(action)}?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Not yet'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Yes, confirmed'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _blockService.saveOverride(
        leaveYear: action.leaveYear,
        periodType: action.periodType,
        originalStartDate: action.originalStartDate,
        originalEndDate: action.originalEndDate,
        overrideStartDate: action.proposedStartDate,
        overrideEndDate: action.proposedEndDate,
        changeType: action.changeType,
        swapDriverNumber: action.swapDriverNumber,
        swapReference: action.swapReference,
        notes: action.notes,
      );

      await _blockPendingService.markConfirmed(actionId: action.id);

      widget.onChanged();
      await _load();

      _showMessage('${_blockPeriodLabel(action)} confirmed and updated.');
    } on AnnualLeaveBlockException catch (error) {
      _showMessage(error.message);
    } on AnnualLeaveBlockPendingActionException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Roster Buddy could not confirm this block leave change.');
    }
  }

  Future<void> _cancelScheduledBlockAction(
    AnnualLeaveBlockPendingAction action,
  ) async {
    final bool? confirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Cancel queued request?'),
          content: Text(
            'Remove the queued ${_blockChangeTypeLabel(action).toLowerCase()} '
            'for ${_blockPeriodLabel(action)}?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Keep'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Cancel request'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _blockPendingService.cancelScheduledAction(actionId: action.id);

      await _load();

      _showMessage('${_blockPeriodLabel(action)} removed from the send queue.');
    } on AnnualLeaveBlockPendingActionException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        'Roster Buddy could not cancel this queued block leave request.',
      );
    }
  }

  Future<void> _cancelBlockAction(AnnualLeaveBlockPendingAction action) async {
    final bool? confirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Cancel pending change?'),
          content: Text(
            'Cancel the pending ${_blockChangeTypeLabel(action).toLowerCase()} '
            'for ${_blockPeriodLabel(action)}?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Keep'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Cancel change'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _blockPendingService.cancelPendingAction(actionId: action.id);

      await _load();

      _showMessage('${_blockPeriodLabel(action)} pending change cancelled.');
    } on AnnualLeaveBlockPendingActionException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        'Roster Buddy could not cancel this pending block leave change.',
      );
    }
  }

  Widget _buildBlockActionCard(AnnualLeaveBlockPendingAction action) {
    final bool mutualSwap =
        action.changeType == AnnualLeaveBlockChangeType.mutualSwap;

    final bool scheduled =
        action.status == AnnualLeaveBlockPendingStatus.scheduled;

    final Color statusColour = scheduled ? const Color(0xFFF59E0B) : leaveRed;

    final String statusLabel = scheduled ? 'SEND QUEUE' : 'UNION';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  scheduled
                      ? Icons.schedule_send_outlined
                      : Icons.swap_horiz_outlined,
                  color: statusColour,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _blockPeriodLabel(action),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColour.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: scheduled ? const Color(0xFFB45309) : leaveRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_blockChangeTypeLabel(action)} • ${action.leaveYear}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Current: ${_dateLabel(action.originalStartDate)} – '
              '${_dateLabel(action.originalEndDate)}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Requested: ${_dateLabel(action.proposedStartDate)} – '
              '${_dateLabel(action.proposedEndDate)}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
            ),
            if (mutualSwap && action.swapDriverNumber != null) ...[
              const SizedBox(height: 6),
              Text(
                'Other driver: ${action.swapDriverNumber}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            if (action.swapReference != null) ...[
              const SizedBox(height: 4),
              Text(
                'Reference: ${action.swapReference}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            if (action.notes != null) ...[
              const SizedBox(height: 4),
              Text(action.notes!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],

            if (scheduled) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saved to send queue',
                      style: TextStyle(
                        color: Color(0xFFB45309),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Due to send ${_blockScheduledTimeLabel(action)}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (action.recipientEmail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'To: ${action.recipientEmail}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      'Automatic email sending is not yet active. '
                      'The email details and send time are safely stored, '
                      'but the server-side sender still needs to be connected.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelScheduledBlockAction(action),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel queued request'),
                  style: OutlinedButton.styleFrom(foregroundColor: leaveRed),
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              const Text(
                'Awaiting Union confirmation. Your current block allocation '
                'has not been changed.',
                style: TextStyle(
                  color: Color(0xFFB45309),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _confirmBlockAction(action),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Union confirmed'),
                  style: FilledButton.styleFrom(backgroundColor: leaveRed),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelBlockAction(action),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel pending change'),
                  style: OutlinedButton.styleFrom(foregroundColor: leaveRed),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(AnnualLeaveRequest request) {
    if (request.cancellationPending) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_dateLabel(request.leaveDate),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Pending cancellation', style: TextStyle(color: leaveRed, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Awaiting Rosters / DTCM approval. Leave stays granted until confirmed.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final changed = await manageFloatingLeaveCancellation(context: context, requests: [request]);
                if (changed && mounted) {
                  widget.onChanged();
                  await _load();
                }
              },
              child: const Text('Action cancellation'),
            ),
          ]),
        ),
      );
    }

    final bool isAbeyance = request.status == AnnualLeaveRequestStatus.abeyance;

    final String statusText = isAbeyance
        ? request.queuePosition == null
              ? 'ABE'
              : 'ABE #${request.queuePosition}'
        : 'AL REQ';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flight_takeoff, color: leaveRed),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _dateLabel(request.leaveDate),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isAbeyance
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                        : leaveRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: isAbeyance ? const Color(0xFFB45309) : leaveRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isAbeyance
                  ? 'Floating annual leave held in abeyance.'
                  : 'Floating annual leave awaiting a decision from Rosters.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _grant(request),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('Grant'),
                    style: FilledButton.styleFrom(backgroundColor: leaveRed),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _moveToAbeyance(request),
                    icon: const Icon(Icons.hourglass_top_outlined),
                    label: Text(isAbeyance ? 'Update ABE' : 'Abeyance'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _cancel(request),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel request'),
                style: OutlinedButton.styleFrom(foregroundColor: leaveRed),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasPendingActions =
        _requests.isNotEmpty ||
        _blockActions.isNotEmpty ||
        _shiftSwaps.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        title: const Text(
          'Notifications & actions',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text(
                'Notifications',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'View roster updates or review outstanding annual leave '
                'and shift-swap actions.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              RosterUpdatesSection(
                notices: _rosterUpdates.where((notice) => !notice.needsInvestigation).toList(),
                onViewed: _viewedRosterUpdates,
                onOpenDocument: _openRosterDocument,
              ),
              if (_rosterUpdates.any((notice) => notice.needsInvestigation)) ...[
                Text('Needs investigation', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900)),
                for (final notice in _rosterUpdates.where((notice) => notice.needsInvestigation))
                  RosterUpdateCard(notice: notice,
                    onOpenDocument: () => _openRosterDocument(notice),
                    onUseShift: () => _useRosteredShift(notice)),
                const SizedBox(height: 16),
              ],
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: leaveRed,
                          size: 30,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (!hasPendingActions)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 34),
                        SizedBox(height: 10),
                        Text(
                          'No pending actions',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Annual leave decisions, block leave changes and mutual '
                          'shift swaps awaiting action will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Icon(Icons.flight_takeoff, color: leaveRed),
                    SizedBox(width: 8),
                    Text(
                      'Floating annual leave',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Individual ALD requests awaiting a decision from Rosters.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (_requests.isEmpty)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: textGrey),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No floating annual leave actions.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._requests.map(_buildRequestCard),

                const SizedBox(height: 22),

                Row(
                  children: [
                    Icon(Icons.swap_horiz_outlined, color: Color(0xFF1769AA)),
                    SizedBox(width: 8),
                    Text(
                      'Mutual shift swaps',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Shift swaps waiting for a decision from Rosters / DTCM.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (_shiftSwaps.isEmpty)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: textGrey),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No pending mutual shift swaps.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._shiftSwaps.map(_buildShiftSwapCard),

                const SizedBox(height: 22),

                Row(
                  children: [
                    Icon(Icons.swap_horiz_outlined, color: leaveRed),
                    SizedBox(width: 8),
                    Text(
                      'Block annual leave',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Block moves, mutual swaps and future requests waiting '
                  'in the Union send queue.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (_blockActions.isEmpty)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: textGrey),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No block annual leave actions.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._blockActions.map(_buildBlockActionCard),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.currentTabIndex,
        onDestinationSelected: (int index) {
          Navigator.of(context).pop(index);
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
            icon: Icon(Icons.flight_takeoff),
            selectedIcon: Icon(Icons.flight),
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
}

class _DashboardPage extends StatefulWidget {
  const _DashboardPage({
    required this.email,
    required this.onUpload,
    required this.onCalendarAction,
    required this.onRosterChanged,
    required this.refreshVersion,
  });

  final String email;
  final VoidCallback onUpload;
  final void Function(DateTime date, _CalendarDayAction action)
  onCalendarAction;
  final VoidCallback onRosterChanged;
  final int refreshVersion;

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color workingGreen = Color(0xFF2E7D32);
  static const Color restYellow = Color(0xFFFFD54F);
  static const Color leaveRed = Color(0xFFD64545);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color textGrey = Color(0xFF52667A);

  final DutyResolver _dutyResolver = DutyResolver();
  final Hidden18Service _hidden18Service = const Hidden18Service();
  final ManualDutyService _manualDutyService = ManualDutyService();
  final JobCardService _jobCardService = JobCardService();
  final AnnualLeaveService _annualLeaveService = AnnualLeaveService();

  Hidden18Result? _hidden18Result;
  Duty? _todayDuty;
  Map<String, Duty> _thisWeekDuties = <String, Duty>{};
  Map<String, AnnualLeaveRequest> _thisWeekLeaveRequests =
      <String, AnnualLeaveRequest>{};

  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDashboardDuties();
  }

  @override
  void didUpdateWidget(covariant _DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _loadDashboardDuties();
    }
  }

  Future<void> _loadDashboardDuties() async {
    setState(() {
      _isLoading = true;
      _hidden18Result = null;
      _loadError = null;
    });

    try {
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);

      final List<DateTime> nextSevenDates = List<DateTime>.generate(
        7,
        (int index) => today.add(Duration(days: index + 1)),
        growable: false,
      );

      final DateTime fatigueRangeStart = today.subtract(
        const Duration(days: 13),
      );
      final DateTime fatigueRangeEnd = nextSevenDates.last;

      final Future<Map<String, Duty>> dutiesFuture = _dutyResolver
          .getResolvedDutiesForRange(fatigueRangeStart, fatigueRangeEnd);

      final Future<Map<String, AnnualLeaveRequest>> leaveRequestsFuture =
          _annualLeaveService.getRequestsForRange(today, fatigueRangeEnd);

      final Map<String, Duty> fatigueRangeDuties = await dutiesFuture;
      final Map<String, AnnualLeaveRequest> thisWeekLeaveRequests =
          await leaveRequestsFuture;

      final Map<String, Duty> thisWeekDuties = <String, Duty>{
        for (final DateTime date in nextSevenDates)
          if (fatigueRangeDuties[_dashboardDateKey(date)] != null)
            _dashboardDateKey(date):
                fatigueRangeDuties[_dashboardDateKey(date)]!,
      };

      final Hidden18Result evaluatedHidden18 = _hidden18Service.evaluate(
        fatigueRangeDuties.values,
      );

      // Calculate today's consecutive-day figure separately so the Home
      // screen does not accidentally show the streak at the end of the
      // seven-day future look-ahead period.
      final Hidden18Result currentConsecutiveResult = _hidden18Service.evaluate(
        fatigueRangeDuties.values.where(
          (Duty duty) => !duty.date.isAfter(today),
        ),
      );

      // The current rolling total is the actual seven calendar days ending
      // today. Hidden18Service sees this seven-day slice in chronological
      // order, so its greatest rolling value is the total for that slice.
      final DateTime currentRollingStart = today.subtract(
        const Duration(days: 6),
      );

      final Hidden18Result currentRollingResult = _hidden18Service.evaluate(
        fatigueRangeDuties.values.where(
          (Duty duty) =>
              !duty.date.isBefore(currentRollingStart) &&
              !duty.date.isAfter(today),
        ),
      );

      final Hidden18Result hidden18Result = Hidden18Result(
        warnings: evaluatedHidden18.warnings
            .where(
              (Hidden18Warning warning) =>
                  !warning.date.isBefore(today) &&
                  !warning.date.isAfter(fatigueRangeEnd),
            )
            .toList(growable: false),
        consecutiveDaysWorked: currentConsecutiveResult.consecutiveDaysWorked,
        rollingSevenDayMinutes: currentRollingResult.rollingSevenDayMinutes,
      );

      final Duty? todayDuty = fatigueRangeDuties[_dashboardDateKey(today)];

      if (!mounted) {
        return;
      }

      // Show Today and This Week immediately.
      setState(() {
        _todayDuty = todayDuty;
        _thisWeekDuties = thisWeekDuties;
        _thisWeekLeaveRequests = thisWeekLeaveRequests;
        _hidden18Result = hidden18Result;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _todayDuty = null;
        _hidden18Result = null;
        _thisWeekDuties = <String, Duty>{};
        _thisWeekLeaveRequests = <String, AnnualLeaveRequest>{};
        _isLoading = false;
        _loadError = error is DutyResolverException
            ? error.message
            : 'Roster Buddy could not load your roster.';
      });
    }
  }

  Widget _buildHidden18StatusCard() {
    final Hidden18Result? result = _hidden18Result;
    final bool hasBreach = result?.hasWarnings == true;

    final Color statusColour = hasBreach ? leaveRed : workingGreen;

    final String title;
    final String subtitle;

    if (_isLoading || result == null) {
      title = 'Checking Hidden 18…';
      subtitle = 'Fatigue status is loading.';
    } else if (hasBreach) {
      final int count = result.warnings.length;
      title = '$count Hidden 18 breach${count == 1 ? '' : 'es'}';
      subtitle =
          'A rule is breached today or forecast to be breached within '
          'the next 7 days. Tap to review.';
    } else {
      title = 'Hidden 18 clear';
      subtitle =
          'No Hidden 18 rule breaches detected today or within the next '
          '7 days.';
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showHidden18Check,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: statusColour, width: 6)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: statusColour.withValues(alpha: 0.12),
                child: Icon(
                  hasBreach
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: statusColour,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: hasBreach ? leaveRed : Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35),
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

  Future<void> _showHidden18Check() async {
    final Hidden18Result? result = _hidden18Result;

    if (_isLoading || result == null) {
      showMessage(context, 'Fatigue information is still loading.');
      return;
    }

    if (!result.hasWarnings) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: workingGreen),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Hidden 18 check',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Hidden 18 warnings are currently detected in the '
                    'roster period checked.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Current consecutive working days: '
                    '${result.consecutiveDaysWorked}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Current rolling 7-day total: '
                    '${_formatHidden18Minutes(result.rollingSevenDayMinutes)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: warningOrange),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Hidden 18 warnings',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: result.warnings.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final Hidden18Warning warning = result.warnings[index];

                      return ListTile(
                        leading: const Icon(
                          Icons.warning_amber_rounded,
                          color: warningOrange,
                        ),
                        title: Text(
                          _hidden18WarningTitle(warning.type),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          '${_displayHidden18Date(warning.date)}\n'
                          '${warning.message}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Text(
                    '${result.warnings.length} warning'
                    '${result.warnings.length == 1 ? '' : 's'} detected.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _hidden18WarningTitle(Hidden18WarningType type) {
    switch (type) {
      case Hidden18WarningType.shiftLength:
        return 'Duty exceeds 12 hours';
      case Hidden18WarningType.minimumRest:
        return 'Less than 12 hours rest';
      case Hidden18WarningType.rollingSevenDays:
        return 'More than 72 hours in 7 days';
      case Hidden18WarningType.consecutiveDays:
        return 'More than 13 consecutive days';
    }
  }

  static String _formatHidden18Minutes(int minutes) {
    final int hours = minutes ~/ 60;
    final int remainder = minutes % 60;

    return '${hours}h ${remainder.toString().padLeft(2, '0')}m';
  }

  static String _displayHidden18Date(DateTime date) {
    return displayDate(date);
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
              Text(
                'Welcome back',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(widget.email, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 22),

              const SectionTitle(icon: Icons.today_outlined, title: 'Today'),
              const SizedBox(height: 10),
              _buildTodayCard(),

              const SizedBox(height: 22),
              const SectionTitle(
                icon: Icons.calendar_view_week_outlined,
                title: 'Next 7 days',
              ),
              const SizedBox(height: 10),
              _buildNextSevenDaysCard(),

              const SizedBox(height: 22),
              _buildHidden18StatusCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextSevenDaysCard() {
    if (_isLoading) {
      return _buildLoadingCard('Loading next 7 days…');
    }

    if (_loadError != null) {
      return _buildErrorCard();
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final List<DateTime> dates = List<DateTime>.generate(
      7,
      (int index) => today.add(Duration(days: index + 1)),
      growable: false,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int index = 0; index < dates.length; index++) ...[
              Expanded(
                child: _buildDashboardWeekTile(
                  date: dates[index],
                  duty: _thisWeekDuties[_dashboardDateKey(dates[index])],
                  leaveRequest:
                      _thisWeekLeaveRequests[_dashboardDateKey(dates[index])],
                ),
              ),
              if (index < dates.length - 1) const SizedBox(width: 5),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardWeekTile({
    required DateTime date,
    required Duty? duty,
    required AnnualLeaveRequest? leaveRequest,
  }) {
    final bool isToday = _sameDashboardDate(date, DateTime.now());
    final bool isGrantedAnnualLeave =
        leaveRequest?.status == AnnualLeaveRequestStatus.granted;

    final Color colour = isGrantedAnnualLeave
        ? leaveRed
        : _dashboardWeekColour(duty);

    final bool darkText =
        !isGrantedAnnualLeave &&
        (duty == null ||
            duty.dutyType == DutyType.restDay ||
            duty.dutyType == DutyType.unavailable);

    final Color f…51304 tokens truncated…                                   return;
                                          }

                                          if (selectedOption == 'Mutual swap') {
                                            if (driverNameController.text
                                                    .trim()
                                                    .isEmpty ||
                                                payrollController.text
                                                    .trim()
                                                    .isEmpty ||
                                                requestedDateController.text
                                                    .trim()
                                                    .isEmpty ||
                                                requestedTurnController.text
                                                    .trim()
                                                    .isEmpty) {
                                              _showCalendarMessage(
                                                'Please enter the other driver, '
                                                'payroll number, proposed date and '
                                                'turn number.',
                                              );
                                              return;
                                            }

                                            try {
                                              DateTime? requestedSwapDate;
                                              JobCardMatch? requestedJobCard;
                                              Duty? requestedDateOriginalDuty;

                                              if (confirmedWithRosters) {
                                                requestedSwapDate =
                                                    _shiftSwapService
                                                        .parseRequestedDate(
                                                          requestedDateController
                                                              .text
                                                              .trim(),
                                                        );

                                                requestedJobCard =
                                                    await _jobCardService
                                                        .findMatchingJobCard(
                                                          turnNumber:
                                                              requestedTurnController
                                                                  .text
                                                                  .trim(),
                                                          dutyDate:
                                                              requestedSwapDate,
                                                        );

                                                if (requestedJobCard == null ||
                                                    requestedJobCard
                                                        .jobCard
                                                        .bookOn
                                                        .trim()
                                                        .isEmpty ||
                                                    requestedJobCard
                                                        .jobCard
                                                        .bookOff
                                                        .trim()
                                                        .isEmpty) {
                                                  _showCalendarMessage(
                                                    'Roster Buddy could not find a valid Job Card '
                                                    'for that turn on the proposed date.',
                                                  );
                                                  return;
                                                }

                                                final bool sameDate =
                                                    _dateKey(
                                                      requestedSwapDate,
                                                    ) ==
                                                    _dateKey(date);

                                                if (!sameDate) {
                                                  requestedDateOriginalDuty =
                                                      await _dutyResolver
                                                          .getDutyForDate(
                                                            requestedSwapDate,
                                                          );

                                                  if (requestedDateOriginalDuty
                                                          ?.dutyType
                                                          .countsAsWorking ==
                                                      true) {
                                                    _showCalendarMessage(
                                                      'You already have a working duty on '
                                                      '${_fullDate(requestedSwapDate)}. '
                                                      'Roster Buddy will not apply this swap automatically.',
                                                    );
                                                    return;
                                                  }
                                                }
                                              }

                                              await _shiftSwapService
                                                  .createRequest(
                                                    originalDuty: originalDuty,
                                                    requestedDate:
                                                        requestedDateController
                                                            .text
                                                            .trim(),
                                                    requestedTurnNumber:
                                                        requestedTurnController
                                                            .text
                                                            .trim(),
                                                    otherDriverName:
                                                        driverNameController
                                                            .text
                                                            .trim(),
                                                    otherPayrollNumber:
                                                        payrollController.text
                                                            .trim(),
                                                    requestedBookOn:
                                                        requestedJobCard
                                                            ?.jobCard
                                                            .bookOn,
                                                    requestedBookOff:
                                                        requestedJobCard
                                                            ?.jobCard
                                                            .bookOff,
                                                    type: 'Mutual swap',
                                                    confirmedWithRosters:
                                                        confirmedWithRosters,
                                                    notes: notesController.text
                                                        .trim(),
                                                  );

                                              if (!mounted) {
                                                return;
                                              }

                                              if (confirmedWithRosters) {
                                                final DateTime swapDate =
                                                    requestedSwapDate!;
                                                final JobCardMatch jobCard =
                                                    requestedJobCard!;
                                                final bool sameDate =
                                                    _dateKey(swapDate) ==
                                                    _dateKey(date);

                                                final String otherDriver =
                                                    driverNameController.text
                                                        .trim();
                                                final String otherPayroll =
                                                    payrollController.text
                                                        .trim();

                                                if (sameDate) {
                                                  await _manualDutyService
                                                      .saveMutualSwapWorkingDuty(
                                                        date: date,
                                                        turnNumber: jobCard
                                                            .jobCard
                                                            .turnNumber,
                                                        bookOn: jobCard
                                                            .jobCard
                                                            .bookOn,
                                                        bookOff: jobCard
                                                            .jobCard
                                                            .bookOff,
                                                        otherDriverName:
                                                            otherDriver,
                                                        otherPayrollNumber:
                                                            otherPayroll,
                                                        originalDuty:
                                                            originalDuty,
                                                      );
                                                } else {
                                                  await _manualDutyService
                                                      .saveMutualSwapRestDay(
                                                        date: date,
                                                        originalDuty:
                                                            originalDuty,
                                                        otherDriverName:
                                                            otherDriver,
                                                        otherPayrollNumber:
                                                            otherPayroll,
                                                      );

                                                  await _manualDutyService
                                                      .saveMutualSwapWorkingDuty(
                                                        date: swapDate,
                                                        turnNumber: jobCard
                                                            .jobCard
                                                            .turnNumber,
                                                        bookOn: jobCard
                                                            .jobCard
                                                            .bookOn,
                                                        bookOff: jobCard
                                                            .jobCard
                                                            .bookOff,
                                                        otherDriverName:
                                                            otherDriver,
                                                        otherPayrollNumber:
                                                            otherPayroll,
                                                        originalDuty:
                                                            requestedDateOriginalDuty,
                                                      );
                                                }

                                                await _loadMonth();

                                                if (!mounted) {
                                                  return;
                                                }

                                                if (dialogContext.mounted) {
                                                  Navigator.of(
                                                    dialogContext,
                                                  ).pop();
                                                }

                                                _showCalendarMessage(
                                                  sameDate
                                                      ? 'Mutual swap applied. '
                                                            'Turn ${jobCard.jobCard.turnNumber} is now shown for ${_fullDate(date)}.'
                                                      : 'Mutual swap applied. '
                                                            '${_fullDate(date)} is now a Rest Day and '
                                                            'Turn ${jobCard.jobCard.turnNumber} is shown on ${_fullDate(swapDate)}.',
                                                );
                                                return;
                                              }

                                              if (!confirmedWithRosters) {
                                                final SupabaseClient supabase =
                                                    Supabase.instance.client;

                                                final User? user =
                                                    supabase.auth.currentUser;

                                                String depot = '';
                                                String payrollNumber = '';

                                                if (user != null) {
                                                  final Map<String, dynamic>?
                                                  profile = await supabase
                                                      .from('driver_profiles')
                                                      .select(
                                                        'display_name, depot, payroll_number',
                                                      )
                                                      .eq('user_id', user.id)
                                                      .maybeSingle();

                                                  final Map<String, dynamic>
                                                  metadata =
                                                      user.userMetadata ??
                                                      <String, dynamic>{};


                                                  depot =
                                                      (profile?['depot'] ??
                                                              metadata['depot'] ??
                                                              '')
                                                          .toString()
                                                          .trim();

                                                  payrollNumber =
                                                      (profile?['payroll_number'] ??
                                                              metadata['payroll_number'] ??
                                                              '')
                                                          .toString()
                                                          .trim();
                                                }

                                                final String dutyDate =
                                                    _fullDate(date);

                                                final String otherDriverName =
                                                    driverNameController.text
                                                        .trim();

                                                final String otherPayroll =
                                                    payrollController.text
                                                        .trim();

                                                final String proposedDate =
                                                    requestedDateController.text
                                                        .trim();

                                                final String proposedTurn =
                                                    requestedTurnController.text
                                                        .trim();

                                                final String notes =
                                                    notesController.text.trim();

                                                final String body =
                                                    'Please can I request a mutual shift swap.\n\n'
                                                    'My current duty:\n'
                                                    '$dutyDate'
                                                    '${originalDuty.turnNumber == null ? '' : '\nTurn: ${originalDuty.turnNumber}'}'
                                                    '${originalDuty.bookOn == null ? '' : '\nBook on: ${originalDuty.bookOn}'}'
                                                    '${originalDuty.bookOff == null ? '' : '\nBook off: ${originalDuty.bookOff}'}'
                                                    '\n\n'
                                                    'Proposed swap with:\n'
                                                    '$otherDriverName\n'
                                                    'Payroll Number: $otherPayroll\n'
                                                    'Proposed duty date: $proposedDate\n'
                                                    'Turn: $proposedTurn'
                                                    '${notes.isEmpty ? '' : '\n\nNotes:\n$notes'}'
                                                    '\n\n${await driverNumberEmailLine()}'
                                                    '${payrollNumber.isEmpty ? '' : '\nPayroll Number: $payrollNumber'}'
                                                    '${depot.isEmpty ? '' : '\n$depot'}';

                                                final String subject =
                                                    'Mutual Shift Swap Request - $dutyDate';

                                                final Uri emailUri =
                                                    _rosterBuddyMailUri(
                                                      subject: subject,
                                                      body: body,
                                                    );

                                                if (!dialogContext.mounted) {
                                                  return;
                                                }

                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();

                                                final bool opened =
                                                    await launchUrl(
                                                      emailUri,
                                                      mode: LaunchMode
                                                          .platformDefault,
                                                      webOnlyWindowName: '_self',
                                                    );

                                                if (!mounted) {
                                                  return;
                                                }

                                                if (!opened) {
                                                  _showCalendarMessage(
                                                    'Roster Buddy could not open the email app.',
                                                  );
                                                }

                                                return;
                                              }

                                              if (dialogContext.mounted) {
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              }

                                              _showCalendarMessage(
                                                'Mutual swap recorded.',
                                              );
                                            } on StateError catch (error) {
                                              _showCalendarMessage(
                                                error.message,
                                              );
                                            } catch (error) {
                                              _showCalendarMessage(
                                                'Unable to create the shift change '
                                                'request: $error',
                                              );
                                            }

                                            return;
                                          }
                                        },
                                  child: const Text('Continue'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
          );
        },
      );
    } finally {
      driverNameController.dispose();
      payrollController.dispose();
      requestedDateController.dispose();
      requestedTurnController.dispose();
      notesController.dispose();
    }
  }

  Widget _shiftChangeOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final Color background = selected
        ? CupertinoColors.activeBlue.withValues(alpha: 0.12)
        : CupertinoColors.systemGrey6.resolveFrom(context);

    final Color border = selected
        ? CupertinoColors.activeBlue.resolveFrom(context)
        : const Color(0x00000000);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: selected ? 1.5 : 0),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 24,
              color: selected
                  ? CupertinoColors.activeBlue.resolveFrom(context)
                  : CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.chevron_right,
              size: 20,
              color: selected
                  ? CupertinoColors.activeBlue.resolveFrom(context)
                  : CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftChangeTextField({
    required TextEditingController controller,
    required String placeholder,
    required TextInputType keyboardType,
    int maxLines = 1,
  }) {
    return CupertinoTextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      placeholder: placeholder,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Future<void> _confirmMoveRestDayHere({required DateTime date, required Duty originalDuty}) async {
    try {
      final changed = await moveRestDays(context, date, pickDates: _pickRestDayDates);
      if (changed && mounted) {
        widget.onRosterChanged();
        await _loadMonth();
      }
    } catch (error) {
      if (mounted) _showCalendarMessage('Could not move rest days: $error');
    }
  }

  String _dayActionLabel(_CalendarDayAction action) {
    switch (action) {
      case _CalendarDayAction.viewDay:
        return 'View day';
      case _CalendarDayAction.editTimes:
        return 'Edit book-on/off time';
      case _CalendarDayAction.selectTurnNumber:
        return 'Select turn number';
      case _CalendarDayAction.manualChange:
        return 'Manual change';
      case _CalendarDayAction.shiftSwap:
        return 'Mutual Swap';
      case _CalendarDayAction.moveRestDays:
        return 'Move rest days';
      case _CalendarDayAction.moveRestDayHere:
        return 'Move rest day here';
      case _CalendarDayAction.requestAnnualLeave:
        return 'Request annual leave';
      case _CalendarDayAction.manageAnnualLeave:
        return 'Manage annual leave';
      case _CalendarDayAction.allocateShift:
        return 'Allocate shift – RDW';
      case _CalendarDayAction.makeSundayAvailable:
        return 'Make myself available';
    }
  }

  Widget _buildAnnualLeaveRequestStatus(AnnualLeaveRequest request) {
    String title;
    String description;
    Color colour;
    IconData icon;

    switch (request.status) {
      case AnnualLeaveRequestStatus.requested:
        title = 'Annual leave requested';
        description =
            'Your rostered duty remains allocated while the request is awaiting a decision.';
        colour = leaveRed;
        icon = Icons.schedule_outlined;

      case AnnualLeaveRequestStatus.abeyance:
        title = 'Annual leave – abeyance';

        if (request.queuePosition != null) {
          description =
              'Queue position #${request.queuePosition}. Your rostered duty remains allocated until the leave is granted.';
        } else {
          description =
              'Your request is being held in abeyance. Your rostered duty remains allocated until the leave is granted.';
        }

        colour = const Color(0xFFF59E0B);
        icon = Icons.hourglass_top_outlined;

      case AnnualLeaveRequestStatus.granted:
        title = 'Annual leave granted';
        description = request.cancellationPending
                              ? 'Cancellation pending — leave stays granted until Rosters confirms.'
                              : 'This annual leave request has been granted.';
        colour = leaveRed;
        icon = Icons.event_available_outlined;

      case AnnualLeaveRequestStatus.cancelled:
        title = 'Annual leave request cancelled';
        description =
            'The request was cancelled and the allocated rostered duty applies again.';
        colour = textGrey;
        icon = Icons.cancel_outlined;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colour, size: 21),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colour,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (request.status == AnnualLeaveRequestStatus.abeyance &&
                  request.queuePosition != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '#${request.queuePosition}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            description,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35),
          ),
          if (request.notes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              request.notes!.trim(),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isPermanentlyUnavailableSunday(Duty? duty) {
    if (duty == null) {
      return false;
    }

    return duty.date.weekday == DateTime.sunday &&
        duty.dutyType == DutyType.unavailable &&
        duty.rawText == 'permanent_sunday_unavailable';
  }

  Future<void> _makeSundayAvailable({required DateTime date}) async {
    try {
      await _sundayAvailabilityService.makeSundayAvailable(date);

      await _loadMonth();

      if (!mounted) {
        return;
      }

      _showCalendarMessage('You are now available to work ${_fullDate(date)}.');
    } on SundayAvailabilityException catch (error) {
      if (!mounted) {
        return;
      }

      _showCalendarMessage(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showCalendarMessage(
        'Roster Buddy could not update your Sunday availability.',
      );
    }
  }

  void _showCalendarMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _chooseGrantedAnnualLeaveCancellationScope({
    required DateTime date,
  }) async {
    final String? choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext popupContext) {
        return CupertinoActionSheet(
          title: const Text('Cancel annual leave'),
          message: Text(_fullDate(date)),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop('single');
              },
              child: const Text('Just this date'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop('multiple');
              },
              child: const Text('Multiple dates'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(popupContext).pop();
            },
            child: const Text('Back'),
          ),
        );
      },
    );

    if (!mounted || choice == null) {
      return;
    }

    if (choice == 'single') {
      await _processGrantedAnnualLeaveCancellation(<DateTime>[date]);
      return;
    }

    widget.onOpenCalendar();

    setState(() {
      _isSelectingAnnualLeaveDates = false;
      _selectedAnnualLeaveDateKeys.clear();

      _isSelectingAnnualLeaveCancellationDates = true;
      _selectedAnnualLeaveCancellationDateKeys
        ..clear()
        ..add(_dateKey(date));

      _displayedMonth = DateTime(date.year, date.month);
    });

    await _loadMonth();
  }

  Future<void> _reviewSelectedAnnualLeaveCancellationDates() async {
    if (_selectedAnnualLeaveCancellationDateKeys.isEmpty) {
      return;
    }

    final List<DateTime> dates =
        _selectedAnnualLeaveCancellationDateKeys.map(DateTime.parse).toList()
          ..sort();

    await _processGrantedAnnualLeaveCancellation(dates);
  }

  Future<void> _processGrantedAnnualLeaveCancellation(
    List<DateTime> dates,
  ) async {
    final requests = <AnnualLeaveRequest>[];
    for (final date in dates) {
      final request = _leaveRequestsByDate[_dateKey(date)];
      if (request == null || request.status != AnnualLeaveRequestStatus.granted) {
        _showCalendarMessage('Selected leave has changed. Refresh and try again.');
        return;
      }
      requests.add(request);
    }
    final changed = await manageFloatingLeaveCancellation(context: context, requests: requests);
    if (changed && mounted) {
      setState(() {
        _isSelectingAnnualLeaveCancellationDates = false;
        _selectedAnnualLeaveCancellationDateKeys.clear();
      });
      widget.onRosterChanged();
      await _loadMonth();
    }
  }

  Future<void> _showManageAnnualLeaveDialog({
    required DateTime date,
    required AnnualLeaveRequest request,
  }) async {
    final TextEditingController queueController = TextEditingController(
      text: request.queuePosition?.toString() ?? '',
    );

    bool isSaving = false;
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
                Future<void> finishChange({
                  required Future<AnnualLeaveRequest> Function() action,
                  required String successMessage,
                }) async {
                  if (isSaving) {
                    return;
                  }

                  setSheetState(() {
                    isSaving = true;
                    errorMessage = null;
                  });

                  try {
                    await action();

                    if (!sheetContext.mounted) {
                      return;
                    }

                    Navigator.of(sheetContext).pop();

                    await _loadMonth();

                    if (!mounted) {
                      return;
                    }

                    _showCalendarMessage(successMessage);
                  } on AnnualLeaveException catch (error) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      isSaving = false;
                      errorMessage = error.message;
                    });
                  } catch (_) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      isSaving = false;
                      errorMessage =
                          'Roster Buddy could not update this annual leave request.';
                    });
                  }
                }

                Future<void> moveToAbeyance() async {
                  final int? queuePosition = int.tryParse(
                    queueController.text.trim(),
                  );

                  if (queuePosition == null || queuePosition < 1) {
                    setSheetState(() {
                      errorMessage =
                          'Enter the current abeyance queue position.';
                    });
                    return;
                  }

                  await finishChange(
                    action: () => _annualLeaveService.markAbeyance(
                      requestId: request.id,
                      queuePosition: queuePosition,
                    ),
                    successMessage:
                        'Annual leave moved to abeyance at queue position #$queuePosition.',
                  );
                }

                Future<void> markGranted() async {
                  if (!sheetContext.mounted) {
                    return;
                  }

                  Navigator.of(sheetContext).pop();

                  await Future<void>.delayed(const Duration(milliseconds: 150));

                  if (!mounted) {
                    return;
                  }

                  await _recordRequestedAnnualLeaveDecision(
                    date: date,
                    request: request,
                  );
                }

                Future<void> cancelRequest() async {
                  if (!sheetContext.mounted) {
                    return;
                  }

                  Navigator.of(sheetContext).pop();

                  await Future<void>.delayed(const Duration(milliseconds: 150));

                  if (!mounted) {
                    return;
                  }

                  if (request.status == AnnualLeaveRequestStatus.granted) {
                    await _chooseGrantedAnnualLeaveCancellationScope(
                      date: date,
                    );
                    return;
                  }

                  await _cancelActiveAnnualLeaveRequest(
                    date: date,
                    request: request,
                  );
                }

                String statusTitle;

                switch (request.status) {
                  case AnnualLeaveRequestStatus.requested:
                    statusTitle = 'Awaiting decision';
                  case AnnualLeaveRequestStatus.abeyance:
                    statusTitle = request.queuePosition == null
                        ? 'Held in abeyance'
                        : 'Abeyance – queue position #${request.queuePosition}';
                  case AnnualLeaveRequestStatus.granted:
                    statusTitle = 'Annual leave granted';
                  case AnnualLeaveRequestStatus.cancelled:
                    statusTitle = 'Annual leave cancelled';
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
                            'Manage annual leave',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fullDate(date),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color:
                                  request.status ==
                                      AnnualLeaveRequestStatus.abeyance
                                  ? const Color(
                                      0xFFF59E0B,
                                    ).withValues(alpha: 0.10)
                                  : leaveRed.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusTitle,
                              style: TextStyle(
                                color:
                                    request.status ==
                                        AnnualLeaveRequestStatus.abeyance
                                    ? const Color(0xFFB45309)
                                    : leaveRed,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (request.status ==
                                  AnnualLeaveRequestStatus.requested ||
                              request.status ==
                                  AnnualLeaveRequestStatus.abeyance) ...[
                            const SizedBox(height: 18),
                            TextField(
                              controller: queueController,
                              enabled: !isSaving,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText:
                                    request.status ==
                                        AnnualLeaveRequestStatus.abeyance
                                    ? 'Abeyance queue position'
                                    : 'Queue position if placed in abeyance',
                                hintText: 'For example 3',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: isSaving ? null : moveToAbeyance,
                                icon: const Icon(Icons.hourglass_top_outlined),
                                label: Text(
                                  request.status ==
                                          AnnualLeaveRequestStatus.abeyance
                                      ? 'Update queue position'
                                      : 'Move to abeyance',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: isSaving ? null : markGranted,
                                icon: const Icon(
                                  Icons.event_available_outlined,
                                ),
                                label: const Text('Mark annual leave granted'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: leaveRed,
                                ),
                              ),
                            ),
                          ],
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
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: isSaving ? null : cancelRequest,
                              icon: const Icon(Icons.cancel_outlined),
                              label: Text(
                                request.status ==
                                        AnnualLeaveRequestStatus.granted
                                    ? 'Cancel annual leave'
                                    : 'Cancel annual leave request',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: leaveRed,
                              ),
                            ),
                          ),
                          if (isSaving) ...[
                            const SizedBox(height: 18),
                            const Center(child: CircularProgressIndicator()),
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

    queueController.dispose();
  }

  Future<void> _showEditDutyDialog({
    required DateTime date,
    required Duty originalDuty,
  }) async {
    final TextEditingController turnController = TextEditingController(
      text: originalDuty.turnNumber?.trim() ?? '',
    );
    final TextEditingController bookOnController = TextEditingController(
      text: originalDuty.bookOn?.trim() ?? '',
    );
    final TextEditingController bookOffController = TextEditingController(
      text: originalDuty.bookOff?.trim() ?? '',
    );
    final TextEditingController remarksController = TextEditingController(
      text: originalDuty.remarks?.trim() ?? '',
    );

    bool isSaving = false;
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
                Future<void> saveDuty() async {
                  final String bookOn = _normaliseTimeInput(
                    bookOnController.text,
                  );
                  final String bookOff = _normaliseTimeInput(
                    bookOffController.text,
                  );

                  if (!_isValidTime(bookOn) || !_isValidTime(bookOff)) {
                    setSheetState(() {
                      errorMessage =
                          'Enter valid 24-hour times, for example 0800 or 08:00.';
                    });
                    return;
                  }

                  setSheetState(() {
                    isSaving = true;
                    errorMessage = null;
                  });

                  try {
                    await _manualDutyService.saveEditedDuty(
                      date: date,
                      turnNumber: turnController.text,
                      bookOn: bookOn,
                      bookOff: bookOff,
                      remarks: remarksController.text,
                      originalDuty: originalDuty,
                    );

                    if (!sheetContext.mounted) {
                      return;
                    }

                    Navigator.of(sheetContext).pop();

                    await _loadMonth();

                    if (!mounted) {
                      return;
                    }

                    _showCalendarMessage(
                      'Manual duty changes saved for ${_fullDate(date)}.',
                    );
                  } catch (error) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      isSaving = false;
                      errorMessage = error is ManualDutyException
                          ? error.message
                          : 'Roster Buddy could not save the duty changes.';
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
                            'Edit duty',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fullDate(date),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: turnController,
                            enabled: !isSaving,
                            decoration: const InputDecoration(
                              labelText: 'Turn number',
                              hintText: 'For example 205',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: bookOnController,
                                  enabled: !isSaving,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Book on',
                                    hintText: '0800',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: bookOffController,
                                  enabled: !isSaving,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Book off',
                                    hintText: '1630',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: remarksController,
                            enabled: !isSaving,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Remarks',
                              hintText: 'Optional note about this change',
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
                              onPressed: isSaving ? null : saveDuty,
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                isSaving ? 'Saving…' : 'Save manual change',
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

    turnController.dispose();
    bookOnController.dispose();
    bookOffController.dispose();
    remarksController.dispose();
  }

  Future<void> _showAllocateShiftDialog({
    required DateTime date,
    required Duty originalDuty,
  }) async {
    const String manualSelection = '__MANUAL_RDW__';

    List<JobCardChoice> choices = <JobCardChoice>[];

    try {
      choices = await _jobCardService.findValidJobCardsForDate(dutyDate: date);
    } catch (_) {
      // Manual entry remains available if Job Cards cannot be loaded.
    }

    if (!mounted) {
      return;
    }

    String selectedTurn = choices.isNotEmpty
        ? choices.first.jobCard.turnNumber
        : manualSelection;

    final TextEditingController manualTurnController = TextEditingController();

    final TextEditingController bookOnController = TextEditingController(
      text: choices.isNotEmpty ? choices.first.jobCard.bookOn : '',
    );

    final TextEditingController bookOffController = TextEditingController(
      text: choices.isNotEmpty ? choices.first.jobCard.bookOff : '',
    );

    bool isSaving = false;
    String? formError;

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setSheetState) {
            Future<void> save() async {
              final bool manual = selectedTurn == manualSelection;

              final String turnNumber = manual
                  ? manualTurnController.text.trim()
                  : selectedTurn.trim();

              final String bookOn = _normaliseTimeInput(bookOnController.text);
              final String bookOff = _normaliseTimeInput(
                bookOffController.text,
              );

              if (turnNumber.isEmpty) {
                setSheetState(() {
                  formError = 'Enter or select a turn number.';
                });
                return;
              }

              if (!_isValidTime(bookOn) || !_isValidTime(bookOff)) {
                setSheetState(() {
                  formError =
                      'Enter valid 24-hour times, for example 0800 or 08:00.';
                });
                return;
              }

              setSheetState(() {
                isSaving = true;
                formError = null;
              });

              try {
                await _manualDutyService.saveRestDayWorked(
                  date: date,
                  turnNumber: turnNumber,
                  bookOn: bookOn,
                  bookOff: bookOff,
                  originalDuty: originalDuty,
                );

                if (!sheetContext.mounted) {
                  return;
                }

                Navigator.of(sheetContext).pop(true);
              } catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  isSaving = false;
                  formError = error is ManualDutyException
                      ? error.message
                      : 'Roster Buddy could not save this RDW shift.';
                });
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  MediaQuery.viewInsetsOf(context).bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Allocate shift – RDW',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _fullDate(date),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 18),

                      DropdownButtonFormField<String>(
                        initialValue: selectedTurn,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Turn / Job Card',
                          border: OutlineInputBorder(),
                        ),
                        items: <DropdownMenuItem<String>>[
                          ...choices.map(
                            (JobCardChoice choice) => DropdownMenuItem<String>(
                              value: choice.jobCard.turnNumber,
                              child: Text(
                                'Turn ${choice.jobCard.turnNumber}'
                                '${choice.jobCard.bookOn.trim().isEmpty ? '' : ' • ${choice.jobCard.bookOn}–${choice.jobCard.bookOff}'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const DropdownMenuItem<String>(
                            value: manualSelection,
                            child: Text('Manual / cross-depot duty'),
                          ),
                        ],
                        onChanged: isSaving
                            ? null
                            : (String? value) {
                                if (value == null) {
                                  return;
                                }

                                setSheetState(() {
                                  selectedTurn = value;
                                  formError = null;

                                  if (value != manualSelection) {
                                    for (final JobCardChoice choice
                                        in choices) {
                                      if (choice.jobCard.turnNumber == value) {
                                        bookOnController.text =
                                            choice.jobCard.bookOn;
                                        bookOffController.text =
                                            choice.jobCard.bookOff;
                                        break;
                                      }
                                    }
                                  }
                                });
                              },
                      ),

                      if (selectedTurn == manualSelection) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: manualTurnController,
                          enabled: !isSaving,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Manual turn / duty reference',
                            hintText: 'For example WO216 or cross-depot cover',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: bookOnController,
                              enabled: !isSaving,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: 'Book on',
                                hintText: '0800',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: bookOffController,
                              enabled: !isSaving,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(
                                labelText: 'Book off',
                                hintText: '1630',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),
                      Text(
                        'Selecting a Job Card fills its booked times automatically. '
                        'Manual or cross-depot duties can still be entered.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35),
                      ),

                      if (formError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          formError!,
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
                          onPressed: isSaving ? null : save,
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_circle_outline),
                          label: Text(
                            isSaving ? 'Saving RDW…' : 'Save Rest Day Worked',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: workingGreen,
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

    manualTurnController.dispose();
    bookOnController.dispose();
    bookOffController.dispose();

    if (saved != true || !mounted) {
      return;
    }

    await _loadMonth();

    if (!mounted) {
      return;
    }

    _showCalendarMessage('Rest Day Worked saved for ${_fullDate(date)}.');
  }

  static String _normaliseTimeInput(String value) {
    String cleaned = value.trim().replaceAll(RegExp(r'\s+'), '');

    if (cleaned.isEmpty) {
      return '';
    }

    // Already written as HH:mm.
    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(cleaned)) {
      final List<String> parts = cleaned.split(':');
      return '${parts[0].padLeft(2, '0')}:${parts[1]}';
    }

    // Accept railway-style times such as 815 or 0800.
    if (RegExp(r'^\d{3,4}$').hasMatch(cleaned)) {
      cleaned = cleaned.padLeft(4, '0');
      return '${cleaned.substring(0, 2)}:${cleaned.substring(2)}';
    }

    return cleaned;
  }

  bool _isValidTime(String value) {
    final Match? match = RegExp(
      r'^([01]\d|2[0-3]):([0-5]\d)$',
    ).firstMatch(value);

    return match != null;
  }

  Color _colourForDuty(DutyType type) {
    switch (type) {
      case DutyType.working:
      case DutyType.training:
      case DutyType.medical:
        return workingGreen;
      case DutyType.restDay:
      case DutyType.unavailable:
        return restYellow;
      case DutyType.annualLeave:
      case DutyType.sick:
      case DutyType.publicHoliday:
        return leaveRed;
      case DutyType.unknown:
        return railwayBlue;
    }
  }

  String _shortDutyLabel(Duty duty) {
    switch (duty.dutyType) {
      case DutyType.working:
        return duty.turnNumber?.trim().isNotEmpty == true
            ? 'T${duty.turnNumber!.trim()}'
            : 'Duty';
      case DutyType.training:
        return 'Training';
      case DutyType.medical:
        return 'Medical';
      case DutyType.restDay:
        return 'Rest';
      case DutyType.annualLeave:
        return 'Leave';
      case DutyType.sick:
        return 'Sick';
      case DutyType.publicHoliday:
        return 'Holiday';
      case DutyType.unavailable:
        return 'Unavailable';
      case DutyType.unknown:
        return 'Review';
    }
  }

  String _longDutyLabel(Duty duty) {
    switch (duty.dutyType) {
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
        return 'Roster status requires review';
    }
  }

  String _sourceLabel(RosterSource source) {
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

  String _monthTitle(DateTime date) {
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

    return '${months[date.month - 1]} ${date.year}';
  }

  String _fullDate(DateTime date) {
    return displayDate(date);
  }

  String _dateKey(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }
}

enum _CalendarDayAction {
  editTimes,
  selectTurnNumber,
  manualChange,
  shiftSwap,
  moveRestDayHere,
  moveRestDays,
  requestAnnualLeave,
  manageAnnualLeave,
  allocateShift,
  makeSundayAvailable,
  viewDay,
}

class _UnavailableTilePainter extends CustomPainter {
  const _UnavailableTilePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Yellow is the material background. Grey fills the lower-right half.
    final greyHalf = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(greyHalf, Paint()..color = const Color(0xFFB0B7BF));
  }

  @override
  bool shouldRepaint(_UnavailableTilePainter oldDelegate) => false;
}

class _CalendarLegendItem extends StatelessWidget {
  const _CalendarLegendItem({required this.colour, required this.label});

  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
                    subtitle: Text('Driver Number, payroll number and depot'),
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
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
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


class _PinnedDayAction extends StatelessWidget {
  const _PinnedDayAction({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class _PinnedDayPanel extends StatelessWidget {
  const _PinnedDayPanel({required this.summary, required this.children});
  final Widget summary;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => DayDetailsPanel(
    summary: summary,
    body: children.where((child) => child is! _PinnedDayAction).toList(),
    actions: children.whereType<_PinnedDayAction>().toList(),
  );
}

class DayShiftSummary extends StatefulWidget {
  const DayShiftSummary({super.key, required this.date, required this.duty, required this.annualLeave, required this.onChanged});
  final DateTime date;
  final Duty? duty;
  final bool annualLeave;
  final VoidCallback onChanged;
  @override
  State<DayShiftSummary> createState() => DayShiftSummaryState();
}
class DayShiftSummaryState extends State<DayShiftSummary> {
  late final TextEditingController _start = TextEditingController(text: widget.duty?.bookOn ?? '');
  late final TextEditingController _finish = TextEditingController(text: widget.duty?.bookOff ?? '');
  late String _savedStart = widget.duty?.bookOn ?? '';
  late String _savedFinish = widget.duty?.bookOff ?? '';
  final FocusNode _startFocus = FocusNode();
  final FocusNode _finishFocus = FocusNode();
  bool _editing = false, _saving = false;
  String? _error;
  Duty? get duty => widget.duty;
  DateTime get date => widget.date;
  bool get annualLeave => widget.annualLeave;
  bool get _canMakeAvailable =>
      !annualLeave &&
      duty?.dutyType == DutyType.unavailable &&
      date.weekday == DateTime.sunday &&
      (duty?.rawText == 'permanent_sunday_unavailable' ||
          duty?.rawText == 'post_block_sunday');

  late final Future<Duty?> _rosteredShift = DutyResolver()
      .getDutiesForDate(date)
      .then((duties) => duties.where((duty) => duty.dutyType.countsAsWorking).firstOrNull);

  bool _savingAvailability = false;

  Future<void> _makeAvailable() async {
    setState(() => _savingAvailability = true);
    try {
      await SundayAvailabilityService().makeSundayAvailable(date);
      if (!mounted) return;
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunday availability updated.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingAvailability = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update Sunday availability. Please retry.')),
      );
    }
  }

  @override
  void dispose() {
    _startFocus.dispose(); _finishFocus.dispose();
    _start.dispose(); _finish.dispose(); super.dispose();
  }
  void _beginEdit() {
    setState(() {
      _start.text = _savedStart.replaceAll(':', '');
      _finish.text = _savedFinish.replaceAll(':', '');
      _error = null;
      _editing = true;
    });
    // The field is already mounted, so focus is requested in the user's tap.
    // Deferring this until another frame can lose keyboard activation on iOS.
    _finish.selection = TextSelection(baseOffset: 0, extentOffset: _finish.text.length);
    _finishFocus.canRequestFocus = true;
    _finishFocus.requestFocus();
  }
  String? _clock(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 4) return null;
    final hour = int.parse(digits.substring(0,2)), minute = int.parse(digits.substring(2));
    if (hour > 23 || minute > 59) return null;
    return '${digits.substring(0,2)}:${digits.substring(2)}';
  }
  Future<void> _save() async {
    if (_saving) return;
    final on = _clock(_start.text), off = _clock(_finish.text);
    if (on == null || off == null) {
      setState(() => _error = 'Enter four digits for each time, e.g. 1711.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    FocusScope.of(context).unfocus();
    try {
      await ManualDutyService().saveEditedDuty(date: date,
        turnNumber: duty!.turnNumber ?? '', bookOn: on, bookOff: off,
        remarks: duty!.remarks ?? '', originalDuty: duty!);
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() { _savedStart = on; _savedFinish = off; _start.text = on; _finish.text = off; _editing = false; _saving = false; });
      widget.onChanged();
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'Could not save times. Please retry.'; });
    }
  }
  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shiftText = isDark ? const Color(0xFF102A20) : navy;
    const weekdays = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    final on = _start.text.trim();
    final off = _finish.text.trim();
    final onLeave = annualLeave || duty?.dutyType == DutyType.annualLeave;
    final timed = !onLeave && duty?.dutyType.countsAsWorking == true &&
        (on.isNotEmpty || off.isNotEmpty);
    final needsReview = !onLeave && duty != null &&
        (duty!.dutyType == DutyType.unknown ||
         (duty!.dutyType.countsAsWorking &&
          (_clock(on) == null || _clock(off) == null)));
    final overnight = timed && off.compareTo(on) < 0;
    final type = onLeave ? 'Annual leave' : duty == null ? 'No roster information' :
      duty!.dutyType.countsAsWorking ? (duty!.dutyType == DutyType.training ? 'Training' : duty!.dutyType == DutyType.medical ? 'Medical' : duty!.isRouteRefresh ? 'Route refresh' : duty!.isAmendedTurn ? 'Amended turn' : 'Working') : switch (duty!.dutyType) {
        DutyType.restDay => 'Rest day', DutyType.sick => 'Sick',
        DutyType.publicHoliday => 'Bank holiday', DutyType.unavailable => 'Unavailable',
        DutyType.annualLeave => 'Annual leave', _ => 'Review duty',
      };
    final colour = duty == null && !onLeave ? const Color(0xFF52667A) :
      onLeave ? const Color(0xFFD64545) :
      needsReview ? const Color(0xFF1769AA) :
      switch (duty!.dutyType) {
        DutyType.working || DutyType.training || DutyType.medical => isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32),
        DutyType.restDay || DutyType.unavailable => const Color(0xFFB88700),
        DutyType.sick || DutyType.publicHoliday => const Color(0xFFD64545),
        _ => const Color(0xFF1769AA),
      };
    final statusIcon = onLeave ? Icons.flight_takeoff :
      switch (duty?.dutyType) {
        DutyType.restDay => Icons.free_breakfast_outlined,
        DutyType.unavailable => Icons.block_outlined,
        DutyType.sick => Icons.sick_outlined,
        DutyType.publicHoliday => Icons.event_available_outlined,
        _ => Icons.info_outline,
      };
    final statusDetail = onLeave ? 'Annual leave recorded' :
      switch (duty?.dutyType) {
        DutyType.restDay => 'No shift allocated',
        DutyType.unavailable => 'Not available for work',
        DutyType.sick => 'Sickness recorded',
        DutyType.publicHoliday => 'Non-working day',
        null => 'No shift has been recorded for this date.',
        _ => '',
      };
    final reviewDetail = duty?.remarks?.trim().isNotEmpty == true
        ? duty!.remarks!.trim()
        : duty?.dutyType.countsAsWorking == true
          ? 'Start or finish time is missing or unclear. Check the uploaded document and use More day actions to correct it.'
          : 'Duty details need checking. Open Documents to check the source, then use More day actions to correct this day.';
    Widget clock(String label, String? value, bool nextDay) => Expanded(child: Column(children: [
      Text(label, style: TextStyle(color: shiftText, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      TextField(
        controller: label == 'Start' ? _start : _finish,
        focusNode: label == 'Start' ? _startFocus : _finishFocus,
        canRequestFocus: _editing && !_saving,
        readOnly: _saving,
        showCursor: _editing,
        enableInteractiveSelection: _editing,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        onTap: () { final controller = label == 'Start' ? _start : _finish; controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length); },
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          filled: false,
          fillColor: Colors.transparent,
          hintText: _editing ? 'HHMM' : '—',
          semanticCounterText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: _editing ? const UnderlineInputBorder() : InputBorder.none,
          enabledBorder: _editing ? const UnderlineInputBorder() : InputBorder.none,
          focusedBorder: _editing ? const UnderlineInputBorder() : InputBorder.none,
        ),
        style: TextStyle(fontSize: _editing ? 30 : 34, fontWeight: FontWeight.w900, color: shiftText),
      ),
      Text(nextDay ? '+1 day' : '', style: const TextStyle(color: Color(0xFF52667A))),
    ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_editing) Text('${weekdays[date.weekday-1]} ${date.day} ${months[date.month-1]} ${date.year}',
        style: TextStyle(color: navy, fontSize: 20, fontWeight: FontWeight.w900)),
      if (!_editing) const SizedBox(height: 8),
      if (timed) ...[
        Row(children: [
          Expanded(child: Text(type, style: TextStyle(color: colour, fontWeight: FontWeight.w800))),
          if (!annualLeave && duty != null) _RosterSourceBadge(source: duty!.source),
        ]),
        const SizedBox(height: 10),
      ] else ...[
        Container(
          key: const ValueKey('day-status-card'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: colour, width: 5)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colour.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(statusIcon, color: colour, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(type, style: TextStyle(color: navy, fontSize: 20, fontWeight: FontWeight.w800)),
              if (statusDetail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(statusDetail, style: TextStyle(color: navy)),
              ],
            ])),
            if (!annualLeave && duty != null) ...[
              const SizedBox(width: 8),
              _RosterSourceBadge(source: duty!.source,
                unavailable: duty!.dutyType == DutyType.unavailable),
            ],
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (_canMakeAvailable) ...[
        FutureBuilder<Duty?>(
          future: _rosteredShift,
          builder: (context, snapshot) {
            final shift = snapshot.data;
            if (shift == null) {
              return Text(snapshot.connectionState == ConnectionState.waiting
                  ? 'Loading rostered shift…'
                  : 'Rostered shift details unavailable');
            }
            final turn = shift.turnNumber?.trim();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(turn == null || turn.isEmpty
                  ? 'Rostered shift' : 'Rostered shift · Turn $turn'),
              subtitle: Text('${shift.bookOn ?? '—'}–${shift.bookOff ?? '—'}'),
            );
          },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _savingAvailability ? null : _makeAvailable,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Make myself available'),
        ),
        const SizedBox(height: 12),
      ],
      if (needsReview) Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1769AA).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline, color: Color(0xFF1769AA), size: 20),
                SizedBox(width: 8),
                Text('Needs review', style: TextStyle(color: navy, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Text(reviewDetail, style: TextStyle(color: navy)),
            ]),
          ),
        ),
      ),
      // Keep Save in the fields' tap region: dismissing focus on pointer-down
      // can move the sheet before the button receives pointer-up on iOS web.
      if (timed) TextFieldTapRegion(child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: isDark ? colour : colour.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Row(children: [clock('Start', on, false),
            Container(width: 1, height: 65, color: colour.withValues(alpha: 0.2)),
            clock('Finish', off, overnight)]),
          const Divider(),
          Row(children: [
            Expanded(child: Text(duty?.turnNumber?.trim().isNotEmpty == true ? 'Turn ${duty!.turnNumber}' : '',
              textAlign: TextAlign.center, style: TextStyle(color: shiftText, fontWeight: FontWeight.w800))),
            Expanded(child: canEditShiftTimes(date, on, off, DateTime.now()) && duty?.dutyType.countsAsWorking == true
              ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (_editing) IconButton(tooltip: 'Cancel time edit', onPressed: _saving ? null : () {
                  FocusScope.of(context).unfocus();
                  setState(() { _editing = false; _error = null; _start.text = _savedStart; _finish.text = _savedFinish; });
                }, icon: const Icon(Icons.close, size: 18)),
                Flexible(child: TextButton(onPressed: _saving ? null : _editing ? _save : _beginEdit,
                  child: Text(_saving ? 'Saving…' : _editing ? 'Save' : 'Edit times',
                    style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.black : null)))),
              ])
              : const SizedBox.shrink()),
          ]),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),

        ]),
      )),
    ]);
  }
}
