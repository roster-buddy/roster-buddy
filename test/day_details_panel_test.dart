import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/widgets/day_details_panel.dart';

void main() {
  testWidgets('first keyboard opening keeps shift and Save above keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var saved = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          enableDrag: false,
          builder: (_) => DayDetailsPanel(
            summary: SizedBox(height: 230, child: Column(children: [
              const TextField(key: Key('time')),
              TextButton(onPressed: () { saved++; }, child: const Text('Save')),
            ])),
            body: List.generate(12, (i) => Text('Document $i')),
            actions: const [Text('Request annual leave')],
          ),
        ),
        child: const Text('Open day'),
      )),
    )));
    await tester.tap(find.text('Open day'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('time')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getBottomRight(find.text('Save')).dy, lessThan(504));
    expect(find.text('Request annual leave'), findsNothing);
    await tester.tap(find.text('Save'));
    expect(saved, 1);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.text('Request annual leave'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
