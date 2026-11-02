import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/features/upload/upload_service.dart';
import 'package:roster_buddy/features/upload/upload_source_picker.dart';

void main() {
  testWidgets('browser upload skips the duplicate app source menu', (tester) async {
    UploadSource? selected;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () async { selected = await chooseUploadSource(context, isWeb: true); },
      child: const Text('Upload'),
    ))));
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(selected, UploadSource.file);
    expect(find.text('Add a roster document'), findsNothing);
  });

  testWidgets('native upload offers camera, library and files', (tester) async {
    UploadSource? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                selected = await chooseUploadSource(context);
              },
              child: const Text('Upload'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Photo Library'), findsOneWidget);
    expect(find.text('Choose File'), findsOneWidget);
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    expect(selected, UploadSource.camera);
  });

  testWidgets('upload can choose a file without opening the camera', (
    tester,
  ) async {
    UploadSource? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                selected = await chooseUploadSource(context);
              },
              child: const Text('Upload'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose File'));
    await tester.pumpAndSettle();
    expect(selected, UploadSource.file);
  });
}
