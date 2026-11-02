create or replace function roster_private.claim_push_deliveries() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 insert into public.roster_push_deliveries(event_id,subscription_id)
 select e.id,s.id from public.roster_push_events e join public.roster_push_subscriptions s on s.user_id=e.user_id
 where e.kind<>'test' and e.created_at>=s.created_at and e.created_at>now()-interval '3 days'
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
     (array_agg(e.body order by e.created_at desc))[1] as body
   from claimed c join public.roster_push_events e on e.id=c.event_id
   join public.roster_push_subscriptions s on s.id=c.subscription_id
   group by s.id,s.subscription,coalesce(e.document_id,e.id)
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'delivery_ids',delivery_ids,'subscription_id',subscription_id,'subscription',subscription,
   'attempts',attempts,'event_id',batch_id,
   'title',case when records>1 and conflict then 'Roster updated — annual leave conflict'
                when records>1 then 'Roster updated' else title end,
   'body',case when records>1 then records::text||' roster dates updated.'||
      case when conflict then ' A sheet conflicts with recorded annual leave.' else '' end||
      ' Open Roster Buddy to review the dates and uploaded document.' else body end
 )), '[]'::jsonb) into result from batches;
 return result;
end $$;
