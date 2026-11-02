-- Temporary fixture only. No real users or roster rows are changed.
begin;
do $$
declare
 u uuid := gen_random_uuid(); other_user uuid := gen_random_uuid();
 d uuid; kind text; dtype text; good jsonb; bad jsonb; rejected boolean;
 snapshot jsonb; after_failure jsonb; n integer;
begin
 insert into auth.users(id,email) values
 (u,'import-fixture-'||u||'@example.test'),
 (other_user,'import-fixture-'||other_user||'@example.test');
 perform set_config('request.jwt.claim.sub',u::text,true);
 execute 'set local role authenticated';
 for kind,dtype in values ('duties','base_roster'),('duties','10_day_amendment'),
 ('duties','7_day_amendment'),('duties','48_hour_amendment'),
 ('job_cards','job_card'),('annual_leave','annual_leave_roster') loop
   insert into public.roster_documents(user_id,storage_path,original_filename,file_size_bytes,detected_type)
   values(u,u||'/'||gen_random_uuid(),'fixture.pdf',1,dtype) returning id into d;
   if kind='duties' then
     good:=jsonb_build_object('duty_date','2098-01-01','source',
       case dtype when 'base_roster' then 'base_roster' when '10_day_amendment' then '10_day'
       when '7_day_amendment' then '7_day' else '48_hour' end,
       'duty_type','working','driver_number','TEST','unique_key','original');
   elsif kind='job_cards' then
     good:='{"turn_number":"1","original_turn_code":"1","day_code":"SX","plan_type":"ltp",
       "valid_from":"2098-01-01","valid_to":"2098-01-31","instructions":[],"unique_key":"original"}';
   else
     good:='{"leave_year":2098,"depot":"TEST","driver_number":"TEST","surname":"TEST",
       "block_number":1,"source":"official_roster","is_confirmed":true,"unique_key":"original",
       "periods":[{"period_type":"spring","start_date":"2098-01-01","end_date":"2098-01-07"}]}';
   end if;
   n:=public.replace_document_import(d,kind,jsonb_build_array(good));
   if n<>1 then raise exception 'Incorrect import count'; end if;
   -- Bad second row fails after a valid row; annual leave fails in nested periods.
   bad:=good||'{"unique_key":"bad"}';
   if kind='annual_leave' then
     bad:=jsonb_set(bad,'{periods,0,end_date}','"2097-01-01"');
   elsif kind='job_cards' then bad:=bad||'{"valid_to":"2097-01-01"}';
   else bad:=bad||'{"rostered_minutes":-1}'; end if;
   select jsonb_build_array(
     (select jsonb_agg(to_jsonb(r) order by r.id) from public.document_duties r where document_id=d),
     (select jsonb_agg(to_jsonb(r) order by r.id) from public.job_cards r where document_id=d),
     (select jsonb_agg(to_jsonb(r) order by r.id) from public.annual_leave_allocations r where document_id=d),
     (select jsonb_agg(to_jsonb(r) order by r.id) from public.annual_leave_periods r
       where r.allocation_id in(select id from public.annual_leave_allocations where document_id=d))
   ) into snapshot;
   rejected:=false;
   begin perform public.replace_document_import(d,kind,jsonb_build_array(good,bad));
   exception when others then rejected:=true; end;
   if not rejected then raise exception 'Invalid replacement accepted: %',dtype; end if;
   select jsonb_build_array(
     (select jsonb_agg(to_jsonb(r) order by r.id) from public.document_duties r where document_id=d),
     (select jsonb_agg(to_jsonb(r) order by r.id) from public.job_cards r where document_id=d),
     (select jsonb_agg(to_jsonb(r) order by r.id) from public.annual_leave_allocations r where document_id=d),
     (select jsonb_agg(to_jsonb(r) order by r.id) from public.annual_leave_periods r
       where r.allocation_id in(select id from public.annual_leave_allocations where document_id=d))
   ) into after_failure;
   if snapshot is distinct from after_failure then raise exception 'Failed replacement damaged records: %',dtype; end if;
   if not exists(select 1 from public.roster_documents where id=d and processing_status='processed')
   then raise exception 'Failed retry changed committed status'; end if;
   for bad in select value from jsonb_array_elements(jsonb_build_array('[]'::jsonb,'{}'::jsonb,'null'::jsonb,'[null]'::jsonb,jsonb_build_array(good,good))) loop
     rejected:=false;
     begin perform public.replace_document_import(d,kind,bad);
     exception when others then rejected:=true; end;
     if not rejected then raise exception 'Malformed/duplicate replacement accepted'; end if;
   end loop;
   perform set_config('request.jwt.claim.sub',other_user::text,true);
   rejected:=false;
   begin perform public.replace_document_import(d,kind,jsonb_build_array(good));
   exception when insufficient_privilege then rejected:=true; end;
   if not rejected then raise exception 'Other user replaced document'; end if;
   perform set_config('request.jwt.claim.sub',u::text,true);
   -- A successful retry replaces the entire old set, even beyond the former 250-row batch.
   select jsonb_agg(good||jsonb_build_object('unique_key','replacement-'||i)) into bad
     from generate_series(1,300) i;
   n:=public.replace_document_import(d,kind,bad);
   if n<>300 then raise exception 'Large import count wrong'; end if;
   if kind='duties' then select count(*) into n from public.document_duties where document_id=d;
   elsif kind='job_cards' then select count(*) into n from public.job_cards where document_id=d;
   else select count(*) into n from public.annual_leave_periods where allocation_id in
     (select id from public.annual_leave_allocations where document_id=d); end if;
   if n<>300 then raise exception 'Replacement incomplete: %',dtype; end if;
 end loop;
 if has_function_privilege('anon','public.replace_document_import(uuid,text,jsonb)','execute')
 then raise exception 'Anonymous execution allowed'; end if;
end $$;
rollback;
