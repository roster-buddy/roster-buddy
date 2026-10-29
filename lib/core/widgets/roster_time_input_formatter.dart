import 'package:flutter/services.dart';

/// Enter four digits; show the separator automatically once complete.
class RosterTimeInputFormatter extends TextInputFormatter {
  const RosterTimeInputFormatter();

  static String normalise(String value) {
    final digits = value.replaceAll(RegExp('[^0-9]'), '');
    return digits.length == 4
        ? '${digits.substring(0, 2)}:${digits.substring(2)}'
        : value.trim();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!newValue.composing.isCollapsed) return newValue;
    final digits = newValue.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.length > 4) return oldValue;
    final caret = newValue.selection.extentOffset.clamp(0, newValue.text.length);
    final before = newValue.text.substring(0, caret).replaceAll(RegExp('[^0-9]'), '').length;
    final text = digits.length == 4 ? normalise(digits) : digits;
    final offset = before + (digits.length == 4 && before > 2 ? 1 : 0);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset.clamp(0, text.length)));
  }
}
