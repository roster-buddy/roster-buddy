create table if not exists public.annual_leave_balances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  leave_year integer not null,
  entitlement_days integer not null default 14,
  carry_over_days integer not null default 0,
  starting_balance_days integer not null default 14,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, leave_year)
);

create table if not exists public.annual_leave_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  leave_date date not null,
  status text not null default 'requested'
    check (
      status in (
        'requested',
        'abeyance',
        'granted',
        'refused',
        'cancelled'
      )
    ),
  request_type text not null default 'floating'
    check (
      request_type in (
        'floating',
        'block'
      )
    ),
  requested_at timestamptz not null default now(),
  decision_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, leave_date, request_type)
);

alter table public.annual_leave_balances enable row level security;
alter table public.annual_leave_requests enable row level security;

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

drop policy if exists "Users can read own annual leave requests"
  on public.annual_leave_requests;

create policy "Users can read own annual leave requests"
  on public.annual_leave_requests
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own annual leave requests"
  on public.annual_leave_requests;

create policy "Users can insert own annual leave requests"
  on public.annual_leave_requests
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own annual leave requests"
  on public.annual_leave_requests;

create policy "Users can update own annual leave requests"
  on public.annual_leave_requests
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own annual leave requests"
  on public.annual_leave_requests;

create policy "Users can delete own annual leave requests"
  on public.annual_leave_requests
  for delete
  using (auth.uid() = user_id);

create index if not exists annual_leave_requests_user_date_idx
  on public.annual_leave_requests (user_id, leave_date);

create index if not exists annual_leave_requests_user_status_idx
  on public.annual_leave_requests (user_id, status);

create index if not exists annual_leave_balances_user_year_idx
  on public.annual_leave_balances (user_id, leave_year);
