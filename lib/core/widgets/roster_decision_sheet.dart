import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<T?> showRosterDecisionSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  isDismissible: barrierDismissible,
  builder: builder,
);

/// Shared presentation only: action callbacks retain their original behaviour.
class RosterDecisionSheet extends StatelessWidget {
  const RosterDecisionSheet({super.key, this.title, this.content, this.actions = const []});
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final titleText = title is Text ? (title as Text).data?.toLowerCase() ?? '' : '';
    final approval = titleText.contains('confirmed') ||
        titleText.contains('authorised') ||
        titleText.contains('rest day change') ||
        titleText.contains('union');
    final buttons = <Widget>[];
    for (final action in actions) {
      VoidCallback? callback;
      Widget? label;
      var primary = false;
      if (action is CupertinoDialogAction) {
        callback = action.onPressed;
        label = action.child;
        primary = !action.isDefaultAction && !action.isDestructiveAction;
      } else if (action is ButtonStyleButton) {
        callback = action.onPressed;
        label = action.child;
        primary = action is FilledButton || action is ElevatedButton;
      }
      if (label == null) {
        buttons.add(action);
        continue;
      }
      final text = label is Text ? label.data : null;
      if (approval && text == 'No') {
        label = const Text('No — prepare email');
        primary = true;
      } else if (approval && text == 'Yes') {
        label = const Text('Yes — action change');
        primary = false;
      }
      buttons.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SizedBox(width: double.infinity,
          child: primary
              ? FilledButton(onPressed: callback, child: label)
              : OutlinedButton(onPressed: callback, child: label)),
      ));
    }
    final hasBack = actions.any((a) {
      final Widget? child = a is CupertinoDialogAction ? a.child : a is ButtonStyleButton ? a.child : null;
      return child is Text && ['Back', 'Cancel'].contains(child.data);
    });
    return SafeArea(child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) DefaultTextStyle(
          style: const TextStyle(color: Color(0xFF102A43), fontSize: 22, fontWeight: FontWeight.w900),
          child: title!),
        if (content != null) ...[
          const SizedBox(height: 18),
          DefaultTextStyle(style: const TextStyle(color: Color(0xFF52667A), fontSize: 16, height: 1.4),
            child: content!),
        ],
        const SizedBox(height: 10),
        ...buttons,
        if (!hasBack) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
      ]),
    ));
  }
}
