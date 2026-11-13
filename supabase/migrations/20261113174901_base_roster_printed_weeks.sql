alter table public.base_rosters
  add column start_week_number smallint check (start_week_number between 1 and 54),
  add column swap_partner_week_number smallint check (swap_partner_week_number between 1 and 54),
  drop constraint base_roster_swap_details,
  add constraint base_roster_swap_details check (
    (not has_mutual_swap and swap_partner_driver_number is null
      and swap_partner_week_number is null and starts_with_line = 'mine')
    or
    (has_mutual_swap and (
      (start_week_number is null and swap_partner_week_number is null
        and coalesce(nullif(trim(swap_partner_roster_number), ''),
                     nullif(trim(swap_partner_driver_number), '')) is not null)
      or
      (start_week_number is not null and swap_partner_week_number is not null
        and start_week_number <> swap_partner_week_number)
    ))
  );
