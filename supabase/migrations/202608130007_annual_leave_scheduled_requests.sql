create table if not exists public.annual_leave_scheduled_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  leave_date date not null,
  scheduled_for timestamptz not null,
  notes text,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'sent', 'cancelled', 'failed')),
  sent_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists
  annual_leave_scheduled_requests_active_date_key
on public.annual_leave_scheduled_requests (user_id, leave_date)
where status = 'scheduled';

create index if not exists
  annual_leave_scheduled_requests_due_idx
on public.annual_leave_scheduled_requests (scheduled_for)
where status = 'scheduled';

alter table public.annual_leave_scheduled_requests enable row level security;

drop policy if exists
  "Users can read own scheduled annual leave requests"
on public.annual_leave_scheduled_requests;

create policy
  "Users can read own scheduled annual leave requests"
on public.annual_leave_scheduled_requests
for select
using (auth.uid() = user_id);

drop policy if exists
  "Users can create own scheduled annual leave requests"
on public.annual_leave_scheduled_requests;

create policy
  "Users can create own scheduled annual leave requests"
on public.annual_leave_scheduled_requests
for insert
with check (auth.uid() = user_id);

drop policy if exists
  "Users can update own scheduled annual leave requests"
on public.annual_leave_scheduled_requests;

create policy
  "Users can update own scheduled annual leave requests"
on public.annual_leave_scheduled_requests
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists
  "Users can delete own scheduled annual leave requests"
on public.annual_leave_scheduled_requests;

create policy
  "Users can delete own scheduled annual leave requests"
on public.annual_leave_scheduled_requests
for delete
using (auth.uid() = user_id);
