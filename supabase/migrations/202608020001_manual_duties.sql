create table if not exists public.manual_duties (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  duty_date date not null,

  duty_type text not null
    check (
      duty_type in (
        'working',
        'training',
        'medical',
        'rest_day',
        'annual_leave',
        'sick',
        'public_holiday',
        'unavailable',
        'unknown'
      )
    ),

  manual_change_type text not null
    check (
      manual_change_type in (
        'rest_day_worked',
        'edited_times',
        'selected_turn',
        'manual_change',
        'moved_rest_day'
      )
    ),

  turn_number text,
  book_on time,
  book_off time,
  rostered_minutes integer
    check (rostered_minutes is null or rostered_minutes >= 0),

  remarks text,
  original_source text,
  original_duty_type text,
  original_turn_number text,
  original_book_on time,
  original_book_off time,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (user_id, duty_date, manual_change_type)
);

create index if not exists manual_duties_user_date_idx
on public.manual_duties (
  user_id,
  duty_date
);

alter table public.manual_duties enable row level security;

drop policy if exists
  "Users can read their own manual duties"
on public.manual_duties;

create policy
  "Users can read their own manual duties"
on public.manual_duties
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists
  "Users can insert their own manual duties"
on public.manual_duties;

create policy
  "Users can insert their own manual duties"
on public.manual_duties
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists
  "Users can update their own manual duties"
on public.manual_duties;

create policy
  "Users can update their own manual duties"
on public.manual_duties
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists
  "Users can delete their own manual duties"
on public.manual_duties;

create policy
  "Users can delete their own manual duties"
on public.manual_duties
for delete
to authenticated
using (user_id = auth.uid());
