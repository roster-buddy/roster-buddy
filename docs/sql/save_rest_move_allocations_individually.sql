create or replace function public.allocate_rest_day_move(p_id uuid,p_pairs jsonb)
returns uuid language plpgsql security invoker set search_path=public as $$
declare q public.shift_swaps%rowtype; stored jsonb; item jsonb; complete boolean;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into q from public.shift_swaps where id=p_id and user_id=auth.uid() for update;
 if not found or q.notes not like 'TYPE=Rest day move%' or q.status<>'pending'
 or q.notes not like '%ALLOCATION_REQUIRED=true%' then raise exception 'Move is not awaiting allocation'; end if;
 stored:=substring(q.notes from 'PAIRS=(.*)$')::jsonb;
 if p_pairs is null or jsonb_array_length(p_pairs) not between 1 and 2 then raise exception 'Select a working date'; end if;
 if (select count(distinct x->>'rest') from jsonb_array_elements(p_pairs) x)<>jsonb_array_length(p_pairs) then raise exception 'Duplicate allocation'; end if;
 for item in select * from jsonb_array_elements(p_pairs) loop
  if not exists(select 1 from jsonb_array_elements(stored) x where x->>'rest'=item->>'rest')
    or nullif(item->>'on','') is null or nullif(item->>'off','') is null then raise exception 'Invalid allocation'; end if;
  update public.manual_duties set duty_type='working',turn_number=nullif(item->>'turn',''),
    book_on=(item->>'on')::time,book_off=(item->>'off')::time,
    rostered_minutes=((extract(epoch from (item->>'off')::time)-extract(epoch from (item->>'on')::time)+86400)::integer%86400)/60,
    remarks='Allocated following confirmed Rest Day move',updated_at=now()
   where user_id=auth.uid() and duty_date=(item->>'rest')::date and manual_change_type='manual_change';
  if not found then raise exception 'New working day not found'; end if;
  select jsonb_agg(case when x->>'rest'=item->>'rest' then x||'{"allocated":true}'::jsonb else x end order by ord)
    into stored from jsonb_array_elements(stored) with ordinality t(x,ord);
 end loop;
 complete:=not exists(select 1 from jsonb_array_elements(stored) x where coalesce((x->>'allocated')::boolean,false)=false);
 update public.shift_swaps set status=case when complete then 'approved' else 'pending' end,
 notes=replace(left(notes,strpos(notes,'PAIRS=')-1),'ALLOCATION_REQUIRED=true',
   case when complete then 'ALLOCATION_REQUIRED=false' else 'ALLOCATION_REQUIRED=true' end)||'PAIRS='||stored::text
 where id=p_id and user_id=auth.uid();
 return p_id;
end $$;
revoke all on function public.allocate_rest_day_move(uuid,jsonb) from public,anon;
grant execute on function public.allocate_rest_day_move(uuid,jsonb) to authenticated;