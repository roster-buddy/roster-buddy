import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      const _PlaceholderPage(
        icon: Icons.calendar_month_outlined,
        title: 'Roster',
        description: 'Your Sunday-to-Saturday roster will appear here.',
      ),
      const _UploadPage(),
      const _PlaceholderPage(
        icon: Icons.description_outlined,
        title: 'Documents',
        description: 'Your uploaded roster documents will appear here.',
      ),
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
        onDestinationSelected: (index) {
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

class _UploadPage extends StatelessWidget {
  const _UploadPage();

  static const Color navy = Color(0xFF102A43);
  @override
  Widget build(BuildContext context) {
    const documentTypes = [
      'Base Roster',
      '10-Day Amendment',
      '7-Day Amendment',
      '48-Hour Amendment',
      'Job Card',
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Smart Scan',
              style: TextStyle(
                color: navy,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose the type of railway document you want to upload.',
              style: TextStyle(color: Color(0xFF52667A), height: 1.4),
            ),
            const SizedBox(height: 22),
            for (final type in documentTypes) ...[
              _UploadDocumentTile(
                title: type,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$type upload will be added next.')),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _UploadDocumentTile extends StatelessWidget {
  const _UploadDocumentTile({required this.title, required this.onTap});

  final String title;
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: railwayBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
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

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: railwayBlue),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: navy,
                fontSize: 28,
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
                height: 1.4,
              ),
            ),
          ],
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
