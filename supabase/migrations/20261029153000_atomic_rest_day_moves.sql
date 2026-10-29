create or replace function public.action_rest_day_move(p_action text, p_pairs jsonb default null, p_id uuid default null)
returns uuid language plpgsql security invoker set search_path=public as $$
declare q public.shift_swaps%rowtype; pairs jsonb; item jsonb; result_id uuid; n integer; distinct_dates integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_action not in ('request','confirm','cancel') then raise exception 'Invalid action'; end if;
 if p_id is not null then
  select * into q from public.shift_swaps where id=p_id and user_id=auth.uid() for update;
  if not found or q.notes not like 'TYPE=Rest day move%' then raise exception 'Move not found'; end if;
  if q.status='approved' and p_action='confirm' then return q.id; end if;
  if q.status<>'pending' then raise exception 'Move is no longer pending'; end if;
  result_id:=q.id;
  pairs:=substring(q.notes from 'PAIRS=(.*)$')::jsonb;
 else pairs:=p_pairs;
 end if;
 n:=jsonb_array_length(pairs);
 if n not in (1,2) then raise exception 'Select one or two pairs'; end if;
 select count(distinct d) into distinct_dates from (
  select x->>'rest' d from jsonb_array_elements(pairs) x union all
  select x->>'work' d from jsonb_array_elements(pairs) x
 ) z;
 if distinct_dates<>2*n then raise exception 'Dates must be different'; end if;
 if exists(select 1 from jsonb_array_elements(pairs) x where
  (x->>'rest')::date-extract(dow from (x->>'rest')::date)::integer <>
  (pairs->0->>'rest')::date-extract(dow from (pairs->0->>'rest')::date)::integer)
 then raise exception 'Original Rest Days must be in the same week'; end if;
 for item in select * from jsonb_array_elements(pairs) loop
  if item->>'type' not in ('working','training','medical') or
    nullif(item->>'on','') is null or nullif(item->>'off','') is null
  then raise exception 'Replacement duty needs valid times'; end if;
 end loop;
 if result_id is null then
  insert into public.shift_swaps(user_id,original_date,requested_date,status,notes)
  values(auth.uid(),(pairs->0->>'rest')::date,(pairs->0->>'work')::date,'pending',
   'TYPE=Rest day move'||chr(10)||'CREATED_AT='||now()::text||chr(10)||'PAIRS='||pairs::text)
  returning id into result_id;
 end if;
 if p_action='confirm' then
  for item in select * from jsonb_array_elements(pairs) loop
   insert into public.manual_duties(user_id,duty_date,duty_type,manual_change_type,turn_number,book_on,book_off,rostered_minutes,remarks,original_source,original_duty_type,original_turn_number,original_book_on,original_book_off,updated_at)
   values(auth.uid(),(item->>'rest')::date,item->>'type','manual_change',nullif(item->>'turn',''),(item->>'on')::time,(item->>'off')::time,
    ((extract(epoch from (item->>'off')::time)-extract(epoch from (item->>'on')::time)+86400)::integer%86400)/60,
    'Agreed Rest Day move — duty moved from '||(item->>'work'),item->>'restSource','rest_day',null,null,null,now()),
   (auth.uid(),(item->>'work')::date,'rest_day','manual_change',null,null,null,null,
    'Agreed Rest Day moved from '||(item->>'rest'),item->>'workSource',item->>'type',nullif(item->>'turn',''),(item->>'on')::time,(item->>'off')::time,now())
   on conflict(user_id,duty_date,manual_change_type) do update set
    duty_type=excluded.duty_type,turn_number=excluded.turn_number,book_on=excluded.book_on,book_off=excluded.book_off,
    rostered_minutes=excluded.rostered_minutes,remarks=excluded.remarks,original_source=excluded.original_source,
    original_duty_type=excluded.original_duty_type,original_turn_number=excluded.original_turn_number,
    original_book_on=excluded.original_book_on,original_book_off=excluded.original_book_off,updated_at=now();
  end loop;
 end if;
 update public.shift_swaps set status=case when p_action='confirm' then 'approved' when p_action='cancel' then 'cancelled' else 'pending' end
  where id=result_id and user_id=auth.uid();
 return result_id;
end $$;
revoke all on function public.action_rest_day_move(text,jsonb,uuid) from public,anon;
grant execute on function public.action_rest_day_move(text,jsonb,uuid) to authenticated;