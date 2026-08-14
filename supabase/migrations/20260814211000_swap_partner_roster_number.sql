alter table public.driver_profiles
  add column if not exists swap_partner_roster_number text;

update public.driver_profiles
set swap_partner_roster_number = swap_partner_driver_number
where (swap_partner_roster_number is null or btrim(swap_partner_roster_number) = '')
  and swap_partner_driver_number is not null
  and btrim(swap_partner_driver_number) <> '';

comment on column public.driver_profiles.swap_partner_roster_number is
  'Roster number of the driver used for a permanent Base Roster mutual swap.';

alter table public.base_rosters
  add column if not exists swap_partner_roster_number text;

update public.base_rosters
set swap_partner_roster_number = swap_partner_driver_number
where (swap_partner_roster_number is null or btrim(swap_partner_roster_number) = '')
  and swap_partner_driver_number is not null
  and btrim(swap_partner_driver_number) <> '';

comment on column public.base_rosters.swap_partner_roster_number is
  'Roster number of the mutual-swap partner used when generating Base Roster duties.';
