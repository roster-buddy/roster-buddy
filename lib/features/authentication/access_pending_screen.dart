import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_access_service.dart';
import 'home_screen.dart';
import 'initial_setup_screen.dart';
import 'sign_out.dart';

class AccessPendingScreen extends StatefulWidget {
  const AccessPendingScreen({required this.status, super.key});
  final AppAccessStatus status;

  @override
  State<AccessPendingScreen> createState() => _AccessPendingScreenState();
}

class _AccessPendingScreenState extends State<AccessPendingScreen> {
  bool _checking = false;

  Future<void> _checkAgain() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final status = await const AppAccessService().currentStatus();
      if (!mounted) return;
      if (status == AppAccessStatus.approved) {
        final user = Supabase.instance.client.auth.currentUser!;
        final profile = await Supabase.instance.client
            .from('driver_profiles')
            .select('setup_completed')
            .eq('user_id', user.id)
            .maybeSingle();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(
            builder: (_) => profile?['setup_completed'] == true
                ? const HomeScreen()
                : const InitialSetupScreen(),
          ),
          (_) => false,
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == AppAccessStatus.declined
                ? 'Access has not been approved.'
                : 'Your account is still waiting for approval.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _signOut() => signOutAndResetNavigation(
    context,
    signOut: () => Supabase.instance.client.auth.signOut(),
  );

  @override
  Widget build(BuildContext context) {
    final declined = widget.status == AppAccessStatus.declined;
    return Scaffold(
      appBar: AppBar(title: const Text('Roster Buddy')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  declined ? Icons.block_outlined : Icons.hourglass_top,
                  size: 64,
                  color: declined
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  declined ? 'Access not approved' : 'Waiting for approval',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  declined
                      ? 'The Roster Buddy administrator has declined this access request.'
                      : 'Your email is confirmed. The Roster Buddy administrator must approve your account before you can continue.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _checking ? null : _checkAgain,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Check again'),
                ),
                TextButton(onPressed: _signOut, child: const Text('Sign out')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
