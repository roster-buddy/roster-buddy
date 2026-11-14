create table public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.app_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'declined')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);

alter table public.app_admins enable row level security;
alter table public.app_access enable row level security;

grant select on public.app_admins to authenticated;
grant select, update on public.app_access to authenticated;

create policy app_admins_read_own
on public.app_admins for select to authenticated
using (user_id = (select auth.uid()));

create or replace function roster_private.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.app_admins
    where user_id = (select auth.uid())
  );
$$;

create or replace function roster_private.has_approved_app_access()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.app_access
    where user_id = (select auth.uid()) and status = 'approved'
  );
$$;

revoke all on function roster_private.is_app_admin() from public;
revoke all on function roster_private.has_approved_app_access() from public;
grant execute on function roster_private.is_app_admin() to authenticated;
grant execute on function roster_private.has_approved_app_access() to authenticated;

create policy app_access_read_own_or_admin
on public.app_access for select to authenticated
using (
  user_id = (select auth.uid())
  or (select roster_private.is_app_admin())
);

create policy app_access_admin_update
on public.app_access for update to authenticated
using ((select roster_private.is_app_admin()))
with check (
  (select roster_private.is_app_admin())
  and status in ('pending', 'approved', 'declined')
);

create or replace function roster_private.record_app_access_review()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.user_id := old.user_id;
  new.email := old.email;
  new.requested_at := old.requested_at;
  if new.status is distinct from old.status then
    new.reviewed_at := now();
    new.reviewed_by := (select auth.uid());
  end if;
  return new;
end;
$$;

create trigger record_app_access_review
before update on public.app_access
for each row execute function roster_private.record_app_access_review();

create or replace function roster_private.create_app_access_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.app_access (user_id, email)
  values (new.id, new.email);
  return new;
end;
$$;

revoke all on function roster_private.create_app_access_request() from public;

create trigger create_app_access_request
after insert on auth.users
for each row execute function roster_private.create_app_access_request();

insert into public.app_access (user_id, email, status, reviewed_at)
select id, email,
  case when email_confirmed_at is null then 'pending' else 'approved' end,
  case when email_confirmed_at is null then null else now() end
from auth.users
on conflict (user_id) do nothing;

insert into public.app_admins (user_id)
values ('60e22301-edee-44b5-8b23-16985b962ff2')
on conflict do nothing;

do $$
declare
  target regclass;
begin
  for target in
    select c.oid::regclass
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and c.relrowsecurity
      and c.relname not in ('app_access', 'app_admins')
  loop
    execute format(
      'create policy app_access_required on %s as restrictive for all to authenticated '
      'using ((select roster_private.has_approved_app_access())) '
      'with check ((select roster_private.has_approved_app_access()))',
      target
    );
  end loop;
end;
$$;

create policy app_access_required
on storage.objects as restrictive for all to authenticated
using ((select roster_private.has_approved_app_access()))
with check ((select roster_private.has_approved_app_access()));
