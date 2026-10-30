import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/authentication/credential_autofill_submitter.dart';

void main() {
  testWidgets('saved email then password submits once after fill settles', (tester) async {
    var calls = 0;
    final submitter = CredentialAutofillSubmitter(onReady: () => calls++);
    submitter.emailChanged('driver@example.test');
    submitter.passwordChanged('saved-password');
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, 1);
    submitter.passwordChanged('saved-password');
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    submitter.dispose();
  });

  testWidgets('password filled first waits for email', (tester) async {
    var calls = 0;
    final submitter = CredentialAutofillSubmitter(onReady: () => calls++);
    submitter.passwordChanged('saved-password');
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    submitter.emailChanged('driver@example.test');
    await tester.pump(const Duration(milliseconds: 450));
    expect(calls, 1);
    submitter.dispose();
  });

  testWidgets('normal typing does not submit an unfinished password', (tester) async {
    var calls = 0;
    final submitter = CredentialAutofillSubmitter(onReady: () => calls++);
    submitter.emailChanged('driver@example.test');
    const password = 'manual-password';
    for (var i = 1; i <= password.length; i++) {
      submitter.passwordChanged(password.substring(0, i));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(calls, 0);
    submitter.dispose();
  });

  testWidgets('manual submission or disposal cancels queued automatic submission', (tester) async {
    var calls = 0;
    final submitter = CredentialAutofillSubmitter(onReady: () => calls++);
    submitter.emailChanged('driver@example.test');
    submitter.passwordChanged('saved-password');
    submitter.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    submitter.passwordChanged('another-saved-password');
    submitter.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
  });
}
