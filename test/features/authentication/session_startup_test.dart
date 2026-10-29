import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/authentication/session_startup.dart';
import 'package:roster_buddy/features/authentication/sign_in_screen.dart';

void main() {
  testWidgets('startup waits for restoration before showing destination', (tester) async {
    final destination = Completer<Widget>();
    await tester.pumpWidget(MaterialApp(home: SessionStartup(
      loadDestination: () => destination.future,
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    destination.complete(const Text('Restored roster'));
    await tester.pumpAndSettle();
    expect(find.text('Restored roster'), findsOneWidget);
  });

  testWidgets('restoration failure offers retry and can recover', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(home: SessionStartup(
      loadDestination: () async {
        if (attempts++ == 0) throw Exception('offline');
        return const Text('Restored roster');
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Restored roster'), findsOneWidget);
  });

  testWidgets('login advertises username and password to autofill', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    expect(SemanticsBinding.instance.semanticsEnabled, isTrue);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].autofillHints, contains(AutofillHints.username));
    expect(fields[1].autofillHints, contains(AutofillHints.password));
    expect(find.byType(AutofillGroup), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
