# Shift reminders

Drivers choose any combination of 15, 30, 45, 60, 75, 90, 105 and 120 minutes
before book-on during Initial Setup > Work preferences or Settings > Shift reminders.
The default is 30 minutes; an empty list disables advance reminders.
The five-minute book-off check is fixed for timed working/training/medical shifts.

Device Web Push permission and an active subscription are still required.
The existing one-minute push dispatcher calls the server scheduler, so devices do
not have to leave the app open. Timing is Europe/London, including overnight
finishes and BST/GMT. Push delivery remains subject to device connectivity.

Resolution uses personal manual duties, leave, Sunday availability, and the
Base < 10D < 7D < 48HR hierarchy. Pending reminders are rejected when the effective
shift or selected lead time changes. Start alerts expire at book-on or ten minutes
after their due time, whichever is earlier. Finish checks expire after thirty
minutes. A completed finish check is not sent again after a manual time edit.
The scheduler catches up at most five minutes after a missed polling run.

Push URLs open the shift's starting date. An overnight shift can still have its
finish time edited the following day.

## Deployment

Deploy the app/service worker and roster-push function before enabling scheduling.
The migration creates a server-only control row with enabled=false to prevent a
partial rollout from sending unusable links. Enable after successful deployment:

```sql
update roster_private.shift_reminder_control set enabled=true where singleton;
```

Set enabled=false to pause only timed shift reminders; upload-change pushes remain
active. The control table and all scheduling functions are inaccessible to clients.

## Verification

- `flutter test test/shift_reminder_preferences_test.dart`
- `node --test browser-scanner/push.test.mjs`
- Run `supabase/tests/shift_reminders.sql` in an administrative SQL session.
  Fixtures and queue changes are transactionally rolled back, without sending pushes.
