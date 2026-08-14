create table if not exists public.annual_leave_block_pending_actions (
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
  change_type text not null
    check (change_type in ('agreed_move', 'mutual_swap')),
  original_start_date date not null,
  original_end_date date not null,
  proposed_start_date date not null,
  proposed_end_date date not null,
  swap_driver_number text,
  swap_reference text,
  notes text,
  status text not null default 'awaiting_union'
    check (status in ('awaiting_union', 'confirmed', 'cancelled')),
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  updated_at timestamptz not null default now(),

  constraint annual_leave_block_pending_actions_date_order
    check (
      original_end_date >= original_start_date
      and proposed_end_date >= proposed_start_date
    ),

  constraint annual_leave_block_pending_actions_mutual_driver
    check (
      change_type <> 'mutual_swap'
      or nullif(btrim(swap_driver_number), '') is not null
    )
);

create unique index if not exists
  annual_leave_block_pending_actions_active_period_key
on public.annual_leave_block_pending_actions (
  user_id,
  leave_year,
  period_type
)
where status = 'awaiting_union';

create index if not exists
  annual_leave_block_pending_actions_user_date_idx
on public.annual_leave_block_pending_actions (
  user_id,
  proposed_start_date
)
where status = 'awaiting_union';

alter table public.annual_leave_block_pending_actions enable row level security;

drop policy if exists
  "Users can read own block pending actions"
on public.annual_leave_block_pending_actions;

create policy
  "Users can read own block pending actions"
on public.annual_leave_block_pending_actions
for select
using (auth.uid() = user_id);

drop policy if exists
  "Users can create own block pending actions"
on public.annual_leave_block_pending_actions;

create policy
  "Users can create own block pending actions"
on public.annual_leave_block_pending_actions
for insert
with check (auth.uid() = user_id);

drop policy if exists
  "Users can update own block pending actions"
on public.annual_leave_block_pending_actions;

create policy
  "Users can update own block pending actions"
on public.annual_leave_block_pending_actions
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

comment on table public.annual_leave_block_pending_actions is
  'Unconfirmed personal block annual leave moves and mutual swaps awaiting Union confirmation.';

comment on column public.annual_leave_block_pending_actions.status is
  'awaiting_union does not alter the live block allocation. confirmed actions are applied to annual_leave_block_overrides.';
