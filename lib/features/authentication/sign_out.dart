import 'package:flutter/material.dart';
import 'sign_in_screen.dart';

/// The startup route may already contain a restored Home screen. Popping to
/// that route would show signed-in content after the session was cleared.
Future<void> signOutAndResetNavigation(
  BuildContext context, {
  required Future<void> Function() signOut,
}) async {
  await signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil<void>(
    MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
    (_) => false,
  );
}
