create table if not exists public.job_cards (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.roster_documents(id) on delete cascade,

  turn_number text not null,
  original_turn_code text not null,
  day_code text not null,

  plan_type text not null default 'unknown'
    check (plan_type in ('ltp', 'stp', 'vstp', 'unknown')),

  valid_from date not null,
  valid_to date not null,

  book_on time without time zone,
  book_off time without time zone,
  rostered_minutes integer,

  page_number integer,
  raw_text text,
  instructions jsonb not null default '[]'::jsonb,

  unique_key text not null,
  created_at timestamp with time zone not null default now(),

  constraint job_cards_valid_dates
    check (valid_to >= valid_from),

  constraint job_cards_document_unique
    unique (document_id, unique_key)
);

create index if not exists job_cards_turn_number_idx
  on public.job_cards (turn_number);

create index if not exists job_cards_validity_idx
  on public.job_cards (valid_from, valid_to);

create index if not exists job_cards_document_id_idx
  on public.job_cards (document_id);

alter table public.job_cards enable row level security;

drop policy if exists "Authenticated users can read job cards"
  on public.job_cards;

create policy "Authenticated users can read job cards"
  on public.job_cards
  for select
  to authenticated
  using (true);

drop policy if exists "Document owners can insert job cards"
  on public.job_cards;

create policy "Document owners can insert job cards"
  on public.job_cards
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.roster_documents
      where roster_documents.id = job_cards.document_id
        and roster_documents.user_id = auth.uid()
    )
  );

drop policy if exists "Document owners can update job cards"
  on public.job_cards;

create policy "Document owners can update job cards"
  on public.job_cards
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.roster_documents
      where roster_documents.id = job_cards.document_id
        and roster_documents.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.roster_documents
      where roster_documents.id = job_cards.document_id
        and roster_documents.user_id = auth.uid()
    )
  );

drop policy if exists "Document owners can delete job cards"
  on public.job_cards;

create policy "Document owners can delete job cards"
  on public.job_cards
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.roster_documents
      where roster_documents.id = job_cards.document_id
        and roster_documents.user_id = auth.uid()
    )
  );
