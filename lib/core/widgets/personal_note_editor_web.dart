import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@JS('rosterOpenNoteEditor')
external JSPromise<JSString?> _openNoteEditor(
  JSString title,
  JSString note,
  JSBoolean dark,
);

Future<String?>? openPlatformNoteEditor(BuildContext context, String? note) {
  if (defaultTargetPlatform != TargetPlatform.iOS) return null;

  final result = _openNoteEditor(
    (note == null ? 'Add plans or note' : 'Edit plans or note').toJS,
    (note ?? '').toJS,
    (Theme.of(context).brightness == Brightness.dark).toJS,
  );
  return result.toDart.then((value) => value?.toDart);
}
