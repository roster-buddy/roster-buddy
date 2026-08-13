-- ============================================================
-- Roster Buddy
-- Annual Leave block management
-- ============================================================

-- Stores the driver's block-cycle week for each leave year.
--
-- WMT cycle:
--   1 -> 6 -> 11 -> 3 -> 8 -> 13 -> 5 -> 10 -> 2 -> 7 -> 12 -> 4 -> 9 -> 1
--
-- The cycle therefore advances by five positions each year,
-- wrapping within weeks 1-13.
create table if not exists public.annual_leave_block_cycles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  leave_year integer not null,
  week_index integer not null
    check (week_index between 1 and 13),
  source text not null default 'manual'
    check (
      source in (
        'official_roster',
        'manual',
        'calculated'
      )
    ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, leave_year)
);

-- User-specific changes to official block leave.
--
-- The official Annual Leave Roster remains unchanged.
-- These records sit over the top of that baseline for the individual user.
create table if not exists public.annual_leave_block_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  leave_year integer not null,

  period_type text not null
    check (
      period_type in (
        'spring',
        'summer_first_week',
        'summer_second_week',
        'winter'
      )
    ),

  original_start_date date,
  original_end_date date,

  override_start_date date not null,
  override_end_date date not null,

  change_type text not null
    check (
      change_type in (
        'manual',
        'agreed_move',
        'mutual_swap'
      )
    ),

  -- Optional details of the other driver involved in a mutual swap.
  swap_driver_number text,
  swap_reference text,
  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (override_end_date >= override_start_date),

  unique (user_id, leave_year, period_type)
);

alter table public.annual_leave_block_overrides
  add column if not exists original_start_date date,
  add column if not exists original_end_date date,
  add column if not exists override_start_date date,
  add column if not exists override_end_date date,
  add column if not exists change_type text,
  add column if not exists swap_driver_number text,
  add column if not exists swap_reference text;

update public.annual_leave_block_overrides
set
  override_start_date = coalesce(override_start_date, start_date),
  override_end_date = coalesce(override_end_date, end_date),
  change_type = coalesce(
    change_type,
    case
      when override_type = 'manual_correction' then 'manual'
      when override_type = 'agreed_move' then 'agreed_move'
      when override_type = 'mutual_swap' then 'mutual_swap'
      else 'manual'
    end
  );

alter table public.annual_leave_block_overrides
  alter column override_start_date set not null,
  alter column override_end_date set not null,
  alter column change_type set not null;

alter table public.annual_leave_block_cycles enable row level security;
alter table public.annual_leave_block_overrides enable row level security;

-- ============================================================
-- Block cycle RLS
-- ============================================================

drop policy if exists "Users can read own annual leave block cycles"
  on public.annual_leave_block_cycles;

create policy "Users can read own annual leave block cycles"
  on public.annual_leave_block_cycles
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own annual leave block cycles"
  on public.annual_leave_block_cycles;

create policy "Users can insert own annual leave block cycles"
  on public.annual_leave_block_cycles
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own annual leave block cycles"
  on public.annual_leave_block_cycles;

create policy "Users can update own annual leave block cycles"
  on public.annual_leave_block_cycles
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own annual leave block cycles"
  on public.annual_leave_block_cycles;

create policy "Users can delete own annual leave block cycles"
  on public.annual_leave_block_cycles
  for delete
  using (auth.uid() = user_id);

-- ============================================================
-- Block override RLS
-- ============================================================

drop policy if exists "Users can read own annual leave block overrides"
  on public.annual_leave_block_overrides;

create policy "Users can read own annual leave block overrides"
  on public.annual_leave_block_overrides
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own annual leave block overrides"
  on public.annual_leave_block_overrides;

create policy "Users can insert own annual leave block overrides"
  on public.annual_leave_block_overrides
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own annual leave block overrides"
  on public.annual_leave_block_overrides;

create policy "Users can update own annual leave block overrides"
  on public.annual_leave_block_overrides
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own annual leave block overrides"
  on public.annual_leave_block_overrides;

create policy "Users can delete own annual leave block overrides"
  on public.annual_leave_block_overrides
  for delete
  using (auth.uid() = user_id);

create index if not exists annual_leave_block_cycles_user_year_idx
  on public.annual_leave_block_cycles (user_id, leave_year);

create index if not exists annual_leave_block_overrides_user_year_idx
  on public.annual_leave_block_overrides (user_id, leave_year);

create index if not exists annual_leave_block_overrides_dates_idx
  on public.annual_leave_block_overrides (
    override_start_date,
    override_end_date
  );

comment on table public.annual_leave_block_cycles is
  'Stores each user block-leave cycle week. The following leave year normally advances five positions within weeks 1-13.';

comment on table public.annual_leave_block_overrides is
  'User-specific block leave moves and mutual swaps. The official uploaded Annual Leave Roster remains unchanged.';
