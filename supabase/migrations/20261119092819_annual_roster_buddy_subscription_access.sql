alter table public.app_access
  add column subscription_expires_at timestamptz,
  drop constraint app_access_status_check,
  add constraint app_access_status_check check (
    status in ('pending', 'approved', 'declined', 'suspended')
  );

update public.app_access a
set subscription_expires_at = now() + interval '8760 hours'
where a.status = 'approved'
  and not exists (select 1 from public.app_admins admin where admin.user_id = a.user_id);

alter policy app_access_admin_update on public.app_access
with check (
  (select roster_private.is_app_admin())
  and status in ('pending', 'approved', 'declined', 'suspended')
);

create or replace function roster_private.has_approved_app_access()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.app_access a
    where a.user_id = (select auth.uid()) and a.status = 'approved'
      and (a.subscription_expires_at > now() or exists (
        select 1 from public.app_admins admin where admin.user_id = a.user_id
      ))
  );
$$;

create or replace function roster_private.record_app_access_review()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is not null and not roster_private.is_app_admin() then
    raise exception 'Administrator required';
  end if;

  new.user_id := old.user_id;
  new.email := old.email;
  new.requested_at := old.requested_at;
  new.first_name := old.first_name;
  new.last_name := old.last_name;
  new.requested_depot := old.requested_depot;
  new.subscription_expires_at := old.subscription_expires_at;
  new.reviewed_at := old.reviewed_at;
  new.reviewed_by := old.reviewed_by;

  if exists (select 1 from public.app_admins where user_id = old.user_id) then
    raise exception 'Administrator accounts cannot be changed here';
  end if;
  if new.status = 'declined' and old.status <> 'pending' then
    raise exception 'Only pending requests can be declined';
  end if;
  if new.status = 'suspended' and old.status <> 'approved' then
    raise exception 'Only approved accounts can be suspended';
  end if;
  if new.status = 'pending' and old.status <> 'pending' then
    raise exception 'Reviewed accounts cannot return to pending';
  end if;
  if new.status = 'approved' and (
    old.subscription_expires_at is null or old.subscription_expires_at <= now()
  ) then
    new.subscription_expires_at := now() + interval '8760 hours';
  elsif new.status = 'approved' and old.status = 'approved'
      and old.subscription_expires_at <= now() + interval '168 hours' then
    new.subscription_expires_at := old.subscription_expires_at + interval '8760 hours';
  end if;
  if new.status is distinct from old.status
     or new.subscription_expires_at is distinct from old.subscription_expires_at then
    new.reviewed_at := now();
    new.reviewed_by := auth.uid();
  end if;
  return new;
end;
$$;

alter table public.roster_push_events
  drop constraint roster_push_events_kind_check,
  add constraint roster_push_events_kind_check check (kind in (
    'allocated', 'changed', 'leave_conflict', 'test', 'shift_start',
    'shift_finish', 'base_roster_action', 'subscription_renewal'
  ));

create function roster_private.queue_subscription_renewal_reminders()
returns void language sql set search_path = ''
as $$
  insert into public.roster_push_events (user_id, kind, title, body, event_key, target_url)
  select admin.user_id, 'subscription_renewal', 'Roster Buddy subscription due',
    coalesce(nullif(concat_ws(' ', a.first_name, a.last_name), ''), a.email)
      || ' is due for renewal on '
      || to_char(a.subscription_expires_at at time zone 'Europe/London', 'DD/MM/YYYY')
      || '. Open Settings → Access and subscriptions to review.',
    concat_ws('|', 'subscription-renewal', admin.user_id, a.user_id,
      extract(epoch from a.subscription_expires_at)), '?'
  from public.app_access a
  cross join public.app_admins admin
  where a.status in ('approved', 'suspended')
    and a.subscription_expires_at > now()
    and a.subscription_expires_at <= now() + interval '168 hours'
    and exists (
      select 1 from public.roster_push_subscriptions s where s.user_id = admin.user_id
    )
  on conflict (event_key) do nothing;
$$;
revoke all on function roster_private.queue_subscription_renewal_reminders() from public, anon, authenticated;
select cron.schedule('subscription-renewal-reminders', '*/15 * * * *',
  'select roster_private.queue_subscription_renewal_reminders();');

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
 where exists (
     select 1 from public.app_access a where a.user_id = e.user_id
       and a.status = 'approved' and (a.subscription_expires_at > now() or exists (
         select 1 from public.app_admins admin where admin.user_id = a.user_id
       ))
   )
 and (e.expires_at is null or e.expires_at>now())
 and (e.reminder_signature is null or (
   e.reminder_signature=md5(roster_private.effective_shift_for_reminder(e.user_id,e.duty_date)::text)
   and (e.kind<>'shift_start' or exists(select 1 from public.driver_profiles p
     where p.user_id=e.user_id and e.lead_minutes=any(p.shift_reminder_minutes)))))
 and e.kind<>'test' and e.created_at>=s.created_at and e.created_at>now()-interval '3 days'
 on conflict do nothing;
 with groups_to_claim as (
   select distinct d.subscription_id,coalesce(e.document_id,e.id) as batch_id
   from public.roster_push_deliveries d join public.roster_push_events e on e.id=d.event_id
   where exists (
     select 1 from public.app_access a where a.user_id = e.user_id
       and a.status = 'approved' and (a.subscription_expires_at > now() or exists (
         select 1 from public.app_admins admin where admin.user_id = a.user_id
       ))
   )
   and d.attempts<5 and d.next_attempt_at<=now() and
     (d.status='pending' or (d.status='sending' and d.locked_at<now()-interval '2 minutes'))
   limit 10
 ), candidates as (
   select d.id from public.roster_push_deliveries d join public.roster_push_events e on e.id=d.event_id
   join groups_to_claim g on g.subscription_id=d.subscription_id and g.batch_id=coalesce(e.document_id,e.id)
   where exists (
     select 1 from public.app_access a where a.user_id = e.user_id
       and a.status = 'approved' and (a.subscription_expires_at > now() or exists (
         select 1 from public.app_admins admin where admin.user_id = a.user_id
       ))
   )
   and d.attempts<5 and d.next_attempt_at<=now() and
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
end $function$;
