alter table public.driver_profiles add column if not exists roster_updates_seen_at timestamptz;
comment on column public.driver_profiles.roster_updates_seen_at is 'Latest routine roster update viewed by this user; unresolved leave conflicts remain actionable.';
