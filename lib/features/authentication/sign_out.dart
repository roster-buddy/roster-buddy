import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../notifications/web_push_bridge.dart';
import 'package:flutter/material.dart';
import 'sign_in_screen.dart';

/// The startup route may already contain a restored Home screen. Popping to
/// that route would show signed-in content after the session was cleared.
Future<void> signOutAndResetNavigation(
  BuildContext context, {
  required Future<void> Function() signOut,
}) async {
  if (kIsWeb) {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      await WebPushBridge.disable(session?.accessToken ?? '', session?.user.id ?? '');
    } catch (_) { /* Sign-out must still complete if the device is offline. */ }
  }
  await signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil<void>(
    MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
    (_) => false,
  );
}
