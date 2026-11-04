-- Account-owned preferences; book-off checks are intentionally not configurable.
alter table public.driver_profiles add column if not exists shift_reminder_minutes integer[] not null default array[30];
alter table public.driver_profiles add constraint shift_reminder_minutes_allowed
 check (shift_reminder_minutes <@ array[15,30,45,60,75,90,105,120] and array_position(shift_reminder_minutes,null) is null);
alter table public.roster_push_events add column if not exists target_url text not null default '?notifications=1';
alter table public.roster_push_events add column if not exists expires_at timestamptz;
alter table public.roster_push_events add column if not exists reminder_signature text;
alter table public.roster_push_events add column if not exists lead_minutes integer;
alter table public.roster_push_events drop constraint roster_push_events_kind_check;
alter table public.roster_push_events add constraint roster_push_events_kind_check
 check (kind in ('allocated','changed','leave_conflict','test','shift_start','shift_finish'));

-- Effective block periods mirror official allocations and confirmed user moves.
create or replace function roster_private.reminder_block_periods(who uuid)
returns table(start_date date,end_date date)
language sql stable set search_path='' as $$
 with official as (
   select l.* from public.annual_leave_periods l
   join public.annual_leave_allocations a on a.id=l.allocation_id and a.is_confirmed
   join public.driver_profiles p on p.user_id=who and trim(p.driver_number)=trim(a.driver_number)
 ), overrides as (
   select o.* from public.annual_leave_block_overrides o where o.user_id=who
   and (o.change_type<>'manual' or not exists(
     select 1 from official l where extract(year from l.start_date)=o.leave_year and l.period_type=o.period_type))
 )
 select l.start_date,l.end_date from official l where not exists (
   select 1 from overrides o where o.period_type=l.period_type
   and l.start_date between o.original_start_date and o.original_end_date)
 union all select o.override_start_date,o.override_end_date from overrides o
$$;
revoke all on function roster_private.reminder_block_periods(uuid) from public,anon,authenticated;

-- Server-side resolution is required even when every device is closed.
create or replace function roster_private.effective_shift_for_reminder(who uuid,day date)
returns jsonb language plpgsql stable set search_path='' as $$
declare profile public.driver_profiles%rowtype; result jsonb;
begin
 select * into profile from public.driver_profiles where user_id=who;
 if not found then return null; end if;
 -- A granted floating day remains leave until it is cancelled.
 if exists(select 1 from public.annual_leave_requests where user_id=who
   and leave_date=day and request_type='floating' and status='granted') then return null; end if;
 select jsonb_build_object('source','manual','duty_type',d.duty_type,
   'book_on',d.book_on,'book_off',d.book_off,'turn_number',d.turn_number,'amendment_code',null)
 into result from public.manual_duties d where d.user_id=who and d.duty_date=day
 order by d.updated_at desc,
   case d.manual_change_type when 'manual_change' then 4 when 'edited_times' then 3
     when 'selected_turn' then 2 when 'rest_day_worked' then 1 else 0 end desc,d.id desc limit 1;
 if result is not null then return result; end if;
 if exists(select 1 from roster_private.reminder_block_periods(who) l
   where day between l.start_date and l.end_date) then return null; end if;
 if extract(dow from day)=0 and not exists(
   select 1 from public.sunday_availability_overrides where user_id=who and sunday_date=day and is_available)
   and (profile.permanently_unavailable_sundays or exists(
     select 1 from roster_private.reminder_block_periods(who) l
     where l.end_date=day-1 and extract(dow from l.end_date)=6)) then return null; end if;
 select jsonb_build_object('source',d.source,'duty_type',d.duty_type,
   'book_on',d.book_on,'book_off',d.book_off,'turn_number',d.turn_number,'amendment_code',d.amendment_code)
 into result from public.document_duties d
 join public.roster_documents r on r.id=d.document_id and r.processing_status='processed'
 where d.duty_date=day and d.source in ('base_roster','10_day','7_day','48_hour','annual_leave')
 and (case when d.source='base_roster' then
     nullif(trim(d.driver_number),'')=nullif(trim(coalesce(profile.roster_number,profile.driver_number)),'')
   else roster_private.pay_matches(d.payroll_number,profile.payroll_number) end)
 order by case d.source when 'annual_leave' then 5 when '48_hour' then 4
   when '7_day' then 3 when '10_day' then 2 else 1 end desc,
   -- Same-source ordering matches the resolver's Duty.uniqueKey.
   concat_ws('|',d.duty_date,d.source,d.payroll_number,d.driver_number,d.turn_number,
     to_char(d.book_on,'HH24:MI'),to_char(d.book_off,'HH24:MI'),d.amendment_code) desc,
   d.id desc limit 1;
 return result;
