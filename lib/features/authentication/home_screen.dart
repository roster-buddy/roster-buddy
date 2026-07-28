import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);

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
        backgroundColor: background,
        foregroundColor: navy,
        elevation: 0,
        title: const Text(
          'Roster Buddy',
          style: TextStyle(color: navy, fontWeight: FontWeight.w800),
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
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: navy,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.train,
                      size: 46,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'You’re signed in',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF52667A),
                    ),
                  ),
                  const SizedBox(height: 34),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFD9E2EC)),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 42,
                          color: railwayBlue,
                        ),
                        SizedBox(height: 14),
                        Text(
                          'Your roster dashboard will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: navy,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Your account and sign-in are working.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            height: 1.4,
                            color: Color(0xFF52667A),
                          ),
                        ),
                      ],
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
