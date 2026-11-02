create policy roster_push_deliveries_server_only on public.roster_push_deliveries for all to service_role using (true) with check (true);
create policy roster_push_state_server_only on roster_private.push_state for all to service_role using (true) with check (true);
