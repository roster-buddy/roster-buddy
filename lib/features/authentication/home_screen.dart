import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

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

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final email =
        Supabase.instance.client.auth.currentUser?.email ?? 'Roster Buddy user';

    final pages = <Widget>[
      _HomePage(email: email),
      const _RosterPage(),
      const _UploadPage(),
      const _DocumentsPage(),
      _ProfilePage(email: email, onSignOut: _signOut),
    ];

    const titles = ['Roster Buddy', 'Roster', 'Upload', 'Documents', 'Profile'];

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
              style: const TextStyle(color: navy, fontWeight: FontWeight.w800),
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
            setState(() {
              _selectedIndex = 2;
            });

            await const _UploadPage()._pickDocument(context);
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
            label: 'Roster',
          ),
          NavigationDestination(
            icon: Icon(Icons.upload_file_outlined),
            selectedIcon: Icon(Icons.upload_file),
            label: 'Upload',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'Documents',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.email});

  final String email;

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color workingGreen = Color(0xFF2E7D32);
  static const Color restYellow = Color(0xFFF9C74F);
  static const Color leaveRed = Color(0xFFD64545);
  static const Color unresolvedGrey = Color(0xFF7B8794);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Welcome back',
              style: TextStyle(
                color: navy,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(email, style: const TextStyle(color: Color(0xFF52667A))),
            const SizedBox(height: 22),
            const _DashboardCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_month_outlined, color: railwayBlue),
                      SizedBox(width: 10),
                      Text(
                        'This week',
                        style: TextStyle(
                          color: navy,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Sunday to Saturday',
                    style: TextStyle(color: Color(0xFF52667A)),
                  ),
                  SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _DayTile(
                          day: 'Sun',
                          status: 'Rest',
                          colour: restYellow,
                          darkText: true,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: _DayTile(
                          day: 'Mon',
                          status: 'Duty',
                          colour: workingGreen,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: _DayTile(
                          day: 'Tue',
                          status: 'Duty',
                          colour: workingGreen,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: _DayTile(
                          day: 'Wed',
                          status: 'Duty',
                          colour: workingGreen,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: _DayTile(
                          day: 'Thu',
                          status: 'Unknown',
                          colour: unresolvedGrey,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: _DayTile(
                          day: 'Fri',
                          status: 'Leave',
                          colour: leaveRed,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: _DayTile(
                          day: 'Sat',
                          status: 'Rest',
                          colour: restYellow,
                          darkText: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _DashboardCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.document_scanner_outlined, color: railwayBlue),
                      SizedBox(width: 10),
                      Text(
                        'Smart Scan',
                        style: TextStyle(
                          color: navy,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Use the Upload tab to scan a roster document or job card.',
                    style: TextStyle(color: Color(0xFF52667A)),
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

class _RosterPage extends StatefulWidget {
  const _RosterPage();

  @override
  State<_RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<_RosterPage> {
  static const Color navy = Color(0xFF102A43);
  static const Color workingGreen = Color(0xFF2E7D32);
  static const Color restYellow = Color(0xFFF9C74F);
  static const Color leaveRed = Color(0xFFD64545);
  static const Color unresolvedGrey = Color(0xFF7B8794);

  int _weekOffset = 0;

  String get _weekLabel {
    if (_weekOffset == 0) return 'This week';
    if (_weekOffset == -1) return 'Last week';
    if (_weekOffset == 1) return 'Next week';

    return _weekOffset < 0
        ? '${_weekOffset.abs()} weeks ago'
        : 'In $_weekOffset weeks';
  }

  @override
  Widget build(BuildContext context) {
    const duties = [
      _RosterDuty(
        day: 'Sunday',
        date: '2 Aug',
        status: 'Rest day',
        details: 'No booked duty',
        colour: restYellow,
        darkText: true,
        icon: Icons.bedtime_outlined,
      ),
      _RosterDuty(
        day: 'Monday',
        date: '3 Aug',
        status: 'Working',
        details: 'Early duty · Times to be confirmed',
        colour: workingGreen,
        icon: Icons.work_outline,
      ),
      _RosterDuty(
        day: 'Tuesday',
        date: '4 Aug',
        status: 'Working',
        details: 'Duty details awaiting roster data',
        colour: workingGreen,
        icon: Icons.work_outline,
      ),
      _RosterDuty(
        day: 'Wednesday',
        date: '5 Aug',
        status: 'Training',
        details: 'Training duty',
        colour: workingGreen,
        icon: Icons.school_outlined,
      ),
      _RosterDuty(
        day: 'Thursday',
        date: '6 Aug',
        status: 'Unresolved',
        details: 'Further document information required',
        colour: unresolvedGrey,
        icon: Icons.help_outline,
      ),
      _RosterDuty(
        day: 'Friday',
        date: '7 Aug',
        status: 'Annual leave',
        details: 'Booked annual leave',
        colour: leaveRed,
        icon: Icons.beach_access_outlined,
      ),
      _RosterDuty(
        day: 'Saturday',
        date: '8 Aug',
        status: 'Rest day',
        details: 'No booked duty',
        colour: restYellow,
        darkText: true,
        icon: Icons.bedtime_outlined,
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous week',
                  onPressed: () {
                    setState(() {
                      _weekOffset--;
                    });
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _weekLabel,
                        style: const TextStyle(
                          color: navy,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Sunday to Saturday',
                        style: TextStyle(color: Color(0xFF52667A)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Next week',
                  onPressed: () {
                    setState(() {
                      _weekOffset++;
                    });
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: const [
                _RosterLegend(
                  label: 'Working / Training',
                  colour: workingGreen,
                ),
                _RosterLegend(
                  label: 'Rest day',
                  colour: restYellow,
                  darkText: true,
                ),
                _RosterLegend(label: 'Annual leave', colour: leaveRed),
                _RosterLegend(label: 'Unresolved', colour: unresolvedGrey),
              ],
            ),
            const SizedBox(height: 20),
            for (final duty in duties) ...[
              _RosterDutyCard(duty: duty),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _RosterDuty {
  const _RosterDuty({
    required this.day,
    required this.date,
    required this.status,
    required this.details,
    required this.colour,
    required this.icon,
    this.darkText = false,
  });

  final String day;
  final String date;
  final String status;
  final String details;
  final Color colour;
  final IconData icon;
  final bool darkText;
}

class _RosterDutyCard extends StatelessWidget {
  const _RosterDutyCard({required this.duty});

  final _RosterDuty duty;

  @override
  Widget build(BuildContext context) {
    final textColour = duty.darkText ? const Color(0xFF2F3E46) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: duty.colour,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: textColour.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(duty.icon, color: textColour),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        duty.day,
                        style: TextStyle(
                          color: textColour,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      duty.date,
                      style: TextStyle(
                        color: textColour,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  duty.status,
                  style: TextStyle(
                    color: textColour,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  duty.details,
                  style: TextStyle(
                    color: textColour.withValues(alpha: 0.9),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterLegend extends StatelessWidget {
  const _RosterLegend({
    required this.label,
    required this.colour,
    this.darkText = false,
  });

  final String label;
  final Color colour;
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final textColour = darkText ? const Color(0xFF2F3E46) : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColour,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UploadPage extends StatelessWidget {
  const _UploadPage();

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);

  Future<void> _pickDocument(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || !context.mounted) return;

    final file = result.files.single;
    final bytes = file.bytes;
    final user = Supabase.instance.client.auth.currentUser;

    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The selected file could not be read.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in before uploading a document.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final safeFileName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

    final storagePath =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Uploading document…'),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final uploadedPath = await Supabase.instance.client.storage
          .from('roster-documents')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      final sizeInKb = (file.size / 1024).ceil();

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_done_outlined, color: Color(0xFF2E7D32)),
                      SizedBox(width: 10),
                      Text(
                        'Upload complete',
                        style: TextStyle(
                          color: navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1F8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          size: 38,
                          color: railwayBlue,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                style: const TextStyle(
                                  color: navy,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$sizeInKb KB',
                                style: const TextStyle(
                                  color: Color(0xFF52667A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'The document is stored securely. Smart Scan will now '
                    'identify it as one of these document types:',
                    style: TextStyle(color: Color(0xFF52667A), height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DetectionLabel(label: 'Base Roster'),
                      _DetectionLabel(label: '10-Day Amendment'),
                      _DetectionLabel(label: '7-Day Amendment'),
                      _DetectionLabel(label: '48-Hour Amendment'),
                      _DetectionLabel(label: 'Annual Leave Roster'),
                      _DetectionLabel(label: 'Job Card'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Storage reference: $uploadedPath',
                    style: const TextStyle(
                      color: Color(0xFF7B8794),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Continue to Smart Scan'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } on StorageException catch (error) {
      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: ${error.message}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to upload the document. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDetectionPreview(BuildContext context, String source) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Smart Scan',
                  style: TextStyle(
                    color: navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$source selection will be connected next.',
                  style: const TextStyle(color: Color(0xFF52667A), height: 1.4),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Upload document',
              style: TextStyle(
                color: navy,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose where your document is coming from. Smart Scan will '
              'identify the document type automatically.',
              style: TextStyle(color: Color(0xFF52667A), height: 1.4),
            ),
            const SizedBox(height: 22),
            _UploadSourceTile(
              icon: Icons.camera_alt_outlined,
              title: 'Camera',
              subtitle: 'Take a new photo of the document',
              onTap: () => _showDetectionPreview(context, 'Camera'),
            ),
            const SizedBox(height: 12),
            _UploadSourceTile(
              icon: Icons.photo_library_outlined,
              title: 'Photo Library',
              subtitle: 'Choose an existing photo or image',
              onTap: () => _showDetectionPreview(context, 'Photo Library'),
            ),
            const SizedBox(height: 12),
            _UploadSourceTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF or File',
              subtitle: 'Choose a PDF or supported document file',
              onTap: () => _pickDocument(context),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F1F8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_outlined, color: railwayBlue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Smart Scan detects Base Rosters, 10-Day, 7-Day and '
                      '48-Hour amendments, Annual Leave Rosters and Job Cards. '
                      'You can label the document manually if detection is '
                      'uncertain.',
                      style: TextStyle(
                        color: navy,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

class _UploadSourceTile extends StatelessWidget {
  const _UploadSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD9E2EC)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1F8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: railwayBlue),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF52667A)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF7B8794)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectionLabel extends StatelessWidget {
  const _DetectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1F8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1769AA),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DocumentsPage extends StatelessWidget {
  const _DocumentsPage();

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);

  @override
  Widget build(BuildContext context) {
    const documents = [
      _RosterDocument(
        title: 'Base Roster',
        subtitle: 'Current base roster',
        status: 'Active',
        uploaded: 'Uploaded today',
        priority: 1,
      ),
      _RosterDocument(
        title: '10-Day Amendment',
        subtitle: 'Amendment to base roster',
        status: 'Applied',
        uploaded: 'Uploaded today',
        priority: 2,
      ),
      _RosterDocument(
        title: '7-Day Amendment',
        subtitle: 'Overrides earlier roster information',
        status: 'Applied',
        uploaded: 'Uploaded today',
        priority: 3,
      ),
      _RosterDocument(
        title: '48-Hour Amendment',
        subtitle: 'Highest-priority roster amendment',
        status: 'Applied',
        uploaded: 'Uploaded today',
        priority: 4,
      ),
      _RosterDocument(
        title: 'Job Card',
        subtitle: 'Reference information for a specific duty',
        status: 'Reference only',
        uploaded: 'Uploaded today',
        priority: 0,
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Document history',
              style: TextStyle(
                color: navy,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Roster documents are applied in priority order.',
              style: TextStyle(color: Color(0xFF52667A), height: 1.4),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F1F8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: railwayBlue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Priority: Base Roster → 10-Day → 7-Day → 48-Hour. '
                      'Job Cards provide duty-specific information.',
                      style: TextStyle(
                        color: navy,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            for (final document in documents) ...[
              _DocumentCard(document: document),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _RosterDocument {
  const _RosterDocument({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.uploaded,
    required this.priority,
  });

  final String title;
  final String subtitle;
  final String status;
  final String uploaded;
  final int priority;
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document});

  final _RosterDocument document;

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${document.title} details will be added next.'),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD9E2EC)),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1F8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: railwayBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            document.title,
                            style: const TextStyle(
                              color: navy,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F1F8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            document.status,
                            style: const TextStyle(
                              color: railwayBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      document.subtitle,
                      style: const TextStyle(color: Color(0xFF52667A)),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Text(
                          document.uploaded,
                          style: const TextStyle(
                            color: Color(0xFF7B8794),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          document.priority == 0
                              ? 'Does not override roster'
                              : 'Priority ${document.priority}',
                          style: const TextStyle(
                            color: Color(0xFF7B8794),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Color(0xFF7B8794)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.email, required this.onSignOut});

  final String email;
  final VoidCallback onSignOut;

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _DashboardCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 38,
                  backgroundColor: railwayBlue,
                  child: Icon(Icons.person, size: 42, color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E2EC)),
      ),
      child: child,
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.status,
    required this.colour,
    this.darkText = false,
  });

  final String day;
  final String status;
  final Color colour;
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final textColour = darkText ? const Color(0xFF2F3E46) : Colors.white;

    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
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
