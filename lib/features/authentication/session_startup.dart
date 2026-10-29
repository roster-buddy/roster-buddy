import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_screen.dart';
import 'initial_setup_screen.dart';
import 'welcome_screen.dart';

/// Restores the saved session before deciding which screen to display.
class SessionStartup extends StatefulWidget {
  const SessionStartup({super.key, this.loadDestination});

  final Future<Widget> Function()? loadDestination;

  @override
  State<SessionStartup> createState() => _SessionStartupState();
}

class _SessionStartupState extends State<SessionStartup> {
  late Future<Widget> _destination;

  @override
  void initState() {
    super.initState();
    _destination = _load();
  }

  Future<Widget> _load() async {
    if (widget.loadDestination != null) {
      return widget.loadDestination!();
    }
    final client = Supabase.instance.client;
    var session = client.auth.currentSession;
    if (session == null) return const WelcomeScreen();
    if (session.isExpired) {
      session = (await client.auth.refreshSession()).session;
    }
    if (session == null) return const WelcomeScreen();

    final profile = await client.from('driver_profiles')
        .select('setup_completed').eq('user_id', session.user.id).maybeSingle();
    return profile?['setup_completed'] == true
        ? const HomeScreen()
        : const InitialSetupScreen();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _destination,
      builder: (context, snapshot) {
        if (snapshot.hasData) return snapshot.data!;
        if (snapshot.hasError) {
          // A network failure must not discard the persisted session.
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not restore your sign-in. Check your connection and retry.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() { _destination = _load(); }),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
                    ),
                    child: const Text('Go to sign in'),
                  ),
                ],
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
