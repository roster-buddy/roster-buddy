create table if not exists public.annual_leave_allocations (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null
    references public.roster_documents(id)
    on delete cascade,

  leave_year integer not null
    check (leave_year between 2020 and 2200),

  depot text not null,
  driver_number text not null,
  surname text not null,

  block_number integer not null
    check (block_number between 1 and 99),

  source text not null default 'official_roster'
    check (
      source in (
        'official_roster',
        'agreed_move',
        'mutual_swap',
        'manual_correction'
      )
    ),

  original_block_number integer,
  other_driver_number text,
  other_driver_surname text,
  swap_reference text,

  is_confirmed boolean not null default true,
  page_number integer,

  unique_key text not null,
  created_at timestamptz not null default now(),

  unique (document_id, unique_key)
);

create index if not exists
  annual_leave_allocations_driver_year_idx
on public.annual_leave_allocations (
  driver_number,
  leave_year
);

create index if not exists
  annual_leave_allocations_document_idx
on public.annual_leave_allocations (
  document_id
);

create table if not exists public.annual_leave_periods (
  id uuid primary key default gen_random_uuid(),

  allocation_id uuid not null
    references public.annual_leave_allocations(id)
    on delete cascade,

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

  created_at timestamptz not null default now(),

  check (end_date >= start_date),
  unique (allocation_id, period_type)
);

create index if not exists
  annual_leave_periods_allocation_idx
on public.annual_leave_periods (
  allocation_id
);

create index if not exists
  annual_leave_periods_dates_idx
on public.annual_leave_periods (
  start_date,
  end_date
);

alter table public.annual_leave_allocations enable row level security;
alter table public.annual_leave_periods enable row level security;

drop policy if exists
  "Authenticated users can read annual leave allocations"
on public.annual_leave_allocations;

create policy
  "Authenticated users can read annual leave allocations"
on public.annual_leave_allocations
for select
to authenticated
using (true);

drop policy if exists
  "Upload owners can insert annual leave allocations"
on public.annual_leave_allocations;

create policy
  "Upload owners can insert annual leave allocations"
on public.annual_leave_allocations
for insert
to authenticated
with check (
  exists (
    select 1
    from public.roster_documents document
    where document.id = document_id
      and document.user_id = auth.uid()
  )
);

drop policy if exists
  "Upload owners can update annual leave allocations"
on public.annual_leave_allocations;

create policy
  "Upload owners can update annual leave allocations"
on public.annual_leave_allocations
for update
to authenticated
using (
  exists (
    select 1
    from public.roster_documents document
    where document.id = document_id
      and document.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.roster_documents document
    where document.id = document_id
      and document.user_id = auth.uid()
  )
);

drop policy if exists
  "Upload owners can delete annual leave allocations"
on public.annual_leave_allocations;

create policy
  "Upload owners can delete annual leave allocations"
on public.annual_leave_allocations
for delete
to authenticated
using (
  exists (
    select 1
    from public.roster_documents document
    where document.id = document_id
      and document.user_id = auth.uid()
  )
);

drop policy if exists
  "Authenticated users can read annual leave periods"
on public.annual_leave_periods;

create policy
  "Authenticated users can read annual leave periods"
on public.annual_leave_periods
for select
to authenticated
using (true);

drop policy if exists
  "Upload owners can insert annual leave periods"
on public.annual_leave_periods;

create policy
  "Upload owners can insert annual leave periods"
on public.annual_leave_periods
for insert
to authenticated
with check (
  exists (
    select 1
    from public.annual_leave_allocations allocation
    join public.roster_documents document
      on document.id = allocation.document_id
    where allocation.id = allocation_id
      and document.user_id = auth.uid()
  )
);

drop policy if exists
  "Upload owners can update annual leave periods"
on public.annual_leave_periods;

create policy
  "Upload owners can update annual leave periods"
on public.annual_leave_periods
for update
to authenticated
using (
  exists (
    select 1
    from public.annual_leave_allocations allocation
    join public.roster_documents document
      on document.id = allocation.document_id
    where allocation.id = allocation_id
      and document.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.annual_leave_allocations allocation
    join public.roster_documents document
      on document.id = allocation.document_id
    where allocation.id = allocation_id
      and document.user_id = auth.uid()
  )
);

drop policy if exists
  "Upload owners can delete annual leave periods"
on public.annual_leave_periods;

create policy
  "Upload owners can delete annual leave periods"
on public.annual_leave_periods
for delete
to authenticated
using (
  exists (
    select 1
    from public.annual_leave_allocations allocation
    join public.roster_documents document
      on document.id = allocation.document_id
    where allocation.id = allocation_id
      and document.user_id = auth.uid()
  )
);
