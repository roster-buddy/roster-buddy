alter table public.roster_push_events
  drop constraint roster_push_events_kind_check,
  add constraint roster_push_events_kind_check check (
    kind in (
      'allocated', 'changed', 'leave_conflict', 'test',
      'shift_start', 'shift_finish', 'base_roster_action'
    )
  );

create or replace function roster_private.queue_base_roster_setup_actions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.detected_type <> 'base_roster'
     or new.base_roster_commencement is null
     or new.processing_status <> 'processed' then
    return new;
  end if;

  if auth.uid() is not null and auth.uid() <> new.user_id then
    raise exception 'Uploader required';
  end if;

  insert into public.roster_push_events (
    user_id, document_id, duty_date, kind, title, body, event_key
  )
  select
    profile.user_id,
    new.id,
    null,
    'base_roster_action',
    'New Base Roster – setup required',
    'A Base Roster starting '
      || to_char(new.base_roster_commencement, 'DD/MM/YYYY')
      || ' has been published. Open Roster Buddy to choose your starting Sunday, numbered line and mutual-swap details.',
    'base-roster-setup|' || profile.user_id::text || '|' || new.id::text
  from public.driver_profiles profile
  join public.app_access access on access.user_id = profile.user_id
    and access.status = 'approved'
  where profile.setup_completed
    and profile.user_id <> new.user_id
    and lower(trim(profile.depot)) = new.depot
    and not exists (
      select 1 from public.base_rosters activation
      where activation.user_id = profile.user_id
        and activation.document_id = new.id::text
    )
  on conflict (event_key) do nothing;

  return new;
end;
$$;

revoke all on function roster_private.queue_base_roster_setup_actions()
  from public, anon, authenticated;

create trigger queue_base_roster_setup_actions
after update of processing_status on public.roster_documents
for each row
when (
  new.processing_status = 'processed'
  and old.processing_status is distinct from 'processed'
)
execute function roster_private.queue_base_roster_setup_actions();

create or replace function roster_private.queue_existing_base_roster_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  latest public.roster_documents%rowtype;
begin
  if not new.setup_completed
     or lower(trim(coalesce(new.depot, ''))) = '' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.setup_completed
     and old.depot is not distinct from new.depot then
    return new;
  end if;

  select document.* into latest
  from public.roster_documents document
  where document.processing_status = 'processed'
    and document.detected_type = 'base_roster'
    and document.base_roster_commencement is not null
    and document.depot = lower(trim(new.depot))
  order by document.base_roster_commencement desc, document.created_at desc
  limit 1;

  if latest.id is null or exists (
    select 1 from public.base_rosters activation
    where activation.user_id = new.user_id
      and activation.document_id = latest.id::text
  ) then
    return new;
  end if;

  insert into public.roster_push_events (
    user_id, document_id, duty_date, kind, title, body, event_key
  ) values (
    new.user_id,
    latest.id,
    null,
    'base_roster_action',
    'Base Roster setup required',
    'Choose your starting Sunday, numbered roster line and any mutual-swap details to add the current Base Roster to your calendar.',
    'base-roster-setup|' || new.user_id::text || '|' || latest.id::text
  )
  on conflict (event_key) do nothing;

  return new;
end;
$$;

revoke all on function roster_private.queue_existing_base_roster_for_new_user()
  from public, anon, authenticated;

create trigger queue_existing_base_roster_for_new_user
after insert or update of setup_completed, depot on public.driver_profiles
for each row
execute function roster_private.queue_existing_base_roster_for_new_user();

comment on column public.driver_profiles.base_roster_commencement_date is
  'The Sunday selected by this driver for the active depot Base Roster; the official published date is stored on roster_documents.';
