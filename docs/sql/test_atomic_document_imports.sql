-- Run only after the migration is approved/applied. All fixtures roll back.
begin;
do $$
declare u uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid(); doc uuid; kind text; rows jsonb; broken jsonb; rejected boolean; n integer;
begin
 insert into auth.users(id,email) values
 (u,'import-fixture-'||u||'@example.test'),(other_user,'import-fixture-'||other_user||'@example.test');
 perform set_config('request.jwt.claim.sub',u::text,true);
 execute 'set local role authenticated';
 foreach kind in array array['duties','job_cards','annual_leave'] loop
  insert into public.roster_documents(user_id,storage_path,original_filename,file_size_bytes)
  values(u,u||'/fixture-'||kind,'fixture.pdf',100) returning id into doc;
  if kind='duties' then
   rows:='[{"duty_date":"2098-11-25","source":"48_hour","duty_type":"working","payroll_number":"fixture","unique_key":"fixture-duty","book_on":"22:00","book_off":"06:00"}]';
   broken:='[{"source":"48_hour","duty_type":"working","unique_key":"invalid"}]';
  elsif kind='job_cards' then
   rows:='[{"turn_number":"201","original_turn_code":"WO201","day_code":"SX","plan_type":"ltp","valid_from":"2098-01-01","valid_to":"2098-12-31","unique_key":"fixture-card","instructions":[]}]';
   broken:='[{"unique_key":"invalid"}]';
  else
   rows:='[{"leave_year":2098,"depot":"Fixture","driver_number":"fixture","surname":"Fixture","block_number":1,"source":"official_roster","is_confirmed":true,"unique_key":"fixture-leave","periods":[{"period_type":"spring","start_date":"2098-01-06","end_date":"2098-01-11"}]}]';
   broken:=jsonb_set(rows,'{0,periods,0,start_date}','null');
  end if;
  perform public.replace_document_import(doc,kind,rows);
  -- Retry must replace, not accumulate.
  perform public.replace_document_import(doc,kind,rows);
  rejected:=false;
  begin perform public.replace_document_import(doc,kind,broken);
  exception when others then rejected:=true; end;
  if not rejected then raise exception 'Invalid % import accepted',kind; end if;
  rejected:=false;
  begin perform public.replace_document_import(doc,kind,'[]');
  exception when others then rejected:=true; end;
  if not rejected then raise exception 'Empty import erased old rows'; end if;
  -- Simulate an interruption after the write, within a transaction.
  begin
   perform public.replace_document_import(doc,kind,rows);
   raise exception 'Fixture interruption';
  exception when others then null; end;
  if kind='duties' then select count(*) into n from public.document_duties where document_id=doc;
  elsif kind='job_cards' then select count(*) into n from public.job_cards where document_id=doc;
  else
   select count(*) into n from public.annual_leave_periods p join public.annual_leave_allocations a on a.id=p.allocation_id where a.document_id=doc;
  end if;
  if n<>1 then raise exception 'Failed/repeated % import damaged data',kind; end if;
  if not exists(select 1 from public.roster_documents where id=doc and processing_status='processed') then raise exception 'Status was not atomic'; end if;
  perform set_config('request.jwt.claim.sub',other_user::text,true);
  rejected:=false;
  begin perform public.replace_document_import(doc,kind,rows);
  exception when others then rejected:=true; end;
  if not rejected then raise exception 'Other account replaced document'; end if;
  perform set_config('request.jwt.claim.sub',u::text,true);
 end loop;
end $$;
rollback;
