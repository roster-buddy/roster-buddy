Warning: truncated output (original token count: 101444)
Total output lines: 11380

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
      await _openUploadPicker();
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

  Future<void> _openUploadPicker() async {
    try {
      final UploadSource? selectedSource = await chooseUploadSource(context);
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
      onUpload: _openUploadPicker,
      onRosterChanged: _notifyRosterChanged,
    )),
  );

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
      await _openUploadPicker();
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
        onUpload: _openUploadPicker,
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
        onUpload: _openUploadPicker,
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
        onOpenDocuments: _openDepotDocuments,
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
            tooltip: 'Depot documents',
            onPressed: _openDepotDocuments,
            icon: const Icon(Icons.folder_open_outlined),
          ),
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
            await _openUploadPicker();
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
 …71444 tokens truncated…ting decision';
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
