import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../lib/core/widgets/roster_time_input_formatter.dart';

void main() {
  const formatter = RosterTimeInputFormatter();
  TextEditingValue value(String text, [int? caret]) => TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret ?? text.length));
  test('four digit typing and pasted times keep leading zeroes', () {
    for (final entry in {'0425': '04:25', '1258': '12:58', '0000': '00:00', '23:59': '23:59'}.entries) {
      final result = formatter.formatEditUpdate(TextEditingValue.empty, value(entry.key));
      expect(result.text, entry.value);
      expect(result.selection.extentOffset, 5);
    }
  });
  test('partial entry and deletion stay editable', () {
    expect(formatter.formatEditUpdate(value('04:25'), value('04:2')).text, '042');
    expect(formatter.formatEditUpdate(value('04'), value('042')).text, '042');
    expect(formatter.formatEditUpdate(value('04:25'), value('04:256')), value('04:25'));
    final middle = formatter.formatEditUpdate(value('04:25'), value('14:25', 1));
    expect(middle.text, '14:25');
    expect(middle.selection.extentOffset, 1);
  });
  test('save normalisation also accepts four raw digits', () {
    expect(RosterTimeInputFormatter.normalise('0425'), '04:25');
    expect(RosterTimeInputFormatter.normalise('1258'), '12:58');
  });
}
