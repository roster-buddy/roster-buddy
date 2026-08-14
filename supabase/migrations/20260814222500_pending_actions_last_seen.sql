alter table public.driver_profiles
add column if not exists pending_actions_last_seen_at timestamptz;