end $$;
revoke all on function roster_private.effective_shift_for_reminder(uuid,date) from public,anon,authenticated;

create or replace function roster_private.shift_reminder_candidates(who uuid,at_time timestamptz)
returns table(duty_date date,kind text,lead_minutes integer,due_at timestamptz,
 expires_at timestamptz,title text,body text,target_url text,signature text,event_key text)
language sql stable set search_path='' as $$
 with dates as (
   select ((at_time at time zone 'Europe/London')::date + i) as day from generate_series(-1,1) i
 ), duties as (
   select day,roster_private.effective_shift_for_reminder(who,day) as duty from dates
 ), shifts as (
   select day,duty,
     (day+(duty->>'book_on')::time) at time zone 'Europe/London' as starts,
     (day+case when (duty->>'book_off')::time<(duty->>'book_on')::time then 1 else 0 end
       +(duty->>'book_off')::time) at time zone 'Europe/London' as finishes
   from duties where duty->>'duty_type' in ('working','training','medical')
     and duty->>'book_on' is not null and duty->>'book_off' is not null
     and coalesce(duty->>'turn_number','') not ilike '%unalloc%'
 ), offsets as (
   select distinct unnest(p.shift_reminder_minutes) as minutes from public.driver_profiles p where p.user_id=who
 ), events as (
   select s.*, 'shift_start'::text as event_kind,o.minutes as lead,
     s.starts-make_interval(mins=>o.minutes) as due
   from shifts s cross join offsets o
   union all
   select s.*,'shift_finish',5,s.finishes+interval '5 minutes' from shifts s
 )
 select day,event_kind,lead,due,
   case when event_kind='shift_start' then least(starts,due+interval '10 minutes')
        else due+interval '30 minutes' end,
   case when event_kind='shift_start' then
     'Book on in '||lead::text||' minutes'
     else 'Check your book-off time' end,
   case when event_kind='shift_start' then
     roster_private.push_duty_label(duty->>'amendment_code',duty->>'duty_type')||' · '
     else 'Finished at '||to_char((duty->>'book_off')::time,'HH24:MI')||
       '? Delay or overtime? Check and edit your book-off time. ' end ||
   case duty->>'source' when 'manual' then 'M ' when '48_hour' then '48HR '
     when '7_day' then '7D ' when '10_day' then '10D ' else 'BASE ' end ||
   to_char((duty->>'book_on')::time,'HH24MI')||'–'||to_char((duty->>'book_off')::time,'HH24MI')||
   case when nullif(trim(duty->>'turn_number'),'') is not null then ' T'||trim(duty->>'turn_number') else '' end,
   '?shift='||day::text||case when event_kind='shift_finish' then '&bookOff=1' else '' end,
   md5(duty::text),
   'shift-reminder|'||who::text||'|'||day::text||'|'||event_kind||'|'||lead::text||'|'||md5(duty::text)
 from events
$$;
revoke all on function roster_private.shift_reminder_candidates(uuid,timestamptz) from public,anon,authenticated;

-- Enable after the app and sender that understand shift links have deployed.
create table if not exists roster_private.shift_reminder_control (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false
);
alter table roster_private.shift_reminder_control enable row level security;
revoke all on roster_private.shift_reminder_control from public,anon,authenticated;
insert into roster_private.shift_reminder_control(singleton,enabled) values(true,false) on conflict do nothing;

create or replace function roster_private.queue_due_shift_reminders()
returns integer language plpgsql security definer set search_path='' as $$
declare queued integer;
begin
 if not exists(select 1 from roster_private.shift_reminder_control where enabled) then return 0; end if;
 insert into public.roster_push_events(user_id,duty_date,kind,title,body,event_key,
   target_url,expires_at,reminder_signature,lead_minutes)
 select p.user_id,c.duty_date,c.kind,c.title,c.body,c.event_key,c.target_url,
   c.expires_at,c.signature,c.lead_minutes
 from public.driver_profiles p
 cross join lateral roster_private.shift_reminder_candidates(p.user_id,now()) c
 where exists(select 1 from public.roster_push_subscriptions s where s.user_id=p.user_id)
   and c.due_at<=now() and c.due_at>now()-interval '5 minutes' and c.expires_at>now()
   and (c.kind<>'shift_finish' or not exists(
     select 1 from public.roster_push_events e join public.roster_push_deliveries d on d.event_id=e.id
     where e.user_id=p.user_id and e.duty_date=c.duty_date and e.kind='shift_finish' and d.status='sent'))
 on conflict(event_key) do nothing;
 get diagnostics queued=row_count;
 return queued;
