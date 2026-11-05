create table public.roster_update_views (
  user_id uuid not null references auth.users(id) on delete cascade,
  notice_key text not null check (length(notice_key) between 1 and 512),
  received_at timestamptz not null,
  viewed_at timestamptz not null default now(),
  primary key (user_id, notice_key)
);
create index roster_update_views_received_idx
  on public.roster_update_views (user_id, received_at);
alter table public.roster_update_views enable row level security;
revoke all on public.roster_update_views from anon, authenticated;
grant select, insert on public.roster_update_views to authenticated;
create policy "Read own viewed roster updates" on public.roster_update_views
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Record own viewed roster updates" on public.roster_update_views
  for insert to authenticated with check ((select auth.uid()) = user_id);
