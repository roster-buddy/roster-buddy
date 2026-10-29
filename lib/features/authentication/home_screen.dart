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
import '../upload/base_roster_activation_page.dart';
import '../upload/storage_service.dart';
import '../upload/upload_service.dart';
import '../smart_scan/smart_scan_debug_page.dart';
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

  String driverName = '';
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

    driverName = (profile?['display_name'] ?? metadata['full_name'] ?? '')
        .toString()
        .trim();

    depot = (profile?['depot'] ?? metadata['depot'] ?? '').toString().trim();

    payrollNumber =
        (profile?['payroll_number'] ?? metadata['payroll_number'] ?? '')
            .toString()
            .trim();
  }

  final List<String> signature = <String>[
    if (driverName.isNotEmpty) driverName,
    if (depot.isNotEmpty) depot,
    if (payrollNumber.isNotEmpty) 'Payroll Number: $payrollNumber',
  ];

  final String subject = 'Annual Leave Request Cancellation - $dateLabel';

  final String body =
      'Please can I cancel my floating annual leave request for:\n\n'
      '$dateLabel\n\n'
      'Regards'
      '${signature.isEmpty ? '' : '\n${signature.join('\n')}'}';

  return launchUrl(
    _rosterBuddyMailUri(subject: subject, body: body),
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_self',
  );
}

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
  int _pendingActionCount = 0;

  final GlobalKey<_CalendarPageState> _calendarKey =
      GlobalKey<_CalendarPageState>();

  DateTime? _calendarRequestedDate;
  _CalendarDayAction? _calendarRequestedAction;
  int _calendarRequestVersion = 0;

  @override
  void initState() {
    super.initState();
    _refreshPendingActionCount();
  }

  Future<void> _refreshPendingActionCount() async {
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

      if (!mounted) {
        return;
      }

      setState(() {
        _pendingActionCount =
            floatingRows.length + cancellationRows.length + blockRows.length + newShiftSwapCount;
      });
    } catch (_) {
      // Badge loading must never prevent the main app from loading.
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
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _navigateFromChild(int destination) async {
    if (destination == 2) {
      await _pickDocument(UploadSource.file);
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      if (destination == 0 || destination == 1) {
        _dashboardRefreshVersion++;
      }

      _selectedIndex = destination;
    });
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
            await _pickDocument(UploadSource.file);
            return;
          }

          if (index == 1) {
            _calendarKey.currentState?.showCurrentMonth();
          }

          setState(() {
            if (index == 0 || index == 1) {
              _dashboardRefreshVersion++;
            }

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
  static const Color navy = Color(0xFF102A43);
  static const Color background = Color(0xFFF4F7FA);
  static const Color leaveRed = Color(0xFFD64545);
  static const Color textGrey = Color(0xFF52667A);

  final AnnualLeaveBlockPendingActionService _blockPendingService =
      AnnualLeaveBlockPendingActionService();
  final AnnualLeaveBlockService _blockService = AnnualLeaveBlockService();
  final ShiftSwapService _shiftSwapService = ShiftSwapService();
  final DutyResolver _shiftSwapDutyResolver = DutyResolver();
  final ManualDutyService _shiftSwapManualDutyService = ManualDutyService();
  final JobCardService _shiftSwapJobCardService = JobCardService();

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
                            const Text(
                              'Enter times as 4 digits, for example 0800 or 1630.',
                              style: TextStyle(color: textGrey, fontSize: 12),
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
                const Expanded(
                  child: Text(
                    'Mutual shift swap',
                    style: TextStyle(
                      color: navy,
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
              style: const TextStyle(color: navy, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Requested duty: ${_dateLabel(swap.requestedDate)}'
              '${swap.requestedTurnNumber == null ? '' : ' • Turn ${swap.requestedTurnNumber}'}',
              style: const TextStyle(color: navy, fontWeight: FontWeight.w700),
            ),
            if (otherDriver != null) ...[
              const SizedBox(height: 6),
              Text(
                'Other driver: $otherDriver'
                '${otherPayroll == null ? '' : ' • Payroll $otherPayroll'}',
                style: const TextStyle(color: textGrey),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Awaiting confirmation from Rosters / DTCM.',
              style: TextStyle(color: textGrey),
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
                    style: const TextStyle(
                      color: navy,
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
              style: const TextStyle(color: navy, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Current: ${_dateLabel(action.originalStartDate)} – '
              '${_dateLabel(action.originalEndDate)}',
              style: const TextStyle(color: textGrey),
            ),
            const SizedBox(height: 4),
            Text(
              'Requested: ${_dateLabel(action.proposedStartDate)} – '
              '${_dateLabel(action.proposedEndDate)}',
              style: const TextStyle(color: navy, fontWeight: FontWeight.w700),
            ),
            if (mutualSwap && action.swapDriverNumber != null) ...[
              const SizedBox(height: 6),
              Text(
                'Other driver: ${action.swapDriverNumber}',
                style: const TextStyle(color: textGrey),
              ),
            ],
            if (action.swapReference != null) ...[
              const SizedBox(height: 4),
              Text(
                'Reference: ${action.swapReference}',
                style: const TextStyle(color: textGrey),
              ),
            ],
            if (action.notes != null) ...[
              const SizedBox(height: 4),
              Text(action.notes!, style: const TextStyle(color: textGrey)),
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
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (action.recipientEmail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'To: ${action.recipientEmail}',
                        style: const TextStyle(color: textGrey),
                      ),
                    ],
                    const SizedBox(height: 7),
                    const Text(
                      'Automatic email sending is not yet active. '
                      'The email details and send time are safely stored, '
                      'but the server-side sender still needs to be connected.',
                      style: TextStyle(
                        color: textGrey,
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
              style: const TextStyle(color: navy, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Pending cancellation', style: TextStyle(color: leaveRed, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Awaiting Rosters / DTCM approval. Leave stays granted until confirmed.',
              style: TextStyle(color: textGrey)),
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
                const Icon(Icons.beach_access_outlined, color: leaveRed),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _dateLabel(request.leaveDate),
                    style: const TextStyle(
                      color: navy,
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
              style: const TextStyle(color: textGrey),
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
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: navy,
        elevation: 0,
        title: const Text(
          'Pending Actions',
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
              const Text(
                'Annual Leave',
                style: TextStyle(
                  color: navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Record decisions from Rosters or confirm outstanding '
                'block leave changes with the Union.',
                style: TextStyle(color: textGrey),
              ),
              const SizedBox(height: 16),
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
                          style: const TextStyle(color: textGrey),
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
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, color: textGrey, size: 34),
                        SizedBox(height: 10),
                        Text(
                          'No pending actions',
                          style: TextStyle(
                            color: navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Annual leave decisions, block leave changes and mutual '
                          'shift swaps awaiting action will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textGrey),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                const Row(
                  children: [
                    Icon(Icons.beach_access_outlined, color: leaveRed),
                    SizedBox(width: 8),
                    Text(
                      'Floating annual leave',
                      style: TextStyle(
                        color: navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Individual ALD requests awaiting a decision from Rosters.',
                  style: TextStyle(color: textGrey),
                ),
                const SizedBox(height: 12),
                if (_requests.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: textGrey),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No floating annual leave actions.',
                              style: TextStyle(color: textGrey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._requests.map(_buildRequestCard),

                const SizedBox(height: 22),

                const Row(
                  children: [
                    Icon(Icons.swap_horiz_outlined, color: Color(0xFF1769AA)),
                    SizedBox(width: 8),
                    Text(
                      'Mutual shift swaps',
                      style: TextStyle(
                        color: navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Shift swaps waiting for a decision from Rosters / DTCM.',
                  style: TextStyle(color: textGrey),
                ),
                const SizedBox(height: 12),
                if (_shiftSwaps.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: textGrey),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No pending mutual shift swaps.',
                              style: TextStyle(color: textGrey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._shiftSwaps.map(_buildShiftSwapCard),

                const SizedBox(height: 22),

                const Row(
                  children: [
                    Icon(Icons.swap_horiz_outlined, color: leaveRed),
                    SizedBox(width: 8),
                    Text(
                      'Block annual leave',
                      style: TextStyle(
                        color: navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Block moves, mutual swaps and future requests waiting '
                  'in the Union send queue.',
                  style: TextStyle(color: textGrey),
                ),
                const SizedBox(height: 12),
                if (_blockActions.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: textGrey),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No block annual leave actions.',
                              style: TextStyle(color: textGrey),
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
                        color: hasBreach ? leaveRed : navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: textGrey, height: 1.35),
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
                  const Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: workingGreen),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Hidden 18 check',
                          style: TextStyle(
                            color: navy,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Hidden 18 warnings are currently detected in the '
                    'roster period checked.',
                    style: TextStyle(color: textGrey, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Current consecutive working days: '
                    '${result.consecutiveDaysWorked}',
                    style: const TextStyle(
                      color: navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Current rolling 7-day total: '
                    '${_formatHidden18Minutes(result.rollingSevenDayMinutes)}',
                    style: const TextStyle(
                      color: navy,
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: warningOrange),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Hidden 18 warnings',
                          style: TextStyle(
                            color: navy,
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
                          style: const TextStyle(
                            color: navy,
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
                    style: const TextStyle(
                      color: textGrey,
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

    final Color foreground = darkText ? navy : Colors.white;

    return Material(
      color: colour,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          _showDashboardDayDetails(
            date: date,
            duty: duty,
            leaveRequest: leaveRequest,
          );
        },
        onLongPress: () {
          _showDashboardDayActions(date: date, duty: duty);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isToday ? railwayBlue : Colors.transparent,
              width: isToday ? 2.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _dashboardWeekdayLabel(date),
                maxLines: 1,
                style: TextStyle(
                  color: foreground,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                date.day.toString(),
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                isGrantedAnnualLeave
                    ? 'Leave'
                    : duty == null
                    ? '—'
                    : _dashboardWeekStatus(duty),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!isGrantedAnnualLeave &&
                  duty?.bookOn?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 3),
                Text(
                  duty!.bookOn!.trim(),
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (duty != null || isGrantedAnnualLeave) ...[
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 3,
                  runSpacing: 2,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: darkText
                            ? railwayBlue.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isGrantedAnnualLeave
                            ? (leaveRequest?.requestType ==
                                      AnnualLeaveRequestType.floating
                                  ? 'ALD'
                                  : 'AW')
                            : _dashboardSourceLabel(duty!.source),
                        style: TextStyle(
                          color: foreground,
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (!isGrantedAnnualLeave &&
                        leaveRequest != null &&
                        leaveRequest.status !=
                            AnnualLeaveRequestStatus.cancelled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color:
                              leaveRequest.status ==
                                  AnnualLeaveRequestStatus.abeyance
                              ? const Color(0xFFF59E0B)
                              : leaveRed,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          leaveRequest.status ==
                                  AnnualLeaveRequestStatus.abeyance
                              ? leaveRequest.queuePosition == null
                                    ? 'ABE'
                                    : 'ABE #${leaveRequest.queuePosition}'
                              : 'AL REQ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _dashboardWeekColour(Duty? duty) {
    if (duty == null) {
      return Colors.white;
    }

    switch (duty.dutyType) {
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

  String _dashboardWeekStatus(Duty duty) {
    switch (duty.dutyType) {
      case DutyType.working:
        final String? turn = duty.turnNumber?.trim();

        if (turn != null && turn.isNotEmpty) {
          return turn;
        }

        return duty.remarks?.contains('RDW') == true ? 'RDW' : 'Duty';
      case DutyType.training:
        return 'Train';
      case DutyType.medical:
        return 'Med';
      case DutyType.restDay:
        return 'Rest';
      case DutyType.annualLeave:
        return 'Leave';
      case DutyType.sick:
        return 'Sick';
      case DutyType.publicHoliday:
        return 'Holiday';
      case DutyType.unavailable:
        return 'Unavail';
      case DutyType.unknown:
        return 'Review';
    }
  }

  String _dashboardWeekdayLabel(DateTime date) {
    const List<String> labels = <String>[
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
    ];

    return labels[date.weekday % 7];
  }

  String _dashboardSourceLabel(RosterSource source) {
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

  static bool _sameDashboardDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  static String _dashboardDateKey(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
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
          _showDashboardDayDetails(date: duty.date, duty: duty);
        },
        onLongPress: () {
          _showDashboardDayActions(date: duty.date, duty: duty);
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
                    if (duty.dutyType == DutyType.restDay) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          _showDashboardAllocateShiftDialog(
                            date: duty.date,
                            originalDuty: duty,
                          );
                        },
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Allocate shift – RDW'),
                        style: FilledButton.styleFrom(
                          backgroundColor: workingGreen,
                        ),
                      ),
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

  Future<JobCardMatch?> _findDashboardJobCard(Duty duty) async {
    final String turnNumber = duty.turnNumber?.trim() ?? '';

    if (turnNumber.isEmpty || !duty.dutyType.countsAsWorking) {
      return null;
    }

    try {
      return await _jobCardService.findMatchingJobCard(
        turnNumber: turnNumber,
        dutyDate: duty.date,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openDashboardJobCard(JobCardMatch match) async {
    try {
      final String signedUrl = await _jobCardService.createSignedPdfUrl(match);
      Uri pdfUri = Uri.parse(signedUrl);

      final int? pageNumber = match.jobCard.pageNumber;

      if (pageNumber != null && pageNumber > 0) {
        pdfUri = pdfUri.replace(fragment: 'page=$pageNumber');
      }

      final bool opened = await launchUrl(
        pdfUri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );

      if (!opened && mounted) {
        showMessage(context, 'Roster Buddy could not open this Job Card.');
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      showMessage(context, 'Roster Buddy could not open this Job Card.');
    }
  }

  Future<void> _showDashboardDayDetails({
    required DateTime date,
    required Duty? duty,
    AnnualLeaveRequest? leaveRequest,
  }) async {
    leaveRequest ??= _thisWeekLeaveRequests[_dashboardDateKey(date)];

    final bool isGrantedAnnualLeave =
        leaveRequest?.status == AnnualLeaveRequestStatus.granted;

    final bool isFloatingAnnualLeave =
        isGrantedAnnualLeave &&
        leaveRequest?.requestType == AnnualLeaveRequestType.floating;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullDate(date),
                  style: const TextStyle(
                    color: navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                if (duty == null && !isGrantedAnnualLeave)
                  const Text(
                    'No roster information is available for this date.',
                    style: TextStyle(color: textGrey),
                  )
                else ...[
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isGrantedAnnualLeave
                              ? leaveRed
                              : _dashboardWeekColour(duty),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isGrantedAnnualLeave
                              ? 'Annual Leave'
                              : _dashboardWeekStatus(duty!),
                          style: const TextStyle(
                            color: navy,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (isGrantedAnnualLeave)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: leaveRed.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            isFloatingAnnualLeave ? 'ALD' : 'AW',
                            style: const TextStyle(
                              color: leaveRed,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      else
                        _RosterSourceBadge(source: duty!.source),
                    ],
                  ),
                  if (!isGrantedAnnualLeave &&
                      (duty?.bookOn?.trim().isNotEmpty == true ||
                          duty?.bookOff?.trim().isNotEmpty == true)) ...[
                    const SizedBox(height: 14),
                    Text(
                      _timeDescription(duty!),
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (!isGrantedAnnualLeave &&
                      duty?.turnNumber?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Turn ${duty!.turnNumber!.trim()}',
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (!isGrantedAnnualLeave &&
                      duty?.remarks?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Text(
                      displayDatesInText(duty!.remarks!.trim()),
                      style: const TextStyle(color: textGrey, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _DutyHistorySection(
                    future: DutyHistoryService().load(date, _dutyResolver.getDutiesForDate(date)),
                    onChanged: () { widget.onRosterChanged(); _loadDashboardDuties(); },
                  ),
                ],
                const SizedBox(height: 22),
                if (duty?.dutyType.countsAsWorking == true &&
                    (leaveRequest == null ||
                        leaveRequest.status ==
                            AnnualLeaveRequestStatus.cancelled)) ...[
                  FutureBuilder<JobCardMatch?>(
                    future: _findDashboardJobCard(duty!),
                    builder:
                        (
                          BuildContext context,
                          AsyncSnapshot<JobCardMatch?> snapshot,
                        ) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: null,
                                icon: SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                label: Text('Checking Job Card…'),
                              ),
                            );
                          }

                          final JobCardMatch? match = snapshot.data;

                          if (match == null) {
                            return SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: null,
                                icon: Icon(Icons.description_outlined),
                                label: Text('Job Card not available'),
                              ),
                            );
                          }

                          return SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(sheetContext).pop();

                                Future<void>.delayed(
                                  const Duration(milliseconds: 150),
                                  () {
                                    if (mounted) {
                                      _openDashboardJobCard(match);
                                    }
                                  },
                                );
                              },
                              icon: const Icon(Icons.description_outlined),
                              label: const Text('Open Job Card'),
                            ),
                          );
                        },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();

                        Future<void>.delayed(
                          const Duration(milliseconds: 150),
                          () {
                            if (!mounted) {
                              return;
                            }

                            widget.onCalendarAction(
                              date,
                              _CalendarDayAction.requestAnnualLeave,
                            );
                          },
                        );
                      },
                      icon: const Icon(Icons.beach_access_outlined),
                      label: const Text('Request annual leave'),
                      style: FilledButton.styleFrom(backgroundColor: leaveRed),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (leaveRequest != null &&
                    (leaveRequest.status ==
                            AnnualLeaveRequestStatus.requested ||
                        leaveRequest.status ==
                            AnnualLeaveRequestStatus.abeyance)) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();

                        Future<void>.delayed(
                          const Duration(milliseconds: 150),
                          () async {
                            if (!mounted) {
                              return;
                            }

                            await _manageDashboardAnnualLeaveRequest(
                              date: date,
                              request: leaveRequest!,
                            );
                          },
                        );
                      },
                      icon: const Icon(Icons.event_note_outlined),
                      label: const Text('Action annual leave'),
                      style: FilledButton.styleFrom(backgroundColor: leaveRed),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (isGrantedAnnualLeave && leaveRequest != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();

                        Future<void>.delayed(
                          const Duration(milliseconds: 150),
                          () async {
                            if (!mounted) {
                              return;
                            }

                            await _cancelDashboardGrantedAnnualLeave(
                              date: date,
                              request: leaveRequest!,
                            );
                          },
                        );
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel annual leave'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: leaveRed,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();

                      Future<void>.delayed(
                        const Duration(milliseconds: 150),
                        () {
                          if (!mounted) {
                            return;
                          }

                          _showDashboardDayActions(date: date, duty: duty);
                        },
                      );
                    },
                    icon: const Icon(Icons.more_horiz),
                    label: const Text('More day actions'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _manageDashboardAnnualLeaveRequest({
    required DateTime date,
    required AnnualLeaveRequest request,
  }) async {
    final String? action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext popupContext) {
        return CupertinoActionSheet(
          title: const Text('Action annual leave'),
          message: Text(_fullDate(date)),
          actions: [
            CupertinoActionSheetAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(popupContext).pop('grant');
              },
              child: const Text('Grant'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop('abeyance');
              },
              child: Text(
                request.status == AnnualLeaveRequestStatus.abeyance
                    ? 'Update abeyance'
                    : 'Abeyance',
              ),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(popupContext).pop('cancel');
              },
              child: const Text('Cancel request'),
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

    if (action == null || !mounted) {
      return;
    }

    try {
      if (action == 'grant') {
        final bool? alreadyConfirmed = await showRosterDecisionSheet<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return RosterDecisionSheet(
              title: const Text('Annual leave confirmed?'),
              content: Text(
                'Has the annual leave for ${_fullDate(date)} already been '
                'confirmed by Rosters / DTCM?',
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

        if (alreadyConfirmed) {
          await _annualLeaveService.markGranted(requestId: request.id);
          await _loadDashboardDuties();

          if (!mounted) {
            return;
          }

          widget.onRosterChanged();

          showMessage(
            context,
            'Floating annual leave granted for ${_fullDate(date)}.',
          );

          return;
        }

        final SupabaseClient supabase = Supabase.instance.client;
        final User? user = supabase.auth.currentUser;

        String driverName = '';
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

          driverName = (profile?['display_name'] ?? metadata['full_name'] ?? '')
              .toString()
              .trim();

          depot = (profile?['depot'] ?? metadata['depot'] ?? '')
              .toString()
              .trim();

          payrollNumber =
              (profile?['payroll_number'] ?? metadata['payroll_number'] ?? '')
                  .toString()
                  .trim();
        }

        final List<String> signature = <String>[
          if (driverName.isNotEmpty) driverName,
          if (depot.isNotEmpty) depot,
          if (payrollNumber.isNotEmpty) 'Payroll Number: $payrollNumber',
        ];

        final String subject = 'Annual Leave Request - ${_fullDate(date)}';

        final String body =
            'Please can I request floating annual leave for:\n\n'
            '${_fullDate(date)}\n\n'
            'Regards'
            '${signature.isEmpty ? '' : '\n${signature.join('\n')}'}';

        final Uri emailUri = _rosterBuddyMailUri(subject: subject, body: body);

        final bool opened = await launchUrl(
          emailUri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_self',
        );

        if (!mounted) {
          return;
        }

        if (!opened) {
          showMessage(context, 'Roster Buddy could not open your email app.');
        }

        return;
      }

      if (action == 'abeyance') {
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
                    BuildContext dialogContext,
                    void Function(void Function()) setDialogState,
                  ) {
                    return AlertDialog(
                      title: const Text('Abeyance queue position'),
                      content: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        autofocus: true,
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
                            final int? value = int.tryParse(
                              controller.text.trim(),
                            );

                            if (value == null || value < 1) {
                              setDialogState(() {
                                errorText =
                                    'Enter a queue position of 1 or more.';
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

        await _annualLeaveService.markAbeyance(
          requestId: request.id,
          queuePosition: queuePosition,
        );

        await _loadDashboardDuties();

        if (!mounted) {
          return;
        }

        widget.onRosterChanged();

        showMessage(
          context,
          'Annual leave held in abeyance at #$queuePosition.',
        );
        return;
      }

      if (action == 'cancel') {
        final bool? alreadyConfirmed = await showRosterDecisionSheet<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return RosterDecisionSheet(
              title: const Text('Cancellation confirmed?'),
              content: Text(
                'Has the cancellation of your annual leave request for '
                '${_fullDate(date)} already been confirmed by Rosters / DTCM?',
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

        if (alreadyConfirmed) {
          await _annualLeaveService.cancelRequest(requestId: request.id);

          await _loadDashboardDuties();

          if (!mounted) {
            return;
          }

          widget.onRosterChanged();

          showMessage(
            context,
            'Annual leave request cancelled for ${_fullDate(date)}.',
          );

          return;
        }

        final bool opened = await _openAnnualLeaveRequestCancellationEmail(
          dateLabel: _fullDate(date),
        );

        if (!mounted) {
          return;
        }

        if (opened) {
          showMessage(
            context,
            'Cancellation email prepared. The annual leave request '
            'will remain active until Rosters / DTCM confirms cancellation.',
          );
        } else {
          showMessage(
            context,
            'Roster Buddy could not open your email app. '
            'The annual leave request remains active.',
          );
        }

        return;
      }
    } on AnnualLeaveException catch (error) {
      if (mounted) {
        showMessage(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Roster Buddy could not update this annual leave request.',
        );
      }
    }
  }

  Future<void> _cancelDashboardGrantedAnnualLeave({
    required DateTime date,
    required AnnualLeaveRequest request,
  }) async {
    final bool? alreadyConfirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Cancellation confirmed?'),
          content: Text(
            'Has the cancellation of ${_fullDate(date)} already been '
            'confirmed by Rosters / DTCM?',
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
        await _annualLeaveService.cancelRequest(requestId: request.id);
        await _loadDashboardDuties();

        if (!mounted) {
          return;
        }

        widget.onRosterChanged();

        showMessage(context, 'Annual leave cancelled for ${_fullDate(date)}.');
        return;
      }

      final SupabaseClient supabase = Supabase.instance.client;
      final User? user = supabase.auth.currentUser;

      String driverName = '';
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

        driverName = (profile?['display_name'] ?? metadata['full_name'] ?? '')
            .toString()
            .trim();

        depot = (profile?['depot'] ?? metadata['depot'] ?? '')
            .toString()
            .trim();

        payrollNumber =
            (profile?['payroll_number'] ?? metadata['payroll_number'] ?? '')
                .toString()
                .trim();
      }

      final List<String> signature = <String>[
        if (driverName.isNotEmpty) driverName,
        if (depot.isNotEmpty) depot,
        if (payrollNumber.isNotEmpty) 'Payroll Number: $payrollNumber',
      ];

      final String subject = 'Annual Leave Cancellation - ${_fullDate(date)}';

      final String body =
          'Please can I cancel my previously granted annual leave for:\n\n'
          '${_fullDate(date)}\n\n'
          'Regards'
          '${signature.isEmpty ? '' : '\n${signature.join('\n')}'}';

      final Uri emailUri = _rosterBuddyMailUri(subject: subject, body: body);

      final bool opened = await launchUrl(
        emailUri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );

      if (!mounted) {
        return;
      }

      if (!opened) {
        showMessage(
          context,
          'Roster Buddy could not open your email app. '
          'The annual leave remains granted.',
        );
      }
    } on AnnualLeaveException catch (error) {
      if (mounted) {
        showMessage(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Roster Buddy could not process the annual leave cancellation.',
        );
      }
    }
  }

  Future<void> _showDashboardDayActions({
    required DateTime date,
    required Duty? duty,
  }) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext popupContext) {
        final List<Widget> actions = <Widget>[];

        void closeAndRun(VoidCallback callback) {
          Navigator.of(popupContext).pop();

          Future<void>.delayed(const Duration(milliseconds: 150), () {
            if (mounted) {
              callback();
            }
          });
        }

        if (duty == null) {
          actions.add(
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop();
              },
              child: const Text('No roster information'),
            ),
          );
        } else if (duty.dutyType == DutyType.restDay) {
          actions.add(
            CupertinoActionSheetAction(
              onPressed: () {
                closeAndRun(() {
                  _showDashboardAllocateShiftDialog(
                    date: date,
                    originalDuty: duty,
                  );
                });
              },
              child: const Text('Allocate shift'),
            ),
          );
        } else if (duty.dutyType.countsAsWorking) {
          actions.addAll(<Widget>[
            CupertinoActionSheetAction(
              onPressed: () {
                closeAndRun(() {
                  _showDashboardEditDutyDialog(date: date, originalDuty: duty);
                });
              },
              child: const Text('Edit book-on/off time'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                closeAndRun(() {
                  widget.onCalendarAction(
                    date,
                    _CalendarDayAction.selectTurnNumber,
                  );
                });
              },
              child: const Text('Select turn number'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                closeAndRun(() {
                  widget.onCalendarAction(
                    date,
                    _CalendarDayAction.manualChange,
                  );
                });
              },
              child: const Text('Manual change'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                closeAndRun(() {
                  widget.onCalendarAction(date, _CalendarDayAction.shiftSwap);
                });
              },
              child: const Text('Mutual Swap'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                closeAndRun(() {
                  widget.onCalendarAction(
                    date,
                    _CalendarDayAction.moveRestDayHere,
                  );
                });
              },
              child: const Text('Move rest day here'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                closeAndRun(() {
                  widget.onCalendarAction(
                    date,
                    _CalendarDayAction.requestAnnualLeave,
                  );
                });
              },
              child: const Text('Request annual leave'),
            ),
          ]);
        } else {
          actions.add(
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop();
              },
              child: const Text('View duty details'),
            ),
          );
        }

        return CupertinoActionSheet(
          title: Text(_fullDate(date)),
          message: Text(
            duty == null ? 'No roster information' : _dashboardWeekStatus(duty),
          ),
          actions: actions,
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(popupContext).pop();
            },
            child: const Text('Cancel'),
          ),
        );
      },
    );
  }

  Future<void> _showDashboardEditDutyDialog({
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
                  final String bookOn = _normaliseDashboardTime(
                    bookOnController.text,
                  );
                  final String bookOff = _normaliseDashboardTime(
                    bookOffController.text,
                  );

                  if (!_isValidDashboardTime(bookOn) ||
                      !_isValidDashboardTime(bookOff)) {
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
                    await _loadDashboardDuties();

                    if (!mounted) {
                      return;
                    }

                    showMessage(
                      context,
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
                          const Text(
                            'Edit duty',
                            style: TextStyle(
                              color: navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fullDate(date),
                            style: const TextStyle(color: textGrey),
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

  Future<void> _showDashboardAllocateShiftDialog({
    required DateTime date,
    required Duty originalDuty,
  }) async {
    const String manualSelection = '__MANUAL_DASHBOARD_RDW__';

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
    String? errorMessage;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setSheetState,
              ) {
                Future<void> save() async {
                  final bool manual = selectedTurn == manualSelection;

                  final String turnNumber = manual
                      ? manualTurnController.text.trim()
                      : selectedTurn.trim();

                  final String bookOn = _normaliseDashboardTime(
                    bookOnController.text,
                  );

                  final String bookOff = _normaliseDashboardTime(
                    bookOffController.text,
                  );

                  if (turnNumber.isEmpty) {
                    setSheetState(() {
                      errorMessage = 'Enter or select a turn number.';
                    });
                    return;
                  }

                  if (!_isValidDashboardTime(bookOn) ||
                      !_isValidDashboardTime(bookOff)) {
                    setSheetState(() {
                      errorMessage =
                          'Enter valid times, for example 0800 or 08:00.';
                    });
                    return;
                  }

                  setSheetState(() {
                    isSaving = true;
                    errorMessage = null;
                  });

                  try {
                    await _manualDutyService.saveRestDayWorked(
                      date: date,
                      turnNumber: turnNumber,
                      bookOn: bookOn,
                      bookOff: bookOff,
                      originalDuty: originalDuty,
                    );

                    if (!mounted || !sheetContext.mounted) {
                      return;
                    }

                    Navigator.of(sheetContext).pop();

                    await _loadDashboardDuties();
                    widget.onRosterChanged();

                    if (!mounted) {
                      return;
                    }

                    showMessage(
                      this.context,
                      'Rest Day Worked saved for ${_fullDate(date)}.',
                    );
                  } catch (error) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      isSaving = false;
                      errorMessage = error is ManualDutyException
                          ? error.message
                          : 'Roster Buddy could not save this RDW.';
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
                          const Text(
                            'Allocate shift – RDW',
                            style: TextStyle(
                              color: navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fullDate(date),
                            style: const TextStyle(color: textGrey),
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
                                (
                                  JobCardChoice choice,
                                ) => DropdownMenuItem<String>(
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
                                      errorMessage = null;

                                      if (value != manualSelection) {
                                        for (final JobCardChoice choice
                                            in choices) {
                                          if (choice.jobCard.turnNumber ==
                                              value) {
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
                                hintText:
                                    'For example WO216 or cross-depot cover',
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

                          const Text(
                            'Selecting a Job Card fills its booked times '
                            'automatically. Manual or cross-depot duties '
                            'can still be entered.',
                            style: TextStyle(color: textGrey, height: 1.35),
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
                                isSaving
                                    ? 'Saving RDW…'
                                    : 'Save Rest Day Worked',
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
  }

  static String _normaliseDashboardTime(String value) {
    String cleaned = value.trim().replaceAll(RegExp(r'\s+'), '');

    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(cleaned)) {
      final List<String> parts = cleaned.split(':');
      return '${parts[0].padLeft(2, '0')}:${parts[1]}';
    }

    if (RegExp(r'^\d{3,4}$').hasMatch(cleaned)) {
      cleaned = cleaned.padLeft(4, '0');
      return '${cleaned.substring(0, 2)}:${cleaned.substring(2)}';
    }

    return cleaned;
  }

  static bool _isValidDashboardTime(String value) {
    final RegExpMatch? match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);

    if (match == null) {
      return false;
    }

    final int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2)!);

    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
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
    return displayDate(date);
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

class _DutyHistorySection extends StatelessWidget {
  const _DutyHistorySection({required this.future, required this.onChanged});

  final VoidCallback onChanged;

  final Future<List<Duty>> future;

  Future<void> _showTurnHistory(BuildContext context, List<Duty> duties) async {
    final selected = await showModalBottomSheet<Duty>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history, size: 22, color: Color(0xFF102A43)),
                    SizedBox(width: 8),
                    Text(
                      'Roster history',
                      style: TextStyle(
                        color: Color(0xFF102A43),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Current entry first. Tap an older entry to revert.',
                  style: TextStyle(color: Color(0xFF52667A)),
                ),
                const SizedBox(height: 16),
                for (int index = 0; index < duties.length; index++) ...[
                  GestureDetector(
                    onTap: index == 0 ? null : () async {
                      final confirmed = await showRosterDecisionSheet<bool>(
                        context: sheetContext,
                        builder: (confirmContext) => RosterDecisionSheet(
                          title: const Text('Revert to this entry?'),
                          content: _DutyHistoryEntry(duty: duties[index], isCurrent: false),
                          actions: [
                            CupertinoDialogAction(onPressed: () => Navigator.pop(confirmContext, false), child: const Text('Back')),
                            CupertinoDialogAction(onPressed: () => Navigator.pop(confirmContext, true), child: const Text('Revert to this entry')),
                          ],
                        ),
                      );
                      if (confirmed == true && sheetContext.mounted) Navigator.pop(sheetContext, duties[index]);
                    },
                    child: _DutyHistoryEntry(duty: duties[index], isCurrent: index == 0),
                  ),
                  if (index != duties.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    try {
      await DutyHistoryService().revert(selected, duties.first);
      if (!context.mounted) return;
      Navigator.pop(context);
      onChanged();
    } catch (_) {
      if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not revert the roster entry. Please try again.'))); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Duty>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<Duty>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Loading latest roster entry…'),
            ],
          );
        }

        if (snapshot.hasError) {
          return const Text(
            'Roster information could not be loaded.',
            style: TextStyle(color: Color(0xFF52667A)),
          );
        }

        final List<Duty> duties = List<Duty>.of(
          snapshot.data ?? const <Duty>[],
        );

        if (duties.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(onTap: () => _showTurnHistory(context, duties), child: const Row(
              children: [
                Icon(Icons.update, size: 20, color: Color(0xFF102A43)),
                SizedBox(width: 8),
                Text(
                  'Latest roster entry',
                  style: TextStyle(
                    color: Color(0xFF102A43),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )),
            const SizedBox(height: 10),
            InkWell(onTap: () => _showTurnHistory(context, duties), child: _DutyHistoryEntry(duty: duties.first, isCurrent: true)),
            ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showTurnHistory(context, duties),
                  icon: const Icon(Icons.history),
                  label: const Text('Roster history'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DutyHistoryEntry extends StatelessWidget {
  const _DutyHistoryEntry({required this.duty, required this.isCurrent});

  final Duty duty;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final String source =
        duty.source == RosterSource.annualLeave &&
            duty.remarks?.toLowerCase().startsWith('floating annual leave') ==
                true
        ? 'ALD'
        : _historySourceLabel(duty.source);
    final String dutyLabel = _historyDutyLabel(duty);

    final List<String> details = <String>[];

    if (duty.turnNumber?.trim().isNotEmpty == true) {
      details.add('Turn ${duty.turnNumber!.trim()}');
    }

    final String? bookOn = duty.bookOn?.trim();
    final String? bookOff = duty.bookOff?.trim();

    if (bookOn?.isNotEmpty == true || bookOff?.isNotEmpty == true) {
      if (bookOn?.isNotEmpty == true && bookOff?.isNotEmpty == true) {
        details.add('$bookOn–$bookOff');
      } else if (bookOn?.isNotEmpty == true) {
        details.add('Book on $bookOn');
      } else if (bookOff?.isNotEmpty == true) {
        details.add('Book off $bookOff');
      }
    }

    if (duty.amendmentCode?.trim().isNotEmpty == true) {
      details.add(duty.amendmentCode!.trim().toUpperCase());
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? const Color(0xFF1769AA) : const Color(0xFFDCE3E8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RosterSourceBadge(source: duty.source),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source,
                  style: const TextStyle(
                    color: Color(0xFF102A43),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F1FA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Current',
                    style: TextStyle(
                      color: Color(0xFF1769AA),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            dutyLabel,
            style: const TextStyle(
              color: Color(0xFF102A43),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              details.join('  •  '),
              style: const TextStyle(color: Color(0xFF52667A), height: 1.3),
            ),
          ],
          if (duty.remarks?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              displayDatesInText(duty.remarks!.trim()),
              style: const TextStyle(
                color: Color(0xFF52667A),
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _historySourceLabel(RosterSource source) {
    switch (source) {
      case RosterSource.baseRoster:
        return 'Base Roster';
      case RosterSource.tenDay:
        return '10-Day Amendment';
      case RosterSource.sevenDay:
        return '7-Day Amendment';
      case RosterSource.fortyEightHour:
        return '48-Hour Amendment';
      case RosterSource.annualLeave:
        return 'Annual Leave';
      case RosterSource.manual:
        return 'Manual adjustment';
    }
  }

  static String _historyDutyLabel(Duty duty) {
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
        return 'Duty';
    }
  }
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

class _CalendarPage extends StatefulWidget {
  const _CalendarPage({
    required this.refreshVersion,
    required this.requestedDate,
    required this.requestedAction,
    required this.requestVersion,
    required this.onRosterChanged,
    required this.onOpenCalendar,
    super.key,
  });

  final int refreshVersion;
  final DateTime? requestedDate;
  final _CalendarDayAction? requestedAction;
  final int requestVersion;
  final VoidCallback onRosterChanged;
  final VoidCallback onOpenCalendar;

  @override
  State<_CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<_CalendarPage> {
  List<ShiftSwap> _restDayMoves = <ShiftSwap>[];

  @override
  void dispose() {
    _restDayPicker?.complete(null);
    super.dispose();
  }

  Future<void> _actionCalendarRestMove(ShiftSwap move, DateTime date) async {
    try {
      final changed = await actionRestDayMove(context, restDayMovePairs(move.notes!), id: move.id,
        awaitingAllocation: move.notes!.contains('ALLOCATION_REQUIRED=true'), selectedDate: date);
      if (changed && mounted) {
        widget.onRosterChanged();
        await _loadMonth();
      }
    } catch (_) {
      if (mounted) _showCalendarMessage('Could not action the rest day move. Please try again.');
    }
  }

  Completer<List<Duty>?>? _restDayPicker;
  Map<String, Duty> _restDayChoices = <String, Duty>{};
  final Set<String> _restDaySelected = <String>{};
  int _restDayRequired = 0;
  String _restDaySelectionTitle = '';

  Future<List<Duty>?> _pickRestDayDates(
    String title, List<Duty> duties, int count, Duty? initial,
  ) {
    if (_restDayPicker != null) _finishRestDaySelection(false);
    final completer = Completer<List<Duty>?>();
    setState(() {
      _restDayPicker = completer;
      _restDayChoices = {for (final duty in duties) _dateKey(duty.date): duty};
      _restDaySelected.clear();
      if (initial != null) _restDaySelected.add(_dateKey(initial.date));
      _restDayRequired = count;
      _restDaySelectionTitle = title;
      _isSelectingAnnualLeaveDates = false;
      _isSelectingAnnualLeaveCancellationDates = false;
    });
    return completer.future;
  }

  void _finishRestDaySelection(bool confirmed) {
    final picker = _restDayPicker;
    if (picker == null) return;
    final selected = confirmed
        ? _restDaySelected.map((key) => _restDayChoices[key]!).toList()
        : null;
    setState(() {
      _restDayPicker = null;
      _restDaySelected.clear();
      _restDayChoices.clear();
    });
    picker.complete(selected);
  }

  void _toggleRestDayDate(DateTime date) {
    final key = _dateKey(date);
    if (!_restDayChoices.containsKey(key)) return;
    setState(() {
      if (_restDaySelected.contains(key)) {
        _restDaySelected.remove(key);
      } else if (_restDaySelected.length < _restDayRequired) {
        _restDaySelected.add(key);
      }
    });
  }

  Widget _buildRestDaySelectionBar() {
    return Material(
      color: const Color(0xFFF4F7FA),
      elevation: 4,
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_restDaySelectionTitle, style: const TextStyle(color: navy, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _finishRestDaySelection(false),
              child: const Text('Cancel'),
            )),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(
              onPressed: _restDaySelected.length == _restDayRequired
                  ? () => _finishRestDaySelection(true) : null,
              child: Text('Confirm (${_restDaySelected.length}/$_restDayRequired)'),
            )),
          ]),
        ]),
      )),
    );
  }

  static const Color navy = Color(0xFF102A43);

  Future<void> openExternalAction(
    DateTime date,
    _CalendarDayAction action,
  ) async {
    final Duty? cachedDuty = _dutiesByDate[_dateKey(date)];

    if (cachedDuty != null) {
      await _handleDayAction(
        date: date,
        duty: cachedDuty,
        action: action,
        resolveFresh: false,
      );
      return;
    }

    await _handleDayAction(date: date, duty: null, action: action);
  }

  void showCurrentMonth() {
    final DateTime now = DateTime.now();
    setState(() {
      _displayedMonth = DateTime(now.year, now.month);
      _isSelectingAnnualLeaveDates = false;
      _selectedAnnualLeaveDateKeys.clear();
      _isSelectingAnnualLeaveCancellationDates = false;
      _selectedAnnualLeaveCancellationDateKeys.clear();
    });
    _loadMonth();
  }

  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color workingGreen = Color(0xFF2E7D32);
  static const Color restYellow = Color(0xFFFFD54F);
  static const Color leaveRed = Color(0xFFD64545);
  static const Color textGrey = Color(0xFF52667A);

  final DutyResolver _dutyResolver = DutyResolver();
  final ManualDutyService _manualDutyService = ManualDutyService();
  final ShiftSwapService _shiftSwapService = ShiftSwapService();
  final JobCardService _jobCardService = JobCardService();
  final AnnualLeaveService _annualLeaveService = AnnualLeaveService();
  final SundayAvailabilityService _sundayAvailabilityService =
      SundayAvailabilityService();

  late DateTime _displayedMonth;
  Map<String, Duty> _dutiesByDate = <String, Duty>{};
  Map<String, AnnualLeaveRequest> _leaveRequestsByDate =
      <String, AnnualLeaveRequest>{};
  Set<String> _scheduledAnnualLeaveDateKeys = <String>{};

  bool _isSelectingAnnualLeaveDates = false;
  final Set<String> _selectedAnnualLeaveDateKeys = <String>{};

  bool _isSelectingAnnualLeaveCancellationDates = false;
  final Set<String> _selectedAnnualLeaveCancellationDateKeys = <String>{};

  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();

    final DateTime now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month);

    _loadMonth();
  }

  @override
  void didUpdateWidget(covariant _CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _loadMonth();
    }

    if (oldWidget.requestVersion != widget.requestVersion) {
      _openRequestedCalendarAction();
    }
  }

  Future<void> _openRequestedCalendarAction() async {
    final DateTime? requestedDate = widget.requestedDate;
    final _CalendarDayAction? requestedAction = widget.requestedAction;

    if (requestedDate == null || requestedAction == null) {
      return;
    }

    final DateTime requestedMonth = DateTime(
      requestedDate.year,
      requestedDate.month,
    );

    if (_displayedMonth.year != requestedMonth.year ||
        _displayedMonth.month != requestedMonth.month) {
      setState(() {
        _displayedMonth = requestedMonth;
      });

      await _loadMonth();
    } else {
      try {
        final Map<String, Duty> latestDuties = await _dutyResolver
            .getResolvedDutiesForRange(requestedDate, requestedDate);

        if (!mounted) {
          return;
        }

        final Duty? latestDuty = latestDuties[_dateKey(requestedDate)];

        await _handleDayAction(
          date: requestedDate,
          duty: latestDuty ?? _dutiesByDate[_dateKey(requestedDate)],
          action: requestedAction,
        );

        return;
      } catch (_) {
        // Fall through and use the currently loaded Calendar duty.
      }
    }

    if (!mounted) {
      return;
    }

    await _handleDayAction(
      date: requestedDate,
      duty: _dutiesByDate[_dateKey(requestedDate)],
      action: requestedAction,
    );
  }

  Future<void> _loadMonth() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final List<DateTime> calendarDates = _calendarDates();

      final Future<Map<String, Duty>> dutiesFuture = _dutyResolver
          .getResolvedDutiesForRange(calendarDates.first, calendarDates.last);

      final Future<Map<String, AnnualLeaveRequest>> leaveRequestsFuture =
          _annualLeaveService.getRequestsForRange(
            calendarDates.first,
            calendarDates.last,
          );

      final movesFuture = _shiftSwapService.getRequests();
      final User? user = Supabase.instance.client.auth.currentUser;

      Future<List<dynamic>> scheduledRequestsFuture =
          Future<List<dynamic>>.value(const <dynamic>[]);

      if (user != null) {
        scheduledRequestsFuture = Supabase.instance.client
            .from('annual_leave_scheduled_requests')
            .select('leave_date')
            .eq('user_id', user.id)
            .eq('status', 'scheduled')
            .gte('leave_date', _dateKey(calendarDates.first))
            .lte('leave_date', _dateKey(calendarDates.last));
      }

      final moves = await movesFuture;
      final Map<String, Duty> dutiesByDate = await dutiesFuture;
      final Map<String, AnnualLeaveRequest> leaveRequestsByDate =
          await leaveRequestsFuture;
      final List<dynamic> scheduledRequests = await scheduledRequestsFuture;

      final Set<String> scheduledDateKeys = scheduledRequests
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> row) => row['leave_date']?.toString())
          .whereType<String>()
          .where((String value) => value.isNotEmpty)
          .toSet();

      if (!mounted) {
        return;
      }

      setState(() {
        _restDayMoves = moves.where((move) => move.status == ShiftSwapStatus.pending && move.notes?.startsWith('TYPE=Rest day move') == true).toList();
        _dutiesByDate = dutiesByDate;
        _leaveRequestsByDate = leaveRequestsByDate;
        _scheduledAnnualLeaveDateKeys = scheduledDateKeys;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _dutiesByDate = <String, Duty>{};
        _leaveRequestsByDate = <String, AnnualLeaveRequest>{};
        _scheduledAnnualLeaveDateKeys = <String>{};
        _isLoading = false;
        _loadError = error is DutyResolverException
            ? error.message
            : 'Roster Buddy could not load this month.';
      });
    }
  }

  List<DateTime> _calendarDates() {
    final DateTime firstDay = DateTime(
      _displayedMonth.year,
      _displayedMonth.month,
      1,
    );

    // DateTime weekday uses Monday = 1 and Sunday = 7.
    // Modulo seven changes this to Sunday = 0.
    final int leadingDays = firstDay.weekday % 7;

    final DateTime calendarStart = firstDay.subtract(
      Duration(days: leadingDays),
    );

    return List<DateTime>.generate(
      42,
      (int index) => calendarStart.add(Duration(days: index)),
      growable: false,
    );
  }

  Future<void> _changeMonth(int offset) async {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + offset,
      );
    });

    await _loadMonth();
  }

  Future<void> _goToCurrentMonth() async {
    final DateTime now = DateTime.now();

    setState(() {
      _displayedMonth = DateTime(now.year, now.month);
    });

    await _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [Expanded(child: RefreshIndicator(
      onRefresh: _loadMonth,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildMonthHeader(),
              if (_isSelectingAnnualLeaveDates) ...[
                const SizedBox(height: 12),
                _buildAnnualLeaveMultiSelectBanner(),
              ],
              if (_isSelectingAnnualLeaveCancellationDates) ...[
                const SizedBox(height: 12),
                _buildAnnualLeaveCancellationMultiSelectBanner(),
              ],
              const SizedBox(height: 14),
              _buildWeekdayHeader(),
              const SizedBox(height: 6),
              if (_isLoading)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_loadError != null)
                _buildErrorCard()
              else
                _buildMonthGrid(),
              const SizedBox(height: 16),
              _buildLegend(),
            ],
          ),
        ),
      ),
    )), if (_restDayPicker != null) _buildRestDaySelectionBar(),
    ]);
  }

  Widget _buildMonthHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    _monthTitle(_displayedMonth),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: navy,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton(
                    onPressed: _goToCurrentMonth,
                    child: const Text('Today'),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnualLeaveMultiSelectBanner() {
    final int selectedCount = _selectedAnnualLeaveDateKeys.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: leaveRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: leaveRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.date_range_outlined, color: leaveRed),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Select annual leave dates',
                  style: const TextStyle(
                    color: navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$selectedCount selected',
                style: const TextStyle(
                  color: leaveRed,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Tap each working date you want to request. You can move between months and your selections will stay selected.',
            style: TextStyle(color: textGrey, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelAnnualLeaveDateSelection,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: selectedCount == 0
                      ? null
                      : _reviewSelectedAnnualLeaveDates,
                  icon: const Icon(Icons.check),
                  label: const Text('Review dates'),
                  style: FilledButton.styleFrom(backgroundColor: leaveRed),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnnualLeaveCancellationMultiSelectBanner() {
    final int selectedCount = _selectedAnnualLeaveCancellationDateKeys.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_busy_outlined, color: leaveRed),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Select granted leave to cancel',
                    style: TextStyle(
                      color: navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '$selectedCount selected',
                  style: const TextStyle(
                    color: leaveRed,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            const Text(
              'Tap each granted annual leave date you want to cancel. '
              'You can move between months and your selections will stay selected.',
              style: TextStyle(color: textGrey, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelAnnualLeaveCancellationDateSelection,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: selectedCount == 0
                        ? null
                        : _reviewSelectedAnnualLeaveCancellationDates,
                    icon: const Icon(Icons.check),
                    label: const Text('Review dates'),
                    style: FilledButton.styleFrom(backgroundColor: leaveRed),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _cancelAnnualLeaveCancellationDateSelection() {
    setState(() {
      _isSelectingAnnualLeaveCancellationDates = false;
      _selectedAnnualLeaveCancellationDateKeys.clear();
    });
  }

  void _toggleAnnualLeaveCancellationDateSelection({
    required DateTime date,
    required AnnualLeaveRequest? leaveRequest,
  }) {
    if (leaveRequest == null ||
        leaveRequest.status != AnnualLeaveRequestStatus.granted) {
      _showCalendarMessage(
        'Only granted annual leave dates can be selected for cancellation.',
      );
      return;
    }

    final String key = _dateKey(date);

    setState(() {
      if (!_selectedAnnualLeaveCancellationDateKeys.remove(key)) {
        _selectedAnnualLeaveCancellationDateKeys.add(key);
      }
    });
  }

  void _cancelAnnualLeaveDateSelection() {
    setState(() {
      _isSelectingAnnualLeaveDates = false;
      _selectedAnnualLeaveDateKeys.clear();
    });
  }

  void _toggleAnnualLeaveDateSelection({
    required DateTime date,
    required Duty? duty,
    required AnnualLeaveRequest? leaveRequest,
  }) {
    if (date.weekday == DateTime.sunday) {
      _showCalendarMessage('Annual leave cannot be requested for a Sunday.');
      return;
    }

    if (duty == null || !duty.dutyType.countsAsWorking) {
      _showCalendarMessage(
        'Annual leave can only be requested for a working, training or medical duty.',
      );
      return;
    }

    if (leaveRequest != null &&
        leaveRequest.status != AnnualLeaveRequestStatus.cancelled) {
      _showCalendarMessage(
        'There is already an active annual leave request for ${_fullDate(date)}.',
      );
      return;
    }

    final String key = _dateKey(date);

    setState(() {
      if (!_selectedAnnualLeaveDateKeys.remove(key)) {
        _selectedAnnualLeaveDateKeys.add(key);
      }
    });
  }

  Future<void> _reviewSelectedAnnualLeaveDates() async {
    if (_selectedAnnualLeaveDateKeys.isEmpty) {
      return;
    }

    final List<DateTime> dates =
        _selectedAnnualLeaveDateKeys.map(DateTime.parse).toList()..sort();

    final List<DateTime> immediateDates = <DateTime>[];
    final List<DateTime> scheduledDates = <DateTime>[];

    for (final DateTime date in dates) {
      if (_annualLeaveService.shouldSendAnnualLeaveRequestNow(date)) {
        immediateDates.add(date);
      } else {
        scheduledDates.add(date);
      }
    }

    final StringBuffer summary = StringBuffer();

    if (immediateDates.isNotEmpty) {
      summary.writeln(
        '${immediateDates.length} date${immediateDates.length == 1 ? '' : 's'} '
        'will be requested now:',
      );

      for (final DateTime date in immediateDates) {
        summary.writeln('• ${_fullDate(date)}');
      }
    }

    if (immediateDates.isNotEmpty && scheduledDates.isNotEmpty) {
      summary.writeln();
    }

    if (scheduledDates.isNotEmpty) {
      summary.writeln(
        '${scheduledDates.length} date${scheduledDates.length == 1 ? '' : 's'} '
        'will be scheduled for 00:00 UK time, exactly 365 days beforehand:',
      );

      for (final DateTime date in scheduledDates) {
        summary.writeln('• ${_fullDate(date)}');
      }
    }

    Uri? immediateEmailUri;

    if (immediateDates.isNotEmpty) {
      final SupabaseClient supabase = Supabase.instance.client;
      final User? user = supabase.auth.currentUser;

      String driverName = '';
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

        driverName = (profile?['display_name'] ?? metadata['full_name'] ?? '')
            .toString()
            .trim();

        depot = (profile?['depot'] ?? metadata['depot'] ?? '')
            .toString()
            .trim();

        payrollNumber =
            (profile?['payroll_number'] ?? metadata['payroll_number'] ?? '')
                .toString()
                .trim();
      }

      final String requestedDates = immediateDates
          .map((DateTime date) => '- ${_fullDate(date)}')
          .join('\n');

      final List<String> signature = <String>[
        if (driverName.isNotEmpty) driverName,
        if (depot.isNotEmpty) depot,
        if (payrollNumber.isNotEmpty) 'Payroll Number: $payrollNumber',
      ];

      final String body =
          'Please can I request floating annual leave for the following '
          '${immediateDates.length == 1 ? 'date' : 'dates'}:\n\n'
          '$requestedDates\n\n'
          'Regards'
          '${signature.isEmpty ? '' : '\n${signature.join('\n')}'}';

      final String subject = immediateDates.length == 1
          ? 'Annual Leave Request - ${_fullDate(immediateDates.first)}'
          : 'Annual Leave Request - ${immediateDates.length} Dates';

      immediateEmailUri = _rosterBuddyMailUri(subject: subject, body: body);
    }

    Future<bool>? emailLaunchFuture;

    if (!mounted) {
      return;
    }

    final bool? confirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: Text(
            'Request ${dates.length} annual leave '
            'date${dates.length == 1 ? '' : 's'}?',
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(summary.toString().trim()),
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Continue editing'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Confirm requests'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final bool? alreadyAuthorised = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Annual leave authorised?'),
          content: Text(
            dates.length == 1
                ? 'Has this annual leave date already been authorised '
                      'by Rosters / DTCM?'
                : 'Have these ${dates.length} annual leave dates already '
                      'been authorised by Rosters / DTCM?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                if (immediateEmailUri != null) {
                  emailLaunchFuture = launchUrl(
                    immediateEmailUri,
                    mode: LaunchMode.platformDefault,
                    webOnlyWindowName: '_self',
                  );
                }

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

    if (alreadyAuthorised == null || !mounted) {
      return;
    }

    try {
      if (alreadyAuthorised) {
        final Map<int, int> authorisedCountByYear = <int, int>{};

        for (final DateTime date in dates) {
          authorisedCountByYear.update(
            date.year,
            (int value) => value + 1,
            ifAbsent: () => 1,
          );
        }

        for (final MapEntry<int, int> entry in authorisedCountByYear.entries) {
          final int remaining = await _annualLeaveService
              .getRemainingFloatingDays(entry.key);

          if (entry.value > remaining) {
            throw AnnualLeaveException(
              'You selected ${entry.value} floating leave '
              'date${entry.value == 1 ? '' : 's'} in ${entry.key}, '
              'but only $remaining '
              '${remaining == 1 ? 'day remains' : 'days remain'}.',
            );
          }
        }

        for (final DateTime date in dates) {
          final AnnualLeaveRequest request = await _annualLeaveService
              .requestFloatingLeave(date: date);

          await _annualLeaveService.markGranted(requestId: request.id);
        }

        await _loadMonth();

        if (!mounted) {
          return;
        }

        widget.onRosterChanged();

        setState(() {
          _isSelectingAnnualLeaveDates = false;
          _selectedAnnualLeaveDateKeys.clear();
        });

        _showCalendarMessage(
          dates.length == 1
              ? 'Floating annual leave granted for '
                    '${_fullDate(dates.first)}.'
              : '${dates.length} floating annual leave dates granted.',
        );

        return;
      }

      // Validate immediate requests against the available floating balance
      // before writing any live AL REQ rows.
      final Map<int, int> immediateCountByYear = <int, int>{};

      for (final DateTime date in immediateDates) {
        immediateCountByYear.update(
          date.year,
          (int value) => value + 1,
          ifAbsent: () => 1,
        );
      }

      for (final MapEntry<int, int> entry in immediateCountByYear.entries) {
        final int remaining = await _annualLeaveService
            .getRemainingFloatingDays(entry.key);

        if (entry.value > remaining) {
          throw AnnualLeaveException(
            'You selected ${entry.value} floating leave '
            'date${entry.value == 1 ? '' : 's'} in ${entry.key}, '
            'but only $remaining '
            '${remaining == 1 ? 'day remains' : 'days remain'}.',
          );
        }
      }

      final SupabaseClient supabase = Supabase.instance.client;
      final User? user = supabase.auth.currentUser;

      String driverName = '';
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

        driverName = (profile?['display_name'] ?? metadata['full_name'] ?? '')
            .toString()
            .trim();

        depot = (profile?['depot'] ?? metadata['depot'] ?? '')
            .toString()
            .trim();

        payrollNumber =
            (profile?['payroll_number'] ?? metadata['payroll_number'] ?? '')
                .toString()
                .trim();
      }

      final List<String> signature = <String>[
        if (driverName.isNotEmpty) driverName,
        if (depot.isNotEmpty) depot,
        if (payrollNumber.isNotEmpty) 'Payroll Number: $payrollNumber',
      ];

      // Future requests store their fully populated email now. Supabase
      // schedules each email for 00:00 Europe/London exactly 365 days before
      // the requested leave date.
      for (final DateTime date in scheduledDates) {
        final String body =
            'Please can I request floating annual leave for:\n\n'
            '${_fullDate(date)}\n\n'
            'Regards'
            '${signature.isEmpty ? '' : '\n${signature.join('\n')}'}';

        final String subject = 'Annual Leave Request - ${_fullDate(date)}';

        await _annualLeaveService.scheduleFloatingLeaveRequest(
          date: date,
          recipientEmail: 'drivers.rosters@wmtrains.co.uk',
          emailSubject: subject,
          emailBody: body,
        );
      }

      // Dates already inside the request window become live requests now.
      for (final DateTime date in immediateDates) {
        await _annualLeaveService.requestFloatingLeave(date: date);
      }

      bool emailOpened = true;

      if (emailLaunchFuture != null) {
        emailOpened = await emailLaunchFuture ?? false;
      }

      await _loadMonth();

      if (!mounted) {
        return;
      }

      widget.onRosterChanged();

      setState(() {
        _isSelectingAnnualLeaveDates = false;
        _selectedAnnualLeaveDateKeys.clear();
      });

      if (immediateDates.isNotEmpty && scheduledDates.isNotEmpty) {
        _showCalendarMessage(
          '${immediateDates.length} annual leave '
          '${immediateDates.length == 1 ? 'request is' : 'requests are'} ready '
          'to send now and ${scheduledDates.length} '
          '${scheduledDates.length == 1 ? 'date has' : 'dates have'} been '
          'scheduled for later.',
        );
      } else if (scheduledDates.isNotEmpty) {
        _showCalendarMessage(
          '${scheduledDates.length} annual leave '
          '${scheduledDates.length == 1 ? 'date has' : 'dates have'} been '
          'scheduled for the 365-day request point.',
        );
      } else {
        _showCalendarMessage(
          '${immediateDates.length} annual leave '
          '${immediateDates.length == 1 ? 'request is' : 'requests are'} '
          'ready to send to Rosters.',
        );
      }

      if (!emailOpened) {
        _showCalendarMessage(
          'The annual leave request was saved, but Roster Buddy could not '
          'open the email app.',
        );
      }
    } on AnnualLeaveException catch (error) {
      if (!mounted) {
        return;
      }

      _showCalendarMessage(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showCalendarMessage(
        'Roster Buddy could not process the selected annual leave dates.',
      );
    }
  }

  Future<void> _processSingleAnnualLeaveRequest({
    required DateTime date,
  }) async {
    if (date.weekday == DateTime.sunday) {
      _showCalendarMessage('Annual leave cannot be requested for a Sunday.');
      return;
    }

    try {
      final SupabaseClient supabase = Supabase.instance.client;
      final User? user = supabase.auth.currentUser;

      String driverName = '';
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

        driverName = (profile?['display_name'] ?? metadata['full_name'] ?? '')
            .toString()
            .trim();

        depot = (profile?['depot'] ?? metadata['depot'] ?? '')
            .toString()
            .trim();

        payrollNumber =
            (profile?['payroll_number'] ?? metadata['payroll_number'] ?? '')
                .toString()
                .trim();
      }

      final List<String> signature = <String>[
        if (driverName.isNotEmpty) driverName,
        if (depot.isNotEmpty) depot,
        if (payrollNumber.isNotEmpty) 'Payroll Number: $payrollNumber',
      ];

      final String subject = 'Annual Leave Request - ${_fullDate(date)}';

      final String body =
          'Please can I request floating annual leave for:\n\n'
          '${_fullDate(date)}\n\n'
          'Regards'
          '${signature.isEmpty ? '' : '\n${signature.join('\n')}'}';

      final Uri emailUri = _rosterBuddyMailUri(subject: subject, body: body);

      Future<bool>? emailLaunchFuture;

      if (!mounted) {
        return;
      }

      final bool? alreadyAuthorised = await showRosterDecisionSheet<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return RosterDecisionSheet(
            title: const Text('Annual leave authorised?'),
            content: Text(
              'Has the annual leave for ${_fullDate(date)} already been '
              'authorised by Rosters / DTCM?',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () {
                  // Only launch Mail now when the request is inside
                  // the 365-day request window.
                  if (_annualLeaveService.shouldSendAnnualLeaveRequestNow(
                    date,
                  )) {
                    emailLaunchFuture = launchUrl(
                      emailUri,
                      mode: LaunchMode.platformDefault,
                      webOnlyWindowName: '_self',
                    );
                  }

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

      if (alreadyAuthorised == null || !mounted) {
        return;
      }

      if (alreadyAuthorised) {
        final int remainingDays = await _annualLeaveService
            .getRemainingFloatingDays(date.year);

        if (remainingDays <= 0) {
          throw const AnnualLeaveException(
            'You do not have any floating annual leave days remaining.',
          );
        }

        final AnnualLeaveRequest request = await _annualLeaveService
            .requestFloatingLeave(date: date);

        await _annualLeaveService.markGranted(requestId: request.id);

        await _loadMonth();

        if (!mounted) {
          return;
        }

        widget.onRosterChanged();

        _showCalendarMessage(
          'Floating annual leave granted for ${_fullDate(date)}.',
        );

        return;
      }

      if (!_annualLeaveService.shouldSendAnnualLeaveRequestNow(date)) {
        await _annualLeaveService.scheduleFloatingLeaveRequest(
          date: date,
          recipientEmail: 'drivers.rosters@wmtrains.co.uk',
          emailSubject: subject,
          emailBody: body,
        );

        if (!mounted) {
          return;
        }

        final DateTime sendDate = DateTime(
          date.year,
          date.month,
          date.day,
        ).subtract(const Duration(days: 365));

        _showCalendarMessage(
          'Annual leave for ${_fullDate(date)} is scheduled to be sent '
          'at 00:00 on ${_fullDate(sendDate)}.',
        );

        return;
      }

      final int remainingDays = await _annualLeaveService
          .getRemainingFloatingDays(date.year);

      if (remainingDays <= 0) {
        throw const AnnualLeaveException(
          'You do not have any floating annual leave days remaining.',
        );
      }

      await _annualLeaveService.requestFloatingLeave(date: date);

      final bool opened = emailLaunchFuture == null
          ? false
          : await emailLaunchFuture ?? false;

      await _loadMonth();

      if (!mounted) {
        return;
      }

      widget.onRosterChanged();

      if (!opened) {
        _showCalendarMessage(
          'Annual leave was saved, but Roster Buddy could not open the email app.',
        );
        return;
      }

      _showCalendarMessage('Annual leave requested for ${_fullDate(date)}.');
    } on AnnualLeaveException catch (error) {
      if (!mounted) {
        return;
      }

      _showCalendarMessage(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showCalendarMessage(
        'Roster Buddy could not process this annual leave request.',
      );
    }
  }

  Future<void> _startAnnualLeaveMultiSelect({
    required DateTime initialDate,
    required Duty initialDuty,
  }) async {
    if (initialDate.weekday == DateTime.sunday) {
      _showCalendarMessage('Annual leave cannot be requested for a Sunday.');
      return;
    }

    if (!initialDuty.dutyType.countsAsWorking) {
      _showCalendarMessage(
        'Annual leave can only be requested for a working, training or medical duty.',
      );
      return;
    }

    final AnnualLeaveRequest? existing =
        _leaveRequestsByDate[_dateKey(initialDate)];

    if (existing != null &&
        existing.status != AnnualLeaveRequestStatus.cancelled) {
      _showCalendarMessage(
        'There is already an active annual leave request for this date.',
      );
      return;
    }

    widget.onOpenCalendar();

    setState(() {
      _isSelectingAnnualLeaveDates = true;
      _selectedAnnualLeaveDateKeys
        ..clear()
        ..add(_dateKey(initialDate));

      _displayedMonth = DateTime(initialDate.year, initialDate.month);
    });

    await _loadMonth();
  }

  Future<void> _chooseAnnualLeaveRequestScope({
    required DateTime date,
    required Duty duty,
  }) async {
    if (_scheduledAnnualLeaveDateKeys.contains(_dateKey(date))) {
      _showCalendarMessage(
        'Annual leave for this date is already queued to be sent.',
      );
      return;
    }

    final String? choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext popupContext) {
        return CupertinoActionSheet(
          title: const Text('Request annual leave'),
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
            child: const Text('Cancel'),
          ),
        );
      },
    );

    if (!mounted || choice == null) {
      return;
    }

    if (choice == 'single') {
      await _processSingleAnnualLeaveRequest(date: date);
      return;
    }

    await _startAnnualLeaveMultiSelect(initialDate: date, initialDuty: duty);
  }

  Widget _buildWeekdayHeader() {
    const List<String> weekdays = <String>[
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
    ];

    return Row(
      children: weekdays
          .map(
            (String weekday) => Expanded(
              child: Center(
                child: Text(
                  weekday,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildMonthGrid() {
    final List<DateTime> dates = _calendarDates();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: dates.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (BuildContext context, int index) {
        final DateTime date = dates[index];
        final String dateKey = _dateKey(date);
        final Duty? duty = _dutiesByDate[dateKey];
        final AnnualLeaveRequest? leaveRequest = _leaveRequestsByDate[dateKey];
        final bool isQueuedAnnualLeave = _scheduledAnnualLeaveDateKeys.contains(
          dateKey,
        );

        return _buildDayCell(
          date: date,
          duty: duty,
          leaveRequest: leaveRequest,
          isQueuedAnnualLeave: isQueuedAnnualLeave,
        );
      },
    );
  }

  Widget _buildDayCell({
    required DateTime date,
    required Duty? duty,
    required AnnualLeaveRequest? leaveRequest,
    required bool isQueuedAnnualLeave,
  }) {
    final bool belongsToDisplayedMonth =
        date.year == _displayedMonth.year &&
        date.month == _displayedMonth.month;

    final DateTime now = DateTime.now();
    final bool isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    final bool isGrantedAnnualLeave =
        leaveRequest?.status == AnnualLeaveRequestStatus.granted;

    final Color dutyColour = isGrantedAnnualLeave
        ? leaveRed
        : duty == null
        ? Colors.white
        : _colourForDuty(duty.dutyType);

    final bool useDarkText =
        !isGrantedAnnualLeave &&
        (duty == null ||
            duty.dutyType == DutyType.restDay ||
            duty.dutyType == DutyType.unavailable);

    final Color foreground = useDarkText ? navy : Colors.white;
    final bool isSelectedAnnualLeaveDate = _selectedAnnualLeaveDateKeys
        .contains(_dateKey(date));
    final bool isSelectedAnnualLeaveCancellationDate =
        _selectedAnnualLeaveCancellationDateKeys.contains(_dateKey(date));

    return Opacity(
      opacity: belongsToDisplayedMonth ? 1 : 0.42,
      child: Material(
        color: dutyColour,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            if (_restDayPicker != null) {
              _toggleRestDayDate(date);
              return;
            }
            if (_isSelectingAnnualLeaveCancellationDates) {
              _toggleAnnualLeaveCancellationDateSelection(
                date: date,
                leaveRequest: leaveRequest,
              );
              return;
            }

            if (_isSelectingAnnualLeaveDates) {
              _toggleAnnualLeaveDateSelection(
                date: date,
                duty: duty,
                leaveRequest: leaveRequest,
              );
              return;
            }

            _showDayDetails(date: date, duty: duty);
          },
          onLongPress:
              (_restDayPicker != null || _isSelectingAnnualLeaveDates ||
                  _isSelectingAnnualLeaveCancellationDates)
              ? null
              : () => _showDayActions(date: date, duty: duty),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color:
                    (isSelectedAnnualLeaveDate ||
                        isSelectedAnnualLeaveCancellationDate)
                    ? leaveRed
                    : isToday
                    ? railwayBlue
                    : const Color(0xFFD8E0E8),
                width:
                    (isSelectedAnnualLeaveDate ||
                        isSelectedAnnualLeaveCancellationDate)
                    ? 3
                    : isToday
                    ? 2.5
                    : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        date.day.toString(),
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (_restDayPicker != null && _restDayChoices.containsKey(_dateKey(date)))
                      SizedBox(width: 22, height: 22, child: Checkbox(
                        value: _restDaySelected.contains(_dateKey(date)),
                        fillColor: const WidgetStatePropertyAll(Colors.white),
                        checkColor: railwayBlue,
                        onChanged: (_) => _toggleRestDayDate(date),
                      )),
                    if (isSelectedAnnualLeaveDate ||
                        isSelectedAnnualLeaveCancellationDate)
                      Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: leaveRed,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
                if (isQueuedAnnualLeave && !isGrantedAnnualLeave) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: railwayBlue,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'AL QUEUED',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
                if (leaveRequest != null &&
                    leaveRequest.status != AnnualLeaveRequestStatus.cancelled &&
                    !isGrantedAnnualLeave) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          leaveRequest.status ==
                              AnnualLeaveRequestStatus.abeyance
                          ? const Color(0xFFF59E0B)
                          : leaveRed,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      leaveRequest.status == AnnualLeaveRequestStatus.abeyance
                          ? leaveRequest.queuePosition == null
                                ? 'ABE'
                                : 'ABE #${leaveRequest.queuePosition}'
                          : leaveRequest.status ==
                                AnnualLeaveRequestStatus.requested
                          ? 'AL REQ'
                          : 'AL',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (duty != null || isGrantedAnnualLeave) ...[
                  Text(
                    isGrantedAnnualLeave ? 'Leave' : duty?.remarks?.contains('awaiting allocation') == true ? 'Allocate duty' : _shortDutyLabel(duty!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!isGrantedAnnualLeave &&
                      duty?.bookOn?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      duty!.bookOn!.trim(),
                      maxLines: 1,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: useDarkText
                            ? railwayBlue.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isGrantedAnnualLeave
                            ? (leaveRequest?.requestType ==
                                      AnnualLeaveRequestType.floating
                                  ? 'ALD'
                                  : 'AW')
                            : _sourceLabel(duty!.source),
                        style: TextStyle(
                          color: foreground,
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: leaveRed, size: 34),
            const SizedBox(height: 10),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: textGrey),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _loadMonth,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Wrap(
          spacing: 14,
          runSpacing: 10,
          children: [
            _CalendarLegendItem(colour: workingGreen, label: 'Working'),
            _CalendarLegendItem(colour: restYellow, label: 'Rest day'),
            _CalendarLegendItem(colour: leaveRed, label: 'Annual leave'),
          ],
        ),
      ),
    );
  }

  Future<void> _showSelectTurnNumberDialog({
    required DateTime date,
    required Duty originalDuty,
  }) async {
    const String manualSelection = '__MANUAL_TURN__';

    List<JobCardChoice> choices = <JobCardChoice>[];

    try {
      choices = await _jobCardService.findValidJobCardsForDate(dutyDate: date);
    } catch (_) {
      // Manual entry remains available even if Job Cards cannot be loaded.
    }

    if (!mounted) {
      return;
    }

    final Object? selected = await showCupertinoModalPopup<Object>(
      context: context,
      builder: (BuildContext popupContext) {
        return CupertinoActionSheet(
          title: Text('Select turn – ${_fullDate(date)}'),
          message: Text(
            choices.isEmpty
                ? 'No Job Card turns are available for this date. '
                      'You can enter the turn manually.'
                : 'Select a Job Card turn or enter the duty manually.',
          ),
          actions: <Widget>[
            ...choices.map(
              (JobCardChoice choice) => CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(popupContext).pop(choice);
                },
                child: Text(
                  'Turn ${choice.jobCard.turnNumber}  •  '
                  '${choice.jobCard.bookOn}–${choice.jobCard.bookOff}'
                  '${choice.jobCard.dayCode.trim().isEmpty ? '' : '  •  ${choice.jobCard.dayCode}'}',
                ),
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop(manualSelection);
              },
              child: const Text('Enter turn manually'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(popupContext).pop();
            },
            child: const Text('Cancel'),
          ),
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    if (selected is JobCardChoice) {
      final card = selected.jobCard;

      try {
        await _manualDutyService.saveSelectedTurn(
          date: date,
          turnNumber: card.turnNumber,
          bookOn: card.bookOn,
          bookOff: card.bookOff,
          originalDuty: originalDuty,
        );

        await _loadMonth();

        if (!mounted) {
          return;
        }

        _showCalendarMessage(
          'Turn ${card.turnNumber} selected for ${_fullDate(date)}.',
        );
      } on ManualDutyException catch (error) {
        if (!mounted) {
          return;
        }

        _showCalendarMessage(error.message);
      } catch (_) {
        if (!mounted) {
          return;
        }

        _showCalendarMessage('Roster Buddy could not save the selected turn.');
      }

      return;
    }

    if (selected != manualSelection) {
      return;
    }

    final TextEditingController turnController = TextEditingController(
      text: originalDuty.turnNumber?.trim() ?? '',
    );
    final TextEditingController bookOnController = TextEditingController(
      text: originalDuty.bookOn?.trim() ?? '',
    );
    final TextEditingController bookOffController = TextEditingController(
      text: originalDuty.bookOff?.trim() ?? '',
    );

    bool isSaving = false;
    String? formError;

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setSheetState,
              ) {
                Future<void> saveManualTurn() async {
                  final String turnNumber = turnController.text.trim();
                  final String bookOn = _normaliseTimeInput(
                    bookOnController.text,
                  );
                  final String bookOff = _normaliseTimeInput(
                    bookOffController.text,
                  );

                  if (turnNumber.isEmpty) {
                    setSheetState(() {
                      formError = 'Enter the turn number.';
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
                    await _manualDutyService.saveSelectedTurn(
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
                  } on ManualDutyException catch (error) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      isSaving = false;
                      formError = error.message;
                    });
                  } catch (_) {
                    if (!sheetContext.mounted) {
                      return;
                    }

                    setSheetState(() {
                      isSaving = false;
                      formError =
                          'Roster Buddy could not save the manual turn.';
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
                          const Text(
                            'Enter turn manually',
                            style: TextStyle(
                              color: navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fullDate(date),
                            style: const TextStyle(color: textGrey),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: turnController,
                            enabled: !isSaving,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Turn number / duty reference',
                              hintText: 'For example WO201',
                              border: OutlineInputBorder(),
                            ),
                          ),
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
                              onPressed: isSaving ? null : saveManualTurn,
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
                                isSaving ? 'Saving…' : 'Save selected turn',
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

    if (saved != true || !mounted) {
      return;
    }

    await _loadMonth();

    if (!mounted) {
      return;
    }

    _showCalendarMessage('Turn updated for ${_fullDate(date)}.');
  }

  Future<JobCardMatch?> _findCalendarJobCard(Duty duty) async {
    final String turnNumber = duty.turnNumber?.trim() ?? '';

    if (turnNumber.isEmpty || !duty.dutyType.countsAsWorking) {
      return null;
    }

    try {
      return await _jobCardService.findMatchingJobCard(
        turnNumber: turnNumber,
        dutyDate: duty.date,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openCalendarJobCard(JobCardMatch match) async {
    try {
      final String signedUrl = await _jobCardService.createSignedPdfUrl(match);
      Uri pdfUri = Uri.parse(signedUrl);

      final int? pageNumber = match.jobCard.pageNumber;

      if (pageNumber != null && pageNumber > 0) {
        pdfUri = pdfUri.replace(fragment: 'page=$pageNumber');
      }

      final bool opened = await launchUrl(
        pdfUri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );

      if (!opened && mounted) {
        _showCalendarMessage('Roster Buddy could not open this Job Card.');
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showCalendarMessage('Roster Buddy could not open this Job Card.');
    }
  }

  Future<void> _cancelQueuedAnnualLeaveRequest(DateTime date) async {
    final bool? confirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Cancel queued annual leave?'),
          content: Text(
            'The scheduled annual leave request for ${_fullDate(date)} '
            'will be removed from the send queue.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Keep queued'),
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
      await _annualLeaveService.cancelScheduledFloatingLeaveRequest(date: date);

      await _loadMonth();

      if (!mounted) {
        return;
      }

      widget.onRosterChanged();

      _showCalendarMessage(
        'Queued annual leave cancelled for ${_fullDate(date)}.',
      );
    } on AnnualLeaveException catch (error) {
      if (!mounted) {
        return;
      }

      _showCalendarMessage(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showCalendarMessage(
        'Roster Buddy could not cancel this queued annual leave request.',
      );
    }
  }

  Future<void> _recordRequestedAnnualLeaveDecision({
    required DateTime date,
    required AnnualLeaveRequest request,
  }) async {
    final bool? alreadyConfirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Annual leave confirmed?'),
          content: Text(
            'Has the annual leave for ${_fullDate(date)} already been '
            'confirmed by Rosters / DTCM?',
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
        await _annualLeaveService.markGranted(requestId: request.id);

        await _loadMonth();

        if (!mounted) {
          return;
        }

        widget.onRosterChanged();

        _showCalendarMessage(
          'Floating annual leave granted for ${_fullDate(date)}.',
        );

        return;
      }

      final SupabaseClient supabase = Supabase.instance.client;
      final User? user = supabase.auth.currentUser;

      String driverName = '';
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

        driverName = (profile?['display_name'] ?? metadata['full_name'] ?? '')
            .toString()
            .trim();

        depot = (profile?['depot'] ?? metadata['depot'] ?? '')
            .toString()
            .trim();

        payrollNumber =
            (profile?['payroll_number'] ?? metadata['payroll_number'] ?? '')
                .toString()
                .trim();
      }

      final List<String> signature = <String>[
        if (driverName.isNotEmpty) driverName,
        if (depot.isNotEmpty) depot,
        if (payrollNumber.isNotEmpty) 'Payroll Number: $payrollNumber',
      ];

      final String subject = 'Annual Leave Request - ${_fullDate(date)}';

      final String body =
          'Please can I request floating annual leave for:\n\n'
          '${_fullDate(date)}\n\n'
          'Regards'
          '${signature.isEmpty ? '' : '\n${signature.join('\n')}'}';

      final Uri emailUri = _rosterBuddyMailUri(subject: subject, body: body);

      final bool opened = await launchUrl(
        emailUri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );

      if (!opened && mounted) {
        _showCalendarMessage('Roster Buddy could not open the email app.');
      }
    } on AnnualLeaveException catch (error) {
      if (mounted) {
        _showCalendarMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showCalendarMessage(
          'Roster Buddy could not record the annual leave decision.',
        );
      }
    }
  }

  Future<void> _cancelActiveAnnualLeaveRequest({
    required DateTime date,
    required AnnualLeaveRequest request,
  }) async {
    final bool? alreadyConfirmed = await showRosterDecisionSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RosterDecisionSheet(
          title: const Text('Cancellation confirmed?'),
          content: Text(
            'Has the cancellation of your annual leave request for '
            '${_fullDate(date)} already been confirmed by Rosters / DTCM?',
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
        await _annualLeaveService.cancelRequest(requestId: request.id);

        await _loadMonth();

        if (!mounted) {
          return;
        }

        widget.onRosterChanged();

        _showCalendarMessage(
          'Annual leave request cancelled for ${_fullDate(date)}. '
          'Your allocated rostered duty now applies again.',
        );

        return;
      }

      final bool opened = await _openAnnualLeaveRequestCancellationEmail(
        dateLabel: _fullDate(date),
      );

      if (!mounted) {
        return;
      }

      if (opened) {
        _showCalendarMessage(
          'Cancellation email prepared. The annual leave request '
          'will remain active until Rosters / DTCM confirms cancellation.',
        );
      } else {
        _showCalendarMessage(
          'Roster Buddy could not open your email app. '
          'The annual leave request remains active.',
        );
      }
    } on AnnualLeaveException catch (error) {
      if (mounted) {
        _showCalendarMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showCalendarMessage(
          'Roster Buddy could not process this annual leave cancellation.',
        );
      }
    }
  }

  void _showDayDetails({required DateTime date, required Duty? duty}) {
    final AnnualLeaveRequest? leaveRequest =
        _leaveRequestsByDate[_dateKey(date)];

    final bool isGrantedAnnualLeave =
        leaveRequest?.status == AnnualLeaveRequestStatus.granted;

    final pendingMove = _restDayMoves.where((move) => restDayMovePairs(move.notes!).any(
      (pair) => pair['allocated'] != true && (pair['rest'] == _dateKey(date) || pair['work'] == _dateKey(date)),
    )).firstOrNull;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullDate(date),
                  style: const TextStyle(
                    color: navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                if (duty == null && !isGrantedAnnualLeave)
                  const Text(
                    'No roster information is available for this date.',
                    style: TextStyle(color: textGrey),
                  )
                else ...[
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isGrantedAnnualLeave
                              ? leaveRed
                              : _colourForDuty(duty!.dutyType),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isGrantedAnnualLeave
                              ? 'Annual Leave'
                              : _longDutyLabel(duty!),
                          style: const TextStyle(
                            color: navy,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (isGrantedAnnualLeave)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: leaveRed.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            leaveRequest?.requestType ==
                                    AnnualLeaveRequestType.floating
                                ? 'ALD'
                                : 'AW',
                            style: const TextStyle(
                              color: leaveRed,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      else
                        _RosterSourceBadge(source: duty!.source),
                    ],
                  ),
                  if (!isGrantedAnnualLeave &&
                      duty != null &&
                      (duty.bookOn != null || duty.bookOff != null)) ...[
                    const SizedBox(height: 14),
                    Text(
                      _timeDescription(duty),
                      style: const TextStyle(color: navy),
                    ),
                  ],
                  if (!isGrantedAnnualLeave &&
                      duty?.turnNumber?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Turn ${duty!.turnNumber!.trim()}',
                      style: const TextStyle(color: navy),
                    ),
                  ],
                  if (!isGrantedAnnualLeave &&
                      duty?.remarks?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      displayDatesInText(duty!.remarks!.trim()),
                      style: const TextStyle(color: textGrey),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _DutyHistorySection(
                    future: DutyHistoryService().load(date, _dutyResolver.getDutiesForDate(date)),
                    onChanged: () { widget.onRosterChanged(); _loadMonth(); },
                  ),
                  const SizedBox(height: 22),
                  if (_scheduledAnnualLeaveDateKeys.contains(
                    _dateKey(date),
                  )) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: railwayBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: railwayBlue.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.schedule_send_outlined,
                            color: railwayBlue,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Annual leave queued',
                                  style: TextStyle(
                                    color: navy,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'This request is waiting for its 365-day send date.',
                                  style: TextStyle(
                                    color: textGrey,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_leaveRequestsByDate[_dateKey(date)] != null) ...[
                    const SizedBox(height: 18),
                    _buildAnnualLeaveRequestStatus(
                      _leaveRequestsByDate[_dateKey(date)]!,
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (duty != null && duty.dutyType == DutyType.working) ...[
                    FutureBuilder<JobCardMatch?>(
                      future: _findCalendarJobCard(duty),
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<JobCardMatch?> snapshot,
                          ) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: null,
                                  icon: const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  label: const Text('Checking Job Card…'),
                                ),
                              );
                            }

                            final JobCardMatch? match = snapshot.data;

                            if (match == null) {
                              return SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: null,
                                  icon: const Icon(Icons.description_outlined),
                                  label: const Text('Job Card not available'),
                                ),
                              );
                            }

                            return SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();

                                  Future<void>.delayed(
                                    const Duration(milliseconds: 150),
                                    () {
                                      if (mounted) {
                                        _openCalendarJobCard(match);
                                      }
                                    },
                                  );
                                },
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Open Job Card'),
                              ),
                            );
                          },
                    ),
                    const SizedBox(height: 12),
                    if (!_scheduledAnnualLeaveDateKeys.contains(
                          _dateKey(date),
                        ) &&
                        (_leaveRequestsByDate[_dateKey(date)] == null ||
                            _leaveRequestsByDate[_dateKey(date)]!.status ==
                                AnnualLeaveRequestStatus.cancelled)) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();

                            _handleDayAction(
                              date: date,
                              duty: duty,
                              action: _CalendarDayAction.requestAnnualLeave,
                            );
                          },
                          icon: const Icon(Icons.beach_access_outlined),
                          label: const Text('Request annual leave'),
                          style: FilledButton.styleFrom(
                            backgroundColor: leaveRed,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                  if (duty != null && duty.dutyType == DutyType.restDay) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _handleDayAction(
                            date: date,
                            duty: duty,
                            action: _CalendarDayAction.allocateShift,
                          );
                        },
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Allocate shift – RDW'),
                        style: FilledButton.styleFrom(
                          backgroundColor: workingGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (duty != null && _isPostBlockUnavailableSunday(duty)) ...[
                    _buildPostBlockSundayAction(
                      sheetContext: sheetContext,
                      date: date,
                      duty: duty,
                    ),
                  ],
                if (pendingMove != null) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _actionCalendarRestMove(pendingMove, date);
                    },
                    child: Text(pendingMove.notes!.contains('ALLOCATION_REQUIRED=true')
                      ? 'Allocate new working day' : 'Action pending rest day move'),
                  ),
                ],
                  if (_scheduledAnnualLeaveDateKeys.contains(_dateKey(date))) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _cancelQueuedAnnualLeaveRequest(date);
                        },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel queued request'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: leaveRed,
                        ),
                      ),
                    ),
                  ],
                  if (_leaveRequestsByDate[_dateKey(date)] != null) ...[
                    const SizedBox(height: 12),
                    if (_leaveRequestsByDate[_dateKey(date)]!.status ==
                            AnnualLeaveRequestStatus.requested ||
                        _leaveRequestsByDate[_dateKey(date)]!.status ==
                            AnnualLeaveRequestStatus.abeyance) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            final AnnualLeaveRequest leaveRequest =
                                _leaveRequestsByDate[_dateKey(date)]!;

                            Navigator.of(sheetContext).pop();

                            Future<void>.delayed(
                              const Duration(milliseconds: 150),
                              () async {
                                if (!mounted) {
                                  return;
                                }

                                await _showManageAnnualLeaveDialog(
                                  date: date,
                                  request: leaveRequest,
                                );
                              },
                            );
                          },
                          icon: const Icon(Icons.event_note_outlined),
                          label: const Text('Action annual leave'),
                          style: FilledButton.styleFrom(
                            backgroundColor: leaveRed,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final AnnualLeaveRequest leaveRequest =
                              _leaveRequestsByDate[_dateKey(date)]!;

                          Navigator.of(sheetContext).pop();

                          Future<void>.delayed(
                            const Duration(milliseconds: 150),
                            () async {
                              if (!mounted) {
                                return;
                              }

                              if (leaveRequest.status ==
                                  AnnualLeaveRequestStatus.granted) {
                                await _chooseGrantedAnnualLeaveCancellationScope(
                                  date: date,
                                );
                              } else {
                                await _cancelActiveAnnualLeaveRequest(
                                  date: date,
                                  request: leaveRequest,
                                );
                              }
                            },
                          );
                        },
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(
                          _leaveRequestsByDate[_dateKey(date)]!.status ==
                                  AnnualLeaveRequestStatus.granted
                              ? 'Cancel annual leave'
                              : 'Cancel annual leave request',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: leaveRed,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _showDayActions(date: date, duty: duty);
                      },
                      icon: const Icon(Icons.more_horiz),
                      label: const Text('More day actions'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDayActions({
    required DateTime date,
    required Duty? duty,
  }) async {
    final AnnualLeaveRequest? leaveRequest =
        _leaveRequestsByDate[_dateKey(date)];

    final List<_CalendarDayAction> actions = _actionsForDuty(
      duty,
      leaveRequest: leaveRequest,
    );

    if (actions.isEmpty) {
      _showCalendarMessage(
        'No actions are currently available for ${_fullDate(date)}.',
      );
      return;
    }

    final _CalendarDayAction? selected =
        await showCupertinoModalPopup<_CalendarDayAction>(
          context: context,
          builder: (BuildContext popupContext) {
            return CupertinoActionSheet(
              title: Text(_fullDate(date)),
              message: Text(
                duty == null ? 'No roster information' : _longDutyLabel(duty),
              ),
              actions: actions
                  .map(
                    (_CalendarDayAction action) => CupertinoActionSheetAction(
                      onPressed: () {
                        Navigator.of(popupContext).pop(action);
                      },
                      isDestructiveAction:
                          action == _CalendarDayAction.moveRestDayHere,
                      child: Text(_dayActionLabel(action)),
                    ),
                  )
                  .toList(growable: false),
              cancelButton: CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(popupContext).pop();
                },
                child: const Text('Cancel'),
              ),
            );
          },
        );

    if (selected == null || !mounted) {
      return;
    }

    _handleDayAction(date: date, duty: duty, action: selected);
  }

  List<_CalendarDayAction> _actionsForDuty(
    Duty? duty, {
    AnnualLeaveRequest? leaveRequest,
  }) {
    if (duty == null) {
      return const <_CalendarDayAction>[];
    }

    if (duty.dutyType == DutyType.restDay) {
      return <_CalendarDayAction>[
        _CalendarDayAction.allocateShift,
        _CalendarDayAction.moveRestDays,
        if (duty.source == RosterSource.manual)
          _CalendarDayAction.manualChange,
      ];
    }

    if (_isPermanentlyUnavailableSunday(duty)) {
      return const <_CalendarDayAction>[_CalendarDayAction.makeSundayAvailable];
    }

    final bool hasActiveLeaveRequest =
        leaveRequest != null &&
        leaveRequest.status != AnnualLeaveRequestStatus.cancelled;

    if (duty.dutyType == DutyType.annualLeave) {
      if (hasActiveLeaveRequest) {
        return const <_CalendarDayAction>[_CalendarDayAction.manageAnnualLeave];
      }
      // Imported leave has no request to manage; allow its roster entry to be corrected.
      if (duty.source == RosterSource.manual) {
        return const <_CalendarDayAction>[_CalendarDayAction.manualChange];
      }
    }

    if (duty.source == RosterSource.manual &&
        !hasActiveLeaveRequest &&
        (duty.dutyType == DutyType.unknown ||
            duty.dutyType == DutyType.publicHoliday ||
            duty.dutyType == DutyType.sick ||
            duty.dutyType == DutyType.unavailable)) {
      return const <_CalendarDayAction>[_CalendarDayAction.manualChange];
    }

    if (duty.dutyType == DutyType.working) {
      return <_CalendarDayAction>[
        _CalendarDayAction.editTimes,
        _CalendarDayAction.selectTurnNumber,
        _CalendarDayAction.manualChange,
        _CalendarDayAction.shiftSwap,
        _CalendarDayAction.moveRestDayHere,
        if (hasActiveLeaveRequest)
          _CalendarDayAction.manageAnnualLeave
        else
          _CalendarDayAction.requestAnnualLeave,
      ];
    }

    if (duty.dutyType == DutyType.training ||
        duty.dutyType == DutyType.medical) {
      return <_CalendarDayAction>[
        _CalendarDayAction.editTimes,
        _CalendarDayAction.selectTurnNumber,
        _CalendarDayAction.manualChange,
        _CalendarDayAction.shiftSwap,
        _CalendarDayAction.moveRestDayHere,
        if (hasActiveLeaveRequest)
          _CalendarDayAction.manageAnnualLeave
        else
          _CalendarDayAction.requestAnnualLeave,
      ];
    }

    return const <_CalendarDayAction>[];
  }

  Future<void> _handleDayAction({
    required DateTime date,
    required Duty? duty,
    required _CalendarDayAction action,
    bool resolveFresh = true,
  }) async {
    Duty? effectiveDuty = duty;

    if (resolveFresh) {
      try {
        final Map<String, Duty> latestDuties = await _dutyResolver
            .getResolvedDutiesForRange(date, date);

        effectiveDuty = latestDuties[_dateKey(date)] ?? duty;
      } catch (_) {
        // If a fresh resolve fails, fall back to the duty already displayed.
      }
    }

    if (!mounted) {
      return;
    }

    switch (action) {
      case _CalendarDayAction.editTimes:
        if (effectiveDuty == null) {
          _showCalendarMessage(
            'No roster duty is available to edit for this date.',
          );
          return;
        }

        _showEditDutyDialog(date: date, originalDuty: effectiveDuty);
        return;

      case _CalendarDayAction.selectTurnNumber:
        if (effectiveDuty == null || !effectiveDuty.dutyType.countsAsWorking) {
          _showCalendarMessage(
            'A turn can only be selected for a working duty.',
          );
          return;
        }

        _showSelectTurnNumberDialog(date: date, originalDuty: effectiveDuty);
        return;

      case _CalendarDayAction.manualChange:
        if (effectiveDuty == null) {
          _showCalendarMessage(
            'No roster duty is available for this manual change.',
          );
          return;
        }

        _showManualChangeDialog(date: date, originalDuty: effectiveDuty);
        return;

      case _CalendarDayAction.shiftSwap:
        if (effectiveDuty == null || !effectiveDuty.dutyType.countsAsWorking) {
          _showCalendarMessage(
            'A shift swap can only be requested for a working duty.',
          );
          return;
        }

        _showShiftSwapDialog(
          date: date,
          originalDuty: effectiveDuty,
          initialOption: 'Mutual swap',
        );
        return;

      case _CalendarDayAction.moveRestDays:
        if (effectiveDuty != null) await _confirmMoveRestDayHere(date: date, originalDuty: effectiveDuty);
        return;
      case _CalendarDayAction.moveRestDayHere:
        if (effectiveDuty == null || !effectiveDuty.dutyType.countsAsWorking) {
          _showCalendarMessage(
            'A Rest Day can only be moved onto a working duty.',
          );
          return;
        }

        _confirmMoveRestDayHere(date: date, originalDuty: effectiveDuty);
        return;

      case _CalendarDayAction.requestAnnualLeave:
        if (effectiveDuty == null) {
          _showCalendarMessage(
            'No roster duty is available for this annual leave request.',
          );
          return;
        }

        await _chooseAnnualLeaveRequestScope(date: date, duty: effectiveDuty);
        return;

      case _CalendarDayAction.manageAnnualLeave:
        final AnnualLeaveRequest? leaveRequest =
            _leaveRequestsByDate[_dateKey(date)];

        if (leaveRequest == null ||
            leaveRequest.status == AnnualLeaveRequestStatus.cancelled) {
          _showCalendarMessage(
            'There is no active annual leave request for this date.',
          );
          return;
        }

        _showManageAnnualLeaveDialog(date: date, request: leaveRequest);
        return;

      case _CalendarDayAction.allocateShift:
        if (effectiveDuty == null ||
            effectiveDuty.dutyType != DutyType.restDay) {
          _showCalendarMessage(
            'A Rest Day Worked shift can only be allocated on a Rest Day.',
          );
          return;
        }

        _showAllocateShiftDialog(date: date, originalDuty: effectiveDuty);
        return;

      case _CalendarDayAction.makeSundayAvailable:
        if (effectiveDuty == null ||
            effectiveDuty.date.weekday != DateTime.sunday ||
            effectiveDuty.dutyType != DutyType.unavailable) {
          _showCalendarMessage(
            'Sunday availability can only be changed for an unavailable Sunday.',
          );
          return;
        }

        _makeSundayAvailable(date: date);
        return;
    }
  }

  Future<void> _showManualChangeDialog({
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
      text: originalDuty.remarks ?? '',
    );

    DutyType selectedDutyType = originalDuty.dutyType;
    bool isSaving = false;
    String? errorMessage;

    String dutyTypeLabel(DutyType type) {
      switch (type) {
        case DutyType.working:
          return 'Working';
        case DutyType.training:
          return 'Training';
        case DutyType.medical:
          return 'Medical';
        case DutyType.restDay:
          return 'Rest Day';
        case DutyType.sick:
          return 'Sick';
        case DutyType.publicHoliday:
          return 'Public Holiday';
        case DutyType.unavailable:
          return 'Unavailable';
        case DutyType.annualLeave:
          return 'Annual Leave';
        case DutyType.unknown:
          return 'Unknown';
      }
    }

    final List<DutyType> selectableTypes = <DutyType>[
      if (originalDuty.dutyType == DutyType.unknown) DutyType.unknown,
      if (originalDuty.dutyType == DutyType.annualLeave) DutyType.annualLeave,
      DutyType.working,
      DutyType.training,
      DutyType.medical,
      DutyType.restDay,
      DutyType.sick,
      DutyType.publicHoliday,
      DutyType.unavailable,
    ];

    try {
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
                  final bool workingType = selectedDutyType.countsAsWorking;

                  Future<void> saveManualChange() async {
                    String bookOn = '';
                    String bookOff = '';

                    if (workingType) {
                      bookOn = _normaliseTimeInput(bookOnController.text);
                      bookOff = _normaliseTimeInput(bookOffController.text);

                      if (!_isValidTime(bookOn) || !_isValidTime(bookOff)) {
                        setSheetState(() {
                          errorMessage =
                              'Enter valid 24-hour times, for example 0800 or 08:00.';
                        });
                        return;
                      }
                    }

                    setSheetState(() {
                      isSaving = true;
                      errorMessage = null;
                    });

                    try {
                      await _manualDutyService.saveManualChange(
                        date: date,
                        dutyType: selectedDutyType,
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

                      widget.onRosterChanged();

                      _showCalendarMessage(
                        'Manual change saved for ${_fullDate(date)}.',
                      );
                    } catch (error) {
                      if (!sheetContext.mounted) {
                        return;
                      }

                      setSheetState(() {
                        isSaving = false;
                        errorMessage = error is ManualDutyException
                            ? error.message
                            : 'Roster Buddy could not save the manual change.';
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
                            const Text(
                              'Manual change',
                              style: TextStyle(
                                color: navy,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _fullDate(date),
                              style: const TextStyle(color: textGrey),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Duty type',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: textGrey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: selectableTypes
                                  .map((DutyType type) {
                                    final bool selected =
                                        selectedDutyType == type;

                                    return ChoiceChip(
                                      label: Text(dutyTypeLabel(type)),
                                      selected: selected,
                                      onSelected: isSaving
                                          ? null
                                          : (_) {
                                              setSheetState(() {
                                                selectedDutyType = type;
                                                errorMessage = null;
                                              });
                                            },
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                            if (workingType) ...<Widget>[
                              const SizedBox(height: 18),
                              TextField(
                                controller: turnController,
                                enabled: !isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Turn number',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: bookOnController,
                                enabled: !isSaving,
                                keyboardType: TextInputType.datetime,
                                decoration: const InputDecoration(
                                  labelText: 'Book on',
                                  hintText: '08:00',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: bookOffController,
                                enabled: !isSaving,
                                keyboardType: TextInputType.datetime,
                                decoration: const InputDecoration(
                                  labelText: 'Book off',
                                  hintText: '16:00',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextField(
                              controller: remarksController,
                              enabled: !isSaving,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Notes',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (errorMessage != null) ...<Widget>[
                              const SizedBox(height: 12),
                              Text(
                                errorMessage!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: isSaving ? null : saveManualChange,
                                child: Text(
                                  isSaving ? 'Saving...' : 'Save manual change',
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
    } finally {
      turnController.dispose();
      bookOnController.dispose();
      bookOffController.dispose();
      remarksController.dispose();
    }
  }

  Future<void> _showShiftSwapDialog({
    required DateTime date,
    required Duty originalDuty,
    String? initialOption,
  }) async {
    final TextEditingController driverNameController = TextEditingController();
    final TextEditingController payrollController = TextEditingController();
    final TextEditingController requestedDateController = TextEditingController(
      text:
          '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}',
    );
    final TextEditingController requestedTurnController =
        TextEditingController();
    final TextEditingController notesController = TextEditingController();

    String? selectedOption = initialOption;
    bool confirmedWithRosters = false;

    try {
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder:
                (
                  BuildContext dialogContext,
                  void Function(void Function()) setDialogState,
                ) {
                  return DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.label.resolveFrom(dialogContext),
                      decoration: TextDecoration.none,
                    ),
                    child: CupertinoPopupSurface(
                      child: SafeArea(
                        top: false,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  const Expanded(
                                    child: Text(
                                      'Shift Change',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: CupertinoColors.label,
                                      ),
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      Navigator.of(dialogContext).pop();
                                    },
                                    child: const Icon(
                                      CupertinoIcons.xmark_circle_fill,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 6),

                              Text(
                                'Selected date: ${_fullDate(date)}',
                                style: TextStyle(
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(dialogContext),
                                  fontSize: 13,
                                ),
                              ),

                              const SizedBox(height: 20),

                              Text(
                                'What do you want to do?',
                                style: CupertinoTheme.of(dialogContext)
                                    .textTheme
                                    .textStyle
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),

                              const SizedBox(height: 10),

                              _shiftChangeOption(
                                context: dialogContext,
                                title: 'Mutual swap',
                                subtitle: 'Swap this duty with another driver.',
                                icon: CupertinoIcons.person_2_fill,
                                selected: selectedOption == 'Mutual swap',
                                onTap: () {
                                  setDialogState(() {
                                    selectedOption = 'Mutual swap';
                                  });
                                },
                              ),

                              const SizedBox(height: 8),

                              _shiftChangeOption(
                                context: dialogContext,
                                title: 'Change to Rest Day',
                                subtitle:
                                    'Replace this working duty with a Rest Day.',
                                icon: CupertinoIcons.moon_fill,
                                selected:
                                    selectedOption == 'Change to Rest Day',
                                onTap: () {
                                  setDialogState(() {
                                    selectedOption = 'Change to Rest Day';
                                  });
                                },
                              ),

                              if (selectedOption == 'Mutual swap') ...<Widget>[
                                const SizedBox(height: 22),

                                Text(
                                  'Mutual swap',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.label,
                                  ),
                                ),

                                const SizedBox(height: 6),

                                Text(
                                  'Enter the details of the other driver and '
                                  'the duty you are proposing to swap.',
                                  style: CupertinoTheme.of(dialogContext)
                                      .textTheme
                                      .textStyle
                                      .copyWith(
                                        color: CupertinoColors.secondaryLabel
                                            .resolveFrom(dialogContext),
                                        fontSize: 13,
                                      ),
                                ),

                                const SizedBox(height: 12),

                                _shiftChangeTextField(
                                  controller: driverNameController,
                                  placeholder: 'Other driver name',
                                  keyboardType: TextInputType.name,
                                ),

                                const SizedBox(height: 10),

                                _shiftChangeTextField(
                                  controller: payrollController,
                                  placeholder: 'Other driver payroll number',
                                  keyboardType: TextInputType.number,
                                ),

                                const SizedBox(height: 10),

                                _shiftChangeTextField(
                                  controller: requestedDateController,
                                  placeholder:
                                      'Proposed duty date (DD/MM/YYYY)',
                                  keyboardType: TextInputType.datetime,
                                ),

                                const SizedBox(height: 10),

                                _shiftChangeTextField(
                                  controller: requestedTurnController,
                                  placeholder: "Other driver's turn number",
                                  keyboardType: TextInputType.text,
                                ),

                                const SizedBox(height: 12),

                                Container(
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemGrey6
                                        .resolveFrom(dialogContext),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              const Text(
                                                'Confirmed with DTCM / Rosters',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: CupertinoColors.label,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                confirmedWithRosters
                                                    ? 'Confirmed — change can be applied.'
                                                    : 'Not confirmed — request only.',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: CupertinoColors
                                                      .secondaryLabel
                                                      .resolveFrom(
                                                        dialogContext,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      CupertinoSwitch(
                                        value: confirmedWithRosters,
                                        onChanged: (bool value) {
                                          setDialogState(() {
                                            confirmedWithRosters = value;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 10),

                                _shiftChangeTextField(
                                  controller: notesController,
                                  placeholder: 'Notes (optional)',
                                  keyboardType: TextInputType.multiline,
                                  maxLines: 3,
                                ),
                              ],

                              if (selectedOption ==
                                  'Change to Rest Day') ...<Widget>[
                                const SizedBox(height: 18),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemGrey6
                                        .resolveFrom(dialogContext),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'This will make ${_fullDate(date)} a Rest Day '
                                    'and preserve the original rostered duty in '
                                    'your duty history.',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: CupertinoColors.label,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 20),

                              SizedBox(
                                width: double.infinity,
                                child: CupertinoButton.filled(
                                  onPressed: selectedOption == null
                                      ? null
                                      : () async {
                                          if (selectedOption == 'Change to Rest Day') {
                                            Navigator.of(dialogContext).pop();
                                            await _confirmMoveRestDayHere(date: date, originalDuty: originalDuty);
                                            return;
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

                                                String driverName = '';
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

                                                  driverName =
                                                      (profile?['display_name'] ??
                                                              metadata['full_name'] ??
                                                              '')
                                                          .toString()
                                                          .trim();

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
                                                    '\n\nRegards'
                                                    '${driverName.isEmpty ? '' : '\n$driverName'}'
                                                    '${depot.isEmpty ? '' : '\n$depot'}'
                                                    '${payrollNumber.isEmpty ? '' : '\nPayroll Number: $payrollNumber'}';

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
            style: const TextStyle(color: textGrey, height: 1.35),
          ),
          if (request.notes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              request.notes!.trim(),
              style: const TextStyle(
                color: navy,
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

  bool _isPostBlockUnavailableSunday(Duty? duty) {
    if (duty == null) {
      return false;
    }

    return duty.date.weekday == DateTime.sunday &&
        duty.dutyType == DutyType.unavailable &&
        duty.rawText == 'post_block_sunday';
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

  Widget _buildPostBlockSundayAction({
    required BuildContext sheetContext,
    required DateTime date,
    required Duty duty,
  }) {
    if (!_isPostBlockUnavailableSunday(duty)) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<bool>(
      future: _sundayAvailabilityService.isPermanentlyUnavailableOnSundays(),
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              label: const Text('Checking Sunday availability…'),
            ),
          );
        }

        // Permanently unavailable drivers do not need the post-block prompt.
        if (snapshot.data == true) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: restYellow.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: restYellow.withValues(alpha: 0.8)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: navy, size: 21),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This was a booked Sunday immediately after your '
                      'block leave week, so you are currently marked '
                      'unavailable. Make yourself available if you want '
                      'to work your booked Sunday duty.',
                      style: TextStyle(
                        color: navy,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();

                Future<void>.delayed(const Duration(milliseconds: 150), () {
                  if (mounted) {
                    _makeSundayAvailable(date: date);
                  }
                });
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Make myself available'),
              style: FilledButton.styleFrom(backgroundColor: workingGreen),
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
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
                          const Text(
                            'Manage annual leave',
                            style: TextStyle(
                              color: navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fullDate(date),
                            style: const TextStyle(color: textGrey),
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
                            style: const TextStyle(
                              color: navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fullDate(date),
                            style: const TextStyle(color: textGrey),
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
                      const Text(
                        'Allocate shift – RDW',
                        style: TextStyle(
                          color: navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _fullDate(date),
                        style: const TextStyle(color: textGrey),
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
                      const Text(
                        'Selecting a Job Card fills its booked times automatically. '
                        'Manual or cross-depot duties can still be entered.',
                        style: TextStyle(color: textGrey, height: 1.35),
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

  String _timeDescription(Duty duty) {
    final String? bookOn = duty.bookOn?.trim();
    final String? bookOff = duty.bookOff?.trim();

    if (bookOn?.isNotEmpty == true && bookOff?.isNotEmpty == true) {
      return 'Book on $bookOn  •  Book off $bookOff';
    }

    if (bookOn?.isNotEmpty == true) {
      return 'Book on $bookOn';
    }

    if (bookOff?.isNotEmpty == true) {
      return 'Book off $bookOff';
    }

    return 'Duty times not available';
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
          style: const TextStyle(
            color: Color(0xFF102A43),
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

