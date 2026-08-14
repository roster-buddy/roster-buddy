-- ============================================================
-- Roster Buddy
-- Initial setup / onboarding
-- ============================================================

alter table public.driver_profiles
  add column if not exists setup_completed boolean not null default false;

alter table public.driver_profiles
  add column if not exists base_roster_commencement_date date;

alter table public.driver_profiles
  add column if not exists has_mutual_roster_swap boolean not null default false;

alter table public.driver_profiles
  add column if not exists swap_partner_driver_number text;

alter table public.driver_profiles
  add column if not exists base_roster_starts_with_line text;

-- Existing Roster Buddy profiles pre-date onboarding and must not suddenly
-- be forced through the new-user setup wizard.
update public.driver_profiles
set setup_completed = true
where setup_completed = false;

comment on column public.driver_profiles.setup_completed is
  'True after the user has completed the Roster Buddy first-time setup wizard.';

comment on column public.driver_profiles.base_roster_commencement_date is
  'Optional Base Roster commencement Sunday entered during initial setup.';

comment on column public.driver_profiles.has_mutual_roster_swap is
  'Whether the driver normally alternates Base Roster lines with a permanent mutual-swap partner.';

comment on column public.driver_profiles.swap_partner_driver_number is
  'Roster/driver number of the permanent mutual-swap partner when applicable.';

comment on column public.driver_profiles.base_roster_starts_with_line is
  'Which roster line applies at the saved commencement point: mine or partner.';
