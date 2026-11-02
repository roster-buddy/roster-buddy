import 'dart:js_interop';

@JS('window.open')
external _DocumentWindow? _openWindow(JSString url, JSString target);

extension type _DocumentWindow._(JSObject _) implements JSObject {
  external set location(JSString value);
  external set opener(JSAny? value);
  external void close();
}

/// Reserve the tab during the tap so Safari does not block delayed URL signing.
Future<void> openUploadedDocument(Future<String> Function() resolveUrl) async {
  final target = _openWindow('about:blank'.toJS, '_blank'.toJS);
  if (target == null) throw StateError('The browser blocked the document tab');
  target.opener = null;
  try {
    final url = Uri.parse(await resolveUrl());
    if (url.scheme != 'https') throw StateError('Invalid document URL');
    target.location = url.toString().toJS;
  } catch (_) {
    target.close();
    rethrow;
  }
}
