create function roster_private.delete_declined_access_request()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if not roster_private.is_app_admin() or old.status <> 'pending' then
    raise exception 'Administrator required to decline a pending request';
  end if;
  if exists (select 1 from public.roster_documents where user_id = old.user_id)
     or exists (select 1 from storage.objects where owner_id = old.user_id::text) then
    raise exception 'Account owns roster documents and cannot be deleted here';
  end if;
  delete from auth.users where id = old.user_id;
  return new;
end;
$$;
revoke all on function roster_private.delete_declined_access_request() from public, anon, authenticated;
revoke all on function roster_private.record_app_access_review() from public, anon, authenticated;

create trigger delete_declined_access_request
after update of status on public.app_access
for each row when (old.status = 'pending' and new.status = 'declined')
execute function roster_private.delete_declined_access_request();

