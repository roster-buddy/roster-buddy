import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'upload_service.dart';

Future<UploadSource?> chooseUploadSource(
  BuildContext context, {
  bool isWeb = kIsWeb,
}) {
  if (isWeb) return Future.value(UploadSource.file);
  return showCupertinoModalPopup<UploadSource>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: const Text('Add a roster document'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext, UploadSource.camera),
          child: const Text('Take Photo'),
        ),
        CupertinoActionSheetAction(
          onPressed: () =>
              Navigator.pop(sheetContext, UploadSource.photoLibrary),
          child: const Text('Photo Library'),
        ),
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext, UploadSource.file),
          child: const Text('Choose File'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(sheetContext),
        child: const Text('Cancel'),
      ),
    ),
  );
}
