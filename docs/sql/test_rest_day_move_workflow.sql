-- Regression fixture: creates temporary accounts/rows and rolls everything back.
begin;
do $$
declare
 u uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid(); q uuid;
 mon date:=date_trunc('week',date '2098-11-25')::date;
 pairs jsonb; bad jsonb; rejected boolean;
begin
 insert into auth.users(id,email) values
 (u,'rest-fixture-'||u||'@example.test'),(other_user,'rest-fixture-'||other_user||'@example.test');
 perform set_config('request.jwt.claim.sub',u::text,true);
 execute 'set local role authenticated';
 pairs:=jsonb_build_array(
   jsonb_build_object('rest',(mon+2)::text,'work',mon::text,'type','working','on','06:00','off','14:00','turn','original-1'),
   jsonb_build_object('rest',(mon+3)::text,'work',(mon+1)::text,'type','working','on','07:00','off','15:00','turn','original-2'));
 q:=public.action_rest_day_move('request',pairs,null);
 if exists(select 1 from public.manual_duties where user_id=u) then raise exception 'Pending move altered roster'; end if;
 perform public.action_rest_day_move('confirm',null,q);
 if (select count(*) from public.manual_duties where user_id=u and duty_type='rest_day')<>2
 or (select count(*) from public.manual_duties where user_id=u and duty_type='unknown' and book_on is null and turn_number is null)<>2
 then raise exception 'Confirmation copied old shifts or failed to move rest days'; end if;
 perform public.allocate_rest_day_move(q,jsonb_build_array(jsonb_build_object('rest',(mon+2)::text,'on','22:15','off','06:30','turn','new-1')));
 if not exists(select 1 from public.shift_swaps where id=q and status='pending')
 or not exists(select 1 from public.manual_duties where user_id=u and duty_date=mon+2 and turn_number='new-1' and rostered_minutes=495)
 or not exists(select 1 from public.manual_duties where user_id=u and duty_date=mon+3 and duty_type='unknown')
 then raise exception 'Individual save or overnight calculation failed'; end if;
 rejected:=false;
 begin
  perform public.allocate_rest_day_move(q,jsonb_build_array(jsonb_build_object('rest',(mon+3)::text,'on','invalid','off','15:00')));
 exception when others then rejected:=true; end;
 if not rejected or not exists(select 1 from public.manual_duties where user_id=u and duty_date=mon+2 and turn_number='new-1') then raise exception 'Failed allocation damaged saved date'; end if;
 perform set_config('request.jwt.claim.sub',other_user::text,true);
 rejected:=false;
 begin perform public.allocate_rest_day_move(q,jsonb_build_array(jsonb_build_object('rest',(mon+3)::text,'on','07:00','off','15:00')));
 exception when others then rejected:=true; end;
 if not rejected then raise exception 'Other account allocated work'; end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 perform public.allocate_rest_day_move(q,jsonb_build_array(jsonb_build_object('rest',(mon+3)::text,'on','07:00','off','15:00','turn','new-2')));
 if not exists(select 1 from public.shift_swaps where id=q and status='approved' and notes like '%ALLOCATION_REQUIRED=false%') then raise exception 'Completed queue not cleared'; end if;
 perform public.action_rest_day_move('confirm',null,q);
 if not exists(select 1 from public.manual_duties where user_id=u and duty_date=mon+2 and turn_number='new-1') then raise exception 'Repeat confirmation erased allocation'; end if;
 for bad in select value from jsonb_array_elements(jsonb_build_array(
   jsonb_set(pairs,'{0,rest}',to_jsonb((mon-1)::text)),
   jsonb_set(pairs,'{0,work}',to_jsonb((mon+7)::text)),
   jsonb_set(pairs,'{1,rest}',to_jsonb((mon+2)::text)),
   jsonb_set(pairs,'{0,type}','null'::jsonb),
   jsonb_set(pairs,'{0,work}','null'::jsonb)
 )) loop
  rejected:=false;
  begin perform public.action_rest_day_move('request',bad,null);
  exception when others then rejected:=true; end;
  if not rejected then raise exception 'Invalid dates/type accepted: %',bad; end if;
 end loop;
end $$;
rollback;
