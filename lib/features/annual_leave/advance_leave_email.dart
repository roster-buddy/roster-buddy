import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters/roster_date_format.dart';
import '../../core/services/annual_leave_service.dart';

Future<bool?> openAdvanceLeaveEmail(
  BuildContext context, {
  required DateTime leaveDate,
  required Uri email,
}) {
  final reminderDate = AnnualLeaveService.reminderDateFor(leaveDate);
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Schedule this email'),
      content: Text(
        'For annual leave on ${displayDate(leaveDate)}, schedule this email '
        'in your email app for 00:00 UK time on '
        '${weekdays[reminderDate.weekday - 1]} ${displayDate(reminderDate)}. '
        'If that time has passed, check your Sent folder before sending.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () async {
            bool opened;
            try {
              opened = await launchUrl(
                email,
                mode: LaunchMode.platformDefault,
                webOnlyWindowName: '_self',
              );
            } catch (_) {
              opened = false;
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext, opened);
          },
          child: const Text('Open email app'),
        ),
      ],
    ),
  );
}
