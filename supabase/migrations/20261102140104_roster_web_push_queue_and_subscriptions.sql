create schema if not exists roster_private;
revoke all on schema roster_private from public, anon, authenticated;
grant usage on schema roster_private to service_role;

create table public.roster_push_subscriptions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text not null unique,
 subscription jsonb not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index on public.roster_push_subscriptions(user_id);
alter table public.roster_push_subscriptions enable row level security;
revoke all on public.roster_push_subscriptions from anon, authenticated;
grant select,delete on public.roster_push_subscriptions to authenticated;
grant all on public.roster_push_subscriptions to service_role;
create policy push_subscription_owner on public.roster_push_subscriptions for select to authenticated using ((select auth.uid())=user_id);
create policy push_subscription_owner_delete on public.roster_push_subscriptions for delete to authenticated using ((select auth.uid())=user_id);

create table public.roster_push_events (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 document_id uuid references public.roster_documents(id) on delete set null,
 duty_date date,
 kind text not null check(kind in ('allocated','changed','leave_conflict','test')),
 title text not null,
 body text not null,
 event_key text not null unique,
 created_at timestamptz not null default now()
);
create index on public.roster_push_events(user_id,created_at desc);
create index on public.roster_push_events(document_id);
alter table public.roster_push_events enable row level security;
revoke all on public.roster_push_events from anon,authenticated;
grant select on public.roster_push_events to authenticated;
grant all on public.roster_push_events to service_role;
create policy push_events_owner on public.roster_push_events for select to authenticated using ((select auth.uid())=user_id);

