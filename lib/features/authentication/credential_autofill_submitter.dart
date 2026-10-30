import 'dart:async';

/// Password managers fill a complete value in one edit. Wait briefly for both
/// fields, without submitting a partially typed password on each keystroke.
class CredentialAutofillSubmitter {
  CredentialAutofillSubmitter({required this.onReady});
  final void Function() onReady;
  String _email = '';
  String _password = '';
  bool _bulkFill = false;
  Timer? _timer;

  void emailChanged(String value) {
    _email = value.trim();
    _schedule();
  }

  void passwordChanged(String value) {
    if (value == _password) return;
    final inserted = value.length - _password.length;
    _password = value;
    if (inserted > 1 && value.length >= 6) {
      _bulkFill = true;
    } else if (inserted <= 0) {
      _bulkFill = false;
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_bulkFill || !_email.contains('@') || !_email.contains('.') || _password.length < 6) return;
    _timer = Timer(const Duration(milliseconds: 400), () {
      _bulkFill = false;
      onReady();
    });
  }

  void cancel() {
    _timer?.cancel();
    _bulkFill = false;
  }

  void dispose() {
    cancel();
    _email = '';
    _password = '';
  }
}
