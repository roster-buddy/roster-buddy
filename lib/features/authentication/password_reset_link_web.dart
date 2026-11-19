import 'dart:js_interop';

@JS('window.history.replaceState')
external void _replaceState(JSAny? data, JSString title, JSString url);

void clearPasswordResetFragment(Uri uri) {
  _replaceState(null, ''.toJS, uri.removeFragment().toString().toJS);
}
