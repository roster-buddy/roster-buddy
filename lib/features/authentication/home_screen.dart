import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);

  static const Color workingGreen = Color(0xFF2E7D32);
  static const Color restYellow = Color(0xFFF9C74F);
  static const Color leaveRed = Color(0xFFD64545);
  static const Color unresolvedGrey = Color(0xFF7B8794);

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();

    if (!context.mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final email =
        Supabase.instance.client.auth.currentUser?.email ?? 'Roster Buddy user';

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        foregroundColor: navy,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.train, color: railwayBlue),
            SizedBox(width: 10),
            Text(
              'Roster Buddy',
              style: TextStyle(color: navy, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(color: Color(0xFF52667A))),
                const SizedBox(height: 22),
                _DashboardCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            color: railwayBlue,
                          ),
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
                      const SizedBox(height: 6),
                      const Text(
                        'Sunday to Saturday',
                        style: TextStyle(color: Color(0xFF52667A)),
                      ),
                      const SizedBox(height: 18),
                      const Row(
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
                _DashboardCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.document_scanner_outlined,
                            color: railwayBlue,
                          ),
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
                      const SizedBox(height: 8),
                      const Text(
                        'Scan a roster amendment or job card.',
                        style: TextStyle(color: Color(0xFF52667A)),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: railwayBlue,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text(
                            'Scan document',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(
                      child: _SummaryTile(
                        icon: Icons.work_outline,
                        value: '3',
                        label: 'Working',
                        colour: workingGreen,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _SummaryTile(
                        icon: Icons.bedtime_outlined,
                        value: '2',
                        label: 'Rest days',
                        colour: restYellow,
                        darkText: true,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _SummaryTile(
                        icon: Icons.beach_access_outlined,
                        value: '1',
                        label: 'Annual leave',
                        colour: leaveRed,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
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

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.colour,
    this.darkText = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color colour;
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final textColour = darkText ? const Color(0xFF2F3E46) : Colors.white;

    return Container(
      height: 120,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColour),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              color: textColour,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: textColour, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
