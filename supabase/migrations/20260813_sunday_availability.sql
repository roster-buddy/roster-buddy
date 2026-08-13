-- ============================================================
-- Roster Buddy
-- Sunday availability
-- ============================================================

-- Drivers can be permanently unavailable for Sunday work.
alter table public.driver_profiles
  add column if not exists permanently_unavailable_sundays
    boolean not null default false;

-- A driver can make themselves available for an individual Sunday.
--
-- This is deliberately date-specific. It does not change their normal
-- permanent Sunday setting.
create table if not exists public.sunday_availability_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sunday_date date not null,
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint sunday_availability_overrides_sunday_check
    check (extract(isodow from sunday_date) = 7),

  constraint sunday_availability_overrides_user_date_key
    unique (user_id, sunday_date)
);

alter table public.sunday_availability_overrides enable row level security;

drop policy if exists
  "Users can read own Sunday availability overrides"
  on public.sunday_availability_overrides;

create policy
  "Users can read own Sunday availability overrides"
  on public.sunday_availability_overrides
  for select
  using (auth.uid() = user_id);

drop policy if exists
  "Users can insert own Sunday availability overrides"
  on public.sunday_availability_overrides;

create policy
  "Users can insert own Sunday availability overrides"
  on public.sunday_availability_overrides
  for insert
  with check (auth.uid() = user_id);

drop policy if exists
  "Users can update own Sunday availability overrides"
  on public.sunday_availability_overrides;

create policy
  "Users can update own Sunday availability overrides"
  on public.sunday_availability_overrides
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists
  "Users can delete own Sunday availability overrides"
  on public.sunday_availability_overrides;

create policy
  "Users can delete own Sunday availability overrides"
  on public.sunday_availability_overrides
  for delete
  using (auth.uid() = user_id);

create index if not exists
  sunday_availability_overrides_user_date_idx
  on public.sunday_availability_overrides(user_id, sunday_date);
