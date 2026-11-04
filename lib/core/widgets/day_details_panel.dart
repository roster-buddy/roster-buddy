import 'package:flutter/material.dart';

/// Keeps the shift summary above the keyboard instead of behind it.
class DayDetailsPanel extends StatelessWidget {
  const DayDetailsPanel({
    super.key,
    required this.summary,
    required this.body,
    required this.actions,
  });

  final Widget summary;
  final List<Widget> body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(builder: (context, constraints) {
      final available = (constraints.maxHeight - keyboard)
          .clamp(0.0, constraints.maxHeight);
      final preferred = MediaQuery.sizeOf(context).height * 0.88;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: available < preferred ? available : preferred,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                  child: Row(children: [
                    const Expanded(child: Text('Day details',
                        style: TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(
                      tooltip: 'Close day details',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: summary,
                ),
                const SizedBox(height: 8),
                Expanded(child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: body,
                  ),
                )),
                // Leave room for editing; day actions return when typing ends.
                if (keyboard == 0) Container(
                  decoration: const BoxDecoration(border: Border(
                    top: BorderSide(color: Color(0xFFE0E5EA)))),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        actions[i],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
