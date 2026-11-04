create policy shift_reminder_control_server_only on roster_private.shift_reminder_control
 for all to service_role using (true) with check (true);