end $$;
revoke all on function roster_private.queue_due_shift_reminders() from public,anon,authenticated;

CREATE OR REPLACE FUNCTION roster_private.claim_push_deliveries()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 perform roster_private.queue_due_shift_reminders();
 -- Do not deliver stale reminders after a roster, leave or preference change.
 update public.roster_push_deliveries d set status='failed',last_error='Reminder expired or shift changed'
 from public.roster_push_events e,public.driver_profiles p
 where e.id=d.event_id and p.user_id=e.user_id and e.kind in ('shift_start','shift_finish')
   and d.status in ('pending','sending') and
   (e.expires_at<=now() or e.reminder_signature is distinct from
     md5(roster_private.effective_shift_for_reminder(e.user_id,e.duty_date)::text)
    or (e.kind='shift_start' and not(e.lead_minutes=any(p.shift_reminder_minutes))));
 insert into public.roster_push_deliveries(event_id,subscription_id)
 select e.id,s.id from public.roster_push_events e join public.roster_push_subscriptions s on s.user_id=e.user_id
 where (e.expires_at is null or e.expires_at>now())
 and (e.reminder_signature is null or (
   e.reminder_signature=md5(roster_private.effective_shift_for_reminder(e.user_id,e.duty_date)::text)
   and (e.kind<>'shift_start' or exists(select 1 from public.driver_profiles p
     where p.user_id=e.user_id and e.lead_minutes=any(p.shift_reminder_minutes)))))
 and e.kind<>'test' and e.created_at>=s.created_at and e.created_at>now()-interval '3 days'
 on conflict do nothing;
 with groups_to_claim as (
   select distinct d.subscription_id,coalesce(e.document_id,e.id) as batch_id
   from public.roster_push_deliveries d join public.roster_push_events e on e.id=d.event_id
   where d.attempts<5 and d.next_attempt_at<=now() and
     (d.status='pending' or (d.status='sending' and d.locked_at<now()-interval '2 minutes'))
   limit 10
 ), candidates as (
   select d.id from public.roster_push_deliveries d join public.roster_push_events e on e.id=d.event_id
   join groups_to_claim g on g.subscription_id=d.subscription_id and g.batch_id=coalesce(e.document_id,e.id)
   where d.attempts<5 and d.next_attempt_at<=now() and
     (d.status='pending' or (d.status='sending' and d.locked_at<now()-interval '2 minutes'))
   for update of d skip locked
 ), claimed as (
   update public.roster_push_deliveries d set status='sending',attempts=attempts+1,locked_at=now()
   from candidates c where c.id=d.id returning d.*
 ), batches as (
   select s.id as subscription_id,s.subscription,coalesce(e.document_id,e.id) as batch_id,
     array_agg(c.id) as delivery_ids,max(c.attempts) as attempts,count(*) as records,
     bool_or(e.kind='leave_conflict') as conflict,
     (array_agg(e.title order by e.created_at desc))[1] as title,
     (array_agg(e.body order by e.created_at desc))[1] as body,
     (array_agg(e.target_url order by e.created_at desc))[1] as target_url,
     min(e.expires_at) as expires_at
   from claimed c join public.roster_push_events e on e.id=c.event_id
   join public.roster_push_subscriptions s on s.id=c.subscription_id
   group by s.id,s.subscription,coalesce(e.document_id,e.id)
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'delivery_ids',delivery_ids,'subscription_id',subscription_id,'subscription',subscription,
   'attempts',attempts,'event_id',batch_id,'target_url',target_url,
   'ttl',case when expires_at is null then 3600 else greatest(1,least(3600,extract(epoch from expires_at-now())::int)) end,
   'title',case when records>1 and conflict then 'Roster updated — annual leave conflict'
                when records>1 then 'Roster updated' else title end,
   'body',case when records>1 then records::text||' roster dates updated.'||
      case when conflict then ' A sheet conflicts with recorded annual leave.' else '' end||
      ' Open Roster Buddy to review the dates and uploaded document.' else body end
 )), '[]'::jsonb) into result from batches;
 return result;
end $function$
;
