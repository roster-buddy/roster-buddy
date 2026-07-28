import 'package:flutter/material.dart';

void main() {
  runApp(const RosterBuddyApp());
}

class RosterBuddyApp extends StatelessWidget {
  const RosterBuddyApp({super.key});

  static const Color navy = Color(0xFF102A43);
  static const Color railwayBlue = Color(0xFF1769AA);
  static const Color background = Color(0xFFF4F7FA);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roster Buddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: railwayBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: background,
        fontFamily: 'Arial',
      ),
      home: const WelcomeScreen(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.topRight,
                child: CloudStatusIndicator(),
              ),
              const Spacer(),
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: RosterBuddyApp.navy,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 24,
                      offset: Offset(0, 10),
                      color: Color(0x33000000),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.train_rounded,
                  size: 58,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Roster Buddy',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: RosterBuddyApp.navy,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your railway roster, all in one place.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.4,
                  color: Color(0xFF52667A),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: RosterBuddyApp.railwayBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RosterBuddyApp.navy,
                    side: const BorderSide(
                      color: Color(0xFFBCC8D3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Version 0.1.0',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF7B8C9D),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CloudStatusIndicator extends StatelessWidget {
  const CloudStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cloud status: connected',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFD9E2EC),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 5,
              backgroundColor: Color(0xFF21A366),
            ),
            SizedBox(width: 7),
            Text(
              'Connected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: RosterBuddyApp.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}