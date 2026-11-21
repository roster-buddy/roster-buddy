alter table public.roster_documents
  alter column user_id drop not null,
  drop constraint roster_documents_user_id_fkey,
  add constraint roster_documents_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete set null;

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

create or replace function roster_private.delete_declined_access_request()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not roster_private.is_app_admin() then
    raise exception 'Administrator required to delete an account';
  end if;
  if old.user_id = auth.uid() or exists (
    select 1 from public.app_admins where user_id = old.user_id
  ) then
    raise exception 'Administrator accounts cannot be deleted here';
  end if;

  -- Keep the blobs and paths intact while removing the uploader association.
  update storage.objects
  set owner = null, owner_id = null
  where owner = old.user_id or owner_id = old.user_id::text;

  delete from public.roster_push_events
  where kind = 'subscription_renewal'
    and split_part(event_key, '|', 3) = old.user_id::text;

  delete from auth.users where id = old.user_id;
  return new;
end;
$$;

drop trigger delete_declined_access_request on public.app_access;
create trigger delete_declined_access_request
after update of status on public.app_access
for each row when (old.status is distinct from new.status and new.status = 'declined')
execute function roster_private.delete_declined_access_request();