create table roster_private.push_state (
 user_id uuid not null references auth.users(id) on delete cascade,
 duty_date date not null,
 signature text not null,
 primary key(user_id,duty_date)
);
create table public.roster_push_deliveries (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.roster_push_events(id) on delete cascade,
 subscription_id uuid not null references public.roster_push_subscriptions(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','sending','sent','failed')),
 attempts int not null default 0,
 next_attempt_at timestamptz not null default now(),
 locked_at timestamptz,
 sent_at timestamptz,
 last_error text,
 unique(event_id,subscription_id)
);
create index on public.roster_push_deliveries(subscription_id);
create index on public.roster_push_deliveries(status,next_attempt_at);
alter table public.roster_push_deliveries enable row level security;
revoke all on public.roster_push_deliveries from anon,authenticated;
grant all on public.roster_push_deliveries to service_role;
revoke all on all tables in schema roster_private from public,anon,authenticated;

create function roster_private.pay_matches(a text,b text) returns boolean
language sql immutable set search_path='' as $$
 select trim(a) ~ '^[0-9]{4,}$' and trim(b) ~ '^[0-9]{4,}$' and right(trim(a),4)=right(trim(b),4)
$$;
create function roster_private.best_roster_signature(who uuid, day date, excluding uuid default null) returns text
language sql stable set search_path='' as $$
 select concat_ws('|',d.source,d.duty_type,coalesce(d.turn_number,''),coalesce(d.book_on::text,''),coalesce(d.book_off::text,''))
 from public.document_duties d join public.roster_documents r on r.id=d.document_id
 join public.driver_profiles p on p.user_id=who
 where d.duty_date=day and r.processing_status='processed' and (excluding is null or r.id<>excluding)
 and d.source in ('base_roster','10_day','7_day','48_hour')
 and (roster_private.pay_matches(d.payroll_number,p.payroll_number)
   or (d.source='base_roster' and trim(d.driver_number)=trim(p.roster_number)))
 order by case d.source when '48_hour' then 4 when '7_day' then 3 when '10_day' then 2 else 1 end desc,
 d.created_at desc,d.id desc limit 1
$$;
create function roster_private.recorded_annual_leave(who uuid, day date) returns boolean
language plpgsql stable set search_path='' as $$
declare manual_type text;
begin
 if exists(select 1 from public.annual_leave_requests where user_id=who and leave_date=day and status='granted') then return true; end if;
 select duty_type into manual_type from public.manual_duties where user_id=who and duty_date=day
 order by updated_at desc,
 case manual_change_type when 'manual_change' then 4 when 'edited_times' then 3 when 'selected_turn' then 2 when 'rest_day_worked' then 1 else 0 end desc limit 1;
 if manual_type is not null then return manual_type='annual_leave'; end if;
 if exists(select 1 from public.annual_leave_block_overrides o where o.user_id=who
   and day between o.override_start_date and o.override_end_date) then return true; end if;
 return exists(
   select 1 from public.annual_leave_allocations a
   join public.annual_leave_periods l on l.allocation_id=a.id
   join public.driver_profiles p on p.user_id=who and trim(p.driver_number)=trim(a.driver_number)
   where a.is_confirmed and day between l.start_date and l.end_date
   and not exists(select 1 from public.annual_leave_block_overrides o where o.user_id=who
     and o.period_type=l.period_type and day between o.original_start_date and o.original_end_date)
 );
end $$;

-- Seed comparison state only; historical imports do not send retrospective pushes.
insert into roster_private.push_state(user_id,duty_date,signature)
select p.user_id,d.duty_date,roster_private.best_roster_signature(p.user_id,d.duty_date)
from public.driver_profiles p join public.document_duties d on (
 roster_private.pay_matches(d.payroll_number,p.payroll_number)
 or (d.source='base_roster' and trim(d.driver_number)=trim(p.roster_number)))
where roster_private.best_roster_signature(p.user_id,d.duty_date) is not null
group by p.user_id,d.duty_date on conflict do nothing;

-- Internal fan-out must read each affected driver's private leave records.
-- This trigger has no client-callable API; invocation follows an uploader-owned update.
create function roster_private.queue_completed_roster_push() returns trigger
language plpgsql security definer set search_path='' as $$
declare rec record; old_sig text; new_sig text; conflict_leave boolean; event_kind text; signature text; label text;
begin
 if auth.uid() is not null and auth.uid()<>new.user_id then raise exception 'Uploader required'; end if;
 if auth.uid() is null and session_user<>'postgres' and coalesce(current_setting('request.jwt.claims',true),'') not like '%service_role%' then raise exception 'Authenticated processing required'; end if;
 for rec in
   select distinct on (p.user_id,d.duty_date) p.user_id,d.duty_date,d.duty_type,d.turn_number,d.book_on,d.book_off,d.source
   from public.document_duties d join public.driver_profiles p on roster_private.pay_matches(d.payroll_number,p.payroll_number)
   where d.document_id=new.id and d.source in ('10_day','7_day','48_hour')
   order by p.user_id,d.duty_date,case d.source when '48_hour' then 4 when '7_day' then 3 else 2 end desc,d.created_at desc
 loop
   select s.signature into old_sig from roster_private.push_state s where s.user_id=rec.user_id and s.duty_date=rec.duty_date for update;
   if old_sig is null then old_sig:=roster_private.best_roster_signature(rec.user_id,rec.duty_date,new.id); end if;
   new_sig:=roster_private.best_roster_signature(rec.user_id,rec.duty_date);
   conflict_leave:=rec.duty_type in ('working','training','medical') and roster_private.recorded_annual_leave(rec.user_id,rec.duty_date);
   if conflict_leave or old_sig is distinct from new_sig then
     event_kind:=case when conflict_leave then 'leave_conflict' when old_sig is null then 'allocated' else 'changed' end;
     signature:=concat_ws('|',rec.source,rec.duty_type,rec.turn_number,rec.book_on,rec.book_off);
     label:=case rec.source when '48_hour' then '48HR' when '7_day' then '7D' else '10D' end;
     insert into public.roster_push_events(user_id,document_id,duty_date,kind,title,body,event_key)
     values(rec.user_id,new.id,rec.duty_date,event_kind,
       case when conflict_leave then 'Annual leave conflict — investigate' when old_sig is null then 'Rostered shift allocated' else 'Rostered shift updated' end,
       to_char(rec.duty_date,'DD/MM/YYYY')||' · '||label||
       case when conflict_leave then ': the sheet lists you working on recorded annual leave. Open Roster Buddy to investigate.'
       else ' · '||coalesce(to_char(rec.book_on,'HH24:MI'),'—')||'–'||coalesce(to_char(rec.book_off,'HH24:MI'),'—')||
         case when rec.turn_number is null then '' else ' · Turn '||rec.turn_number end end,
       rec.user_id::text||'|'||new.id::text||'|'||rec.duty_date::text||'|'||event_kind||'|'||md5(signature))
     on conflict(event_key) do nothing;
   end if;
   if new_sig is not null then
     insert into roster_private.push_state values(rec.user_id,rec.duty_date,new_sig)
     on conflict(user_id,duty_date) do update set signature=excluded.signature;
   end if;
 end loop;
 return new;
end $$;
revoke all on function roster_private.queue_completed_roster_push() from public,anon,authenticated;
create trigger queue_completed_roster_push after update of processing_status on public.roster_documents
for each row when(new.processing_status='processed' and old.processing_status is distinct from 'processed')
execute function roster_private.queue_completed_roster_push();

create function roster_private.claim_push_deliveries() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 insert into public.roster_push_deliveries(event_id,subscription_id)
 select e.id,s.id from public.roster_push_events e join public.roster_push_subscriptions s on s.user_id=e.user_id
 where e.created_at>=s.created_at and e.created_at>now()-interval '3 days'
 on conflict do nothing;
 with candidates as (
   select id from public.roster_push_deliveries
   where attempts<5 and next_attempt_at<=now() and
    (status='pending' or (status='sending' and locked_at<now()-interval '2 minutes'))
   order by next_attempt_at limit 40 for update skip locked
 ), claimed as (
   update public.roster_push_deliveries d set status='sending',attempts=attempts+1,locked_at=now()
   from candidates c where c.id=d.id returning d.*
 )
 select coalesce(jsonb_agg(jsonb_build_object('delivery_id',c.id,'subscription_id',s.id,
   'subscription',s.subscription,'attempts',c.attempts,'event_id',e.id,'title',e.title,'body',e.body)), '[]'::jsonb)
 into result from claimed c join public.roster_push_events e on e.id=c.event_id
 join public.roster_push_subscriptions s on s.id=c.subscription_id;
 return result;
end $$;
revoke all on function roster_private.claim_push_deliveries() from public,anon,authenticated;
grant execute on function roster_private.claim_push_deliveries() to service_role;
create function public.claim_roster_push_deliveries() returns jsonb language sql security invoker set search_path=''
as $$ select roster_private.claim_push_deliveries() $$;
revoke all on function public.claim_roster_push_deliveries() from public,anon,authenticated;
grant execute on function public.claim_roster_push_deliveries() to service_role;

create function roster_private.push_config() returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_build_object(
 'vapid',(select decrypted_secret::jsonb from vault.decrypted_secrets where name='roster_push_vapid'),
 'dispatch',(select decrypted_secret from vault.decrypted_secrets where name='roster_push_dispatch'))
$$;
revoke all on function roster_private.push_config() from public,anon,authenticated;
grant execute on function roster_private.push_config() to service_role;
create function public.roster_push_config() returns jsonb language sql security invoker set search_path=''
as $$ select roster_private.push_config() $$;
revoke all on function public.roster_push_config() from public,anon,authenticated;
grant execute on function public.roster_push_config() to service_role;
revoke all on function roster_private.pay_matches(text,text),roster_private.best_roster_signature(uuid,date,uuid),roster_private.recorded_annual_leave(uuid,date) from public,anon,authenticated;
