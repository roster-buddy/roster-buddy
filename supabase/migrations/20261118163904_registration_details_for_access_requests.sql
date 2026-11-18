alter table public.app_access
  add column first_name text,
  add column last_name text,
  add column requested_depot text;

create or replace function roster_private.create_app_access_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.app_access (user_id, email, first_name, last_name, requested_depot)
  values (
    new.id, new.email,
    nullif(left(btrim(new.raw_user_meta_data ->> 'first_name'), 100), ''),
    nullif(left(btrim(new.raw_user_meta_data ->> 'last_name'), 100), ''),
    case when new.raw_user_meta_data ->> 'depot' = 'Wolverhampton' then 'Wolverhampton' end
  );
  return new;
end;
$$;
