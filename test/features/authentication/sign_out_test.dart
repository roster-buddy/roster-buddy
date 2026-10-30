import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/authentication/session_startup.dart';
import 'package:roster_buddy/features/authentication/sign_in_screen.dart';
import 'package:roster_buddy/features/authentication/sign_out.dart';

void main() {
  testWidgets('sign out removes restored Home and Settings from navigation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SessionStartup(
      loadDestination: () async => const Scaffold(body: Text('Restored Home')),
    )));
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.text('Restored Home')));
    unawaited(navigator.push<void>(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Settings fixture')),
    )));
    await tester.pumpAndSettle();
    final completed = Completer<void>();
    final signingOut = signOutAndResetNavigation(
      tester.element(find.text('Settings fixture')), signOut: () => completed.future,
    );
    await tester.pump();
    expect(find.text('Settings fixture'), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
    completed.complete();
    await signingOut;
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Restored Home'), findsNothing);
    expect(navigator.canPop(), isFalse);
    expect(await navigator.maybePop(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed sign out does not navigate away or claim success', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Roster'))));
    await expectLater(signOutAndResetNavigation(
      tester.element(find.text('Roster')),
      signOut: () async => throw StateError('Fixture connection failure'),
    ), throwsStateError);
    await tester.pumpAndSettle();
    expect(find.text('Roster'), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });
}
