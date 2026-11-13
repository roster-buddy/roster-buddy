create table if not exists public.personal_day_notes (
  user_id uuid not null references auth.users(id) on delete cascade,
  note_date date not null,
  note text not null check (length(btrim(note)) between 1 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, note_date)
);

alter table public.personal_day_notes enable row level security;
drop policy if exists "Users manage their own personal day notes" on public.personal_day_notes;
create policy "Users manage their own personal day notes"
  on public.personal_day_notes for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
revoke all on table public.personal_day_notes from anon;
grant select, insert, update, delete on table public.personal_day_notes to authenticated;
