-- Roster Buddy driver identifiers
--
-- payroll_number = daily amendment sheets
-- roster_number  = Base Roster
-- driver_number  = Annual Leave Roster

alter table public.driver_profiles
  add column if not exists roster_number text;

-- Historically driver_number was used for Base Roster matching.
-- Preserve that existing value as the user's roster number.
update public.driver_profiles
set roster_number = driver_number
where (roster_number is null or btrim(roster_number) = '')
  and driver_number is not null
  and btrim(driver_number) <> '';

comment on column public.driver_profiles.payroll_number is
  'Payroll number used to match daily amendment sheets such as 10-Day, 7-Day and 48-Hour.';

comment on column public.driver_profiles.roster_number is
  'Roster number used to match the driver line on the Base Roster.';

comment on column public.driver_profiles.driver_number is
  'Driver number used to match the driver on Annual Leave Rosters.';
