import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../supabase_config.dart';
import 'password_reset_link_stub.dart'
    if (dart.library.js_interop) 'password_reset_link_web.dart';
import 'sign_in_screen.dart';

const _resetRedirect = 'https://roster-buddy.github.io/roster-buddy/';

Uri? takePasswordRecoveryLink() {
  if (!kIsWeb) return null;
  final uri = Uri.base;
  final fragment = Uri.tryParse('?${uri.fragment}')?.queryParameters;
  if (fragment?['type'] != 'recovery' &&
      fragment?['error_code'] != 'otp_expired') {
    return null;
  }
  clearPasswordResetFragment(uri);
  return uri;
}

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key, this.email = '', this.recoveryLink});

  final String email;
  final Uri? recoveryLink;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  // Email apps can open links in a different browser from the installed app.
  // Keep the recovery session in memory and separate from the app session.
  final _client = SupabaseClient(
    SupabaseConfig.url,
    SupabaseConfig.publishableKey,
    authOptions: const AuthClientOptions(
      authFlowType: AuthFlowType.implicit,
      autoRefreshToken: false,
    ),
  );

  bool _busy = false;
  bool _checkingLink = false;
  Session? _recoverySession;
  bool _emailSent = false;
  bool _passwordChanged = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.email);
    final link = widget.recoveryLink;
    if (link != null) {
      _checkingLink = true;
      _openLink(link);
    }
  }

  Future<void> _openLink(Uri link) async {
    try {
      final response = await _client.auth.getSessionFromUrl(
        link,
        storeSession: false,
      );
      if (response.redirectType != 'recovery' || response.session.isExpired) {
        throw const AuthException('Invalid password recovery link');
      }
      if (mounted) setState(() => _recoverySession = response.session);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'This link is invalid or has expired. Request a new reset email below.';
        });
      }
    } finally {
      if (mounted) setState(() => _checkingLink = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final session = _recoverySession;
      if (session != null) {
        await _updatePassword(session, _password.text);
        if (mounted) {
          _password.clear();
          _confirmation.clear();
          setState(() {
            _recoverySession = null;
            _passwordChanged = true;
          });
        }
      } else {
        await _client.auth.resetPasswordForEmail(
          _email.text.trim(),
          redirectTo: _resetRedirect,
        );
        if (mounted) setState(() => _emailSent = true);
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        if (_recoverySession?.isExpired == true ||
            (_recoverySession != null && error.statusCode == '401')) {
          _recoverySession = null;
          _password.clear();
          _confirmation.clear();
          _error = 'This link has expired. Request a new reset email below.';
        } else {
          _error = _recoverySession != null
              ? error.message
              : 'Could not send a reset email. Please wait a moment and try again.';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updatePassword(Session session, String password) async {
    final response = await http
        .put(
          Uri.parse('${SupabaseConfig.url}/auth/v1/user'),
          headers: {
            'apikey': SupabaseConfig.publishableKey,
            'Authorization': 'Bearer ${session.accessToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'password': password}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String message = 'Could not update your password. Please try again.';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['msg'] is String) message = body['msg'] as String;
    } on FormatException {
      // An intermediary can return a plain-text error.
    }
    throw AuthException(message, statusCode: response.statusCode.toString());
  }

  void _goToSignIn() {
    if (widget.recoveryLink == null) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      );
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSetPassword = _recoverySession != null;
    final finished = _emailSent || _passwordChanged;
    final String instructions;
    if (_passwordChanged) {
      instructions = 'Password updated. You can now sign in with your new password.';
    } else if (_emailSent) {
      instructions = 'If an account exists for that email address, you’ll receive a reset link. Check your inbox and spam folder.';
    } else if (canSetPassword) {
      instructions = 'Choose a new password for your Roster Buddy account.';
    } else {
      instructions = 'Enter the email address you used to register.';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _checkingLink
                  ? const CircularProgressIndicator()
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(instructions),
                          const SizedBox(height: 16),
                          if (!finished) ...[
                            if (canSetPassword) ...[
                              TextFormField(
                                controller: _password,
                                decoration: const InputDecoration(labelText: 'New password'),
                                obscureText: true,
                                autofillHints: const [AutofillHints.newPassword],
                                validator: (value) => (value ?? '').length < 6
                                    ? 'Enter at least 6 characters'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _confirmation,
                                decoration: const InputDecoration(labelText: 'Confirm new password'),
                                obscureText: true,
                                validator: (value) => value != _password.text
                                    ? 'Passwords must match'
                                    : null,
                              ),
                            ] else
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(labelText: 'Email address'),
                                validator: (value) =>
                                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                            .hasMatch(value?.trim() ?? '')
                                        ? 'Enter a valid email address'
                                        : null,
                              ),
                            if (_error case final error?) ...[
                              const SizedBox(height: 12),
                              Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            ],
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(_busy
                                  ? 'Please wait…'
                                  : canSetPassword
                                      ? 'Save new password'
                                      : 'Send reset email'),
                            ),
                          ] else
                            FilledButton(
                              onPressed: _goToSignIn,
                              child: const Text('Back to sign in'),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
