import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/widgets/top_notice_banner.dart';

void main() {
  testWidgets('roster banner appears at top and disappears after four seconds', (tester) async {
    final banner = TopNoticeBanner();
    var views = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () => banner.show(context,
        message: 'Roster received', onView: () => views++),
        child: const Text('Show'))))));
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('Roster received'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Roster received')).dy, lessThan(100));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('Roster received'), findsNothing);
    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.tap(find.text('View'));
    await tester.pump();
    expect(views, 1);
    expect(find.text('Roster received'), findsNothing);
    banner.dismiss();
  });
}
