create table public.manual_duty_history (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 duty_date date not null, snapshot jsonb not null,
 archived_at timestamptz not null default now()
);
alter table public.manual_duty_history enable row level security;
create policy own_history_read on public.manual_duty_history for select to authenticated using ((select auth.uid())=user_id);
create policy own_history_insert on public.manual_duty_history for insert to authenticated with check ((select auth.uid())=user_id);
grant select,insert on public.manual_duty_history to authenticated;
grant usage,select on sequence public.manual_duty_history_id_seq to authenticated;
create index manual_duty_history_user_date on public.manual_duty_history(user_id,duty_date,archived_at desc);
create or replace function public.archive_manual_duty() returns trigger language plpgsql security invoker set search_path=public as $$
begin
 insert into public.manual_duty_history(user_id,duty_date,snapshot)
 values(old.user_id,old.duty_date,to_jsonb(old));
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
revoke all on function public.archive_manual_duty() from public,anon;
grant execute on function public.archive_manual_duty() to authenticated;
create trigger preserve_manual_duty_history before update or delete on public.manual_duties for each row execute function public.archive_manual_duty();
