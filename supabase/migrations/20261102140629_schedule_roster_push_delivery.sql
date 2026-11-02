create or replace function roster_private.claim_push_deliveries() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 insert into public.roster_push_deliveries(event_id,subscription_id)
 select e.id,s.id from public.roster_push_events e join public.roster_push_subscriptions s on s.user_id=e.user_id
 where e.kind<>'test' and e.created_at>=s.created_at and e.created_at>now()-interval '3 days'
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

create or replace function roster_private.queue_completed_roster_push() returns trigger
language plpgsql security definer set search_path='' as $$
declare rec record; old_sig text; new_sig text; conflict_leave boolean; event_kind text; signature text; label text;
begin
 if auth.uid() is not null and auth.uid()<>new.user_id then raise exception 'Uploader required'; end if;
 if auth.uid() is null and session_user<>'postgres' and coalesce(current_setting('request.jwt.claims',true),'') not like '%service_role%' then raise exception 'Authenticated processing required'; end if;
 for rec in
   select distinct on (p.user_id,d.duty_date) p.user_id,d.duty_date,d.duty_type,d.turn_number,d.book_on,d.book_off,d.source
   from public.document_duties d join public.driver_profiles p on (roster_private.pay_matches(d.payroll_number,p.payroll_number)
     or (d.source='base_roster' and trim(d.driver_number)=trim(p.roster_number)))
   where d.document_id=new.id and d.source in ('base_roster','10_day','7_day','48_hour')
   order by p.user_id,d.duty_date,case d.source when '48_hour' then 4 when '7_day' then 3 when '10_day' then 2 else 1 end desc,d.created_at desc
 loop
   select s.signature into old_sig from roster_private.push_state s where s.user_id=rec.user_id and s.duty_date=rec.duty_date for update;
   if old_sig is null then old_sig:=roster_private.best_roster_signature(rec.user_id,rec.duty_date,new.id); end if;
   new_sig:=roster_private.best_roster_signature(rec.user_id,rec.duty_date);
   conflict_leave:=rec.source<>'base_roster' and rec.duty_type in ('working','training','medical') and roster_private.recorded_annual_leave(rec.user_id,rec.duty_date);
   if conflict_leave or old_sig is distinct from new_sig then
     event_kind:=case when conflict_leave then 'leave_conflict' when old_sig is null then 'allocated' else 'changed' end;
     signature:=concat_ws('|',rec.source,rec.duty_type,rec.turn_number,rec.book_on,rec.book_off);
     label:=case rec.source when '48_hour' then '48HR' when '7_day' then '7D' when '10_day' then '10D' else 'BASE' end;
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


alter table roster_private.push_state enable row level security;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create function roster_private.dispatch_roster_push() returns bigint
language plpgsql security definer set search_path='' as $$
declare token text; request_id bigint;
begin
 select decrypted_secret into token from vault.decrypted_secrets where name='roster_push_dispatch';
 if token is null then raise exception 'Push dispatcher is not configured'; end if;
 select net.http_post(
   url:='https://ahrkivleahrfvmmtujrh.supabase.co/functions/v1/roster-push',
   headers:=jsonb_build_object('Content-Type','application/json','X-Roster-Dispatch-Token',token),
   body:='{"action":"dispatch"}'::jsonb,
   timeout_milliseconds:=50000
 ) into request_id;
 return request_id;
end $$;
revoke all on function roster_private.dispatch_roster_push() from public,anon,authenticated;
grant execute on function roster_private.dispatch_roster_push() to service_role;
select cron.schedule('roster-push-dispatch','* * * * *','select roster_private.dispatch_roster_push();');
