-- ============================================================
-- Roster Buddy
-- Annual Leave extended yearly setup
-- ============================================================

alter table public.annual_leave_balances
  add column if not exists bonus_days integer not null default 0,
  add column if not exists carry_over_days integer not null default 0,
  add column if not exists lieu_days integer not null default 0;

-- Existing carry_over_days may already exist from the first migration.
-- The ADD COLUMN IF NOT EXISTS above is intentionally safe.

-- Prevent negative yearly allowances.
alter table public.annual_leave_balances
  drop constraint if exists annual_leave_balances_entitlement_days_check;

alter table public.annual_leave_balances
  add constraint annual_leave_balances_entitlement_days_check
  check (entitlement_days >= 0);

alter table public.annual_leave_balances
  drop constraint if exists annual_leave_balances_starting_balance_days_check;

alter table public.annual_leave_balances
  add constraint annual_leave_balances_starting_balance_days_check
  check (starting_balance_days >= 0);

alter table public.annual_leave_balances
  drop constraint if exists annual_leave_balances_bonus_days_check;

alter table public.annual_leave_balances
  add constraint annual_leave_balances_bonus_days_check
  check (bonus_days >= 0);

alter table public.annual_leave_balances
  drop constraint if exists annual_leave_balances_carry_over_days_check;

alter table public.annual_leave_balances
  add constraint annual_leave_balances_carry_over_days_check
  check (carry_over_days >= 0);

alter table public.annual_leave_balances
  drop constraint if exists annual_leave_balances_lieu_days_check;

alter table public.annual_leave_balances
  add constraint annual_leave_balances_lieu_days_check
  check (lieu_days >= 0);


-- ============================================================
-- Annual Leave Block yearly allocation
--
-- One record per user / leave year.
--
-- allocated_week is the driver's numbered Annual Leave week.
-- The official annual leave roster remains the baseline.
-- Overrides are stored separately below.
-- ============================================================

create table if not exists public.annual_leave_block_years (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  leave_year integer not null,
  allocated_week integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint annual_leave_block_years_week_check
    check (allocated_week between 1 and 13),

  unique (user_id, leave_year)
);

alter table public.annual_leave_block_years enable row level security;


-- ============================================================
-- User-specific Block Leave overrides
--
-- The master Annual Leave Roster is never altered.
-- A move/swap only overrides the affected user's period.
--
-- summer_first_week and summer_second_week remain independent,
-- allowing either of the two Block B weeks to move separately.
-- ============================================================

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

  start_date date not null,
  end_date date not null,

  override_type text not null
    check (
      override_type in (
        'agreed_move',
        'mutual_swap',
        'manual_correction'
      )
    ),

  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint annual_leave_block_overrides_dates_check
    check (end_date >= start_date),

  unique (user_id, leave_year, period_type)
);

alter table public.annual_leave_block_overrides enable row level security;


-- ============================================================
-- RLS: balances
-- ============================================================

drop policy if exists "Users can read own annual leave balances"
  on public.annual_leave_balances;

create policy "Users can read own annual leave balances"
  on public.annual_leave_balances
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own annual leave balances"
  on public.annual_leave_balances;

create policy "Users can insert own annual leave balances"
  on public.annual_leave_balances
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own annual leave balances"
  on public.annual_leave_balances;

create policy "Users can update own annual leave balances"
  on public.annual_leave_balances
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ============================================================
-- RLS: block year
-- ============================================================

drop policy if exists "Users can read own annual leave block years"
  on public.annual_leave_block_years;

create policy "Users can read own annual leave block years"
  on public.annual_leave_block_years
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own annual leave block years"
  on public.annual_leave_block_years;

create policy "Users can insert own annual leave block years"
  on public.annual_leave_block_years
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own annual leave block years"
  on public.annual_leave_block_years;

create policy "Users can update own annual leave block years"
  on public.annual_leave_block_years
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ============================================================
-- RLS: block overrides
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


-- ============================================================
-- Documentation
-- ============================================================

comment on column public.annual_leave_balances.starting_balance_days is
  'Floating leave balance available when Roster Buddy starts tracking this leave year. Next leave year defaults back to the normal entitlement.';

comment on column public.annual_leave_balances.entitlement_days is
  'Normal floating annual leave entitlement. WMT default is 14 days.';

comment on column public.annual_leave_balances.bonus_days is
  'Extra floating leave granted for this leave year, such as an additional bank holiday allowance.';

comment on column public.annual_leave_balances.carry_over_days is
  'Unused floating leave carried into this leave year from a previous year.';

comment on column public.annual_leave_balances.lieu_days is
  'Additional days in lieu available during this leave year.';

comment on column public.annual_leave_block_years.allocated_week is
  'The driver allocated Annual Leave week number, 1-13. New leave years normally progress forward by 5 positions.';

comment on table public.annual_leave_block_overrides is
  'User-specific agreed Block Leave moves and mutual swaps. Does not alter the official master Annual Leave Roster.';
