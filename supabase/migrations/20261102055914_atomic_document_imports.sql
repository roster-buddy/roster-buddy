-- One RPC is one transaction. RLS remains active; serialize retries on the
-- owning document so concurrent replacements cannot mix their rows.
create or replace function public.replace_document_import(
  p_document_id uuid, p_kind text, p_rows jsonb
) returns integer
language plpgsql security invoker set search_path = ''
as $$
declare
  document_type text;
  allocation jsonb;
  new_allocation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in before importing a document' using errcode = '42501';
  end if;
  select d.detected_type into document_type
    from public.roster_documents d
    where d.id = p_document_id and d.user_id = auth.uid()
    for update;
  if not found then
    raise exception 'Document unavailable or not owned by you' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Import records must be an array';
  end if;
  if jsonb_array_length(p_rows) = 0 then
    raise exception 'Empty replacement rejected; existing records kept';
  end if;
  if exists (select 1 from jsonb_array_elements(p_rows) x where jsonb_typeof(x) <> 'object') then
    raise exception 'Each import record must be an object';
  end if;
  if p_kind = 'duties' and document_type in
      ('base_roster','10_day_amendment','7_day_amendment','48_hour_amendment') then
    if exists (
      select 1 from jsonb_array_elements(p_rows) x
      where (x->>'source') is distinct from
        case document_type when 'base_roster' then 'base_roster'
          when '10_day_amendment' then '10_day'
          when '7_day_amendment' then '7_day' else '48_hour' end
    ) then raise exception 'Duty source does not match document type'; end if;
    delete from public.document_duties where document_id = p_document_id;
    insert into public.document_duties (document_id, duty_date, source, duty_type, turn_number, book_on, book_off, rostered_minutes, remarks, driver_number, payroll_number, driver_name, depot, amendment_code, mileage, page_number, raw_text, unique_key)
    select p_document_id, r.duty_date, r.source, r.duty_type, r.turn_number, r.book_on, r.book_off, r.rostered_minutes, r.remarks, r.driver_number, r.payroll_number, r.driver_name, r.depot, r.amendment_code, r.mileage, r.page_number, r.raw_text, r.unique_key
    from jsonb_populate_recordset(null::public.document_duties, p_rows) r;
  elsif p_kind = 'job_cards' and document_type = 'job_card' then
    delete from public.job_cards where document_id = p_document_id;
    insert into public.job_cards (document_id, turn_number, original_turn_code, day_code, plan_type, valid_from, valid_to, book_on, book_off, rostered_minutes, page_number, raw_text, instructions, unique_key)
    select p_document_id, r.turn_number, r.original_turn_code, r.day_code, r.plan_type, r.valid_from, r.valid_to, r.book_on, r.book_off, r.rostered_minutes, r.page_number, r.raw_text, r.instructions, r.unique_key
    from jsonb_populate_recordset(null::public.job_cards, p_rows) r;
  elsif p_kind = 'annual_leave' and document_type = 'annual_leave_roster' then
    delete from public.annual_leave_allocations where document_id = p_document_id;
    for allocation in select value from jsonb_array_elements(p_rows) loop
      if jsonb_typeof(allocation->'periods') is distinct from 'array' then
        raise exception 'Annual leave periods must be an array';
      end if;
      insert into public.annual_leave_allocations (document_id, leave_year, depot, driver_number, surname, block_number, source, original_block_number, other_driver_number, other_driver_surname, swap_reference, is_confirmed, page_number, unique_key)
    select p_document_id, r.leave_year, r.depot, r.driver_number, r.surname, r.block_number, r.source, r.original_block_number, r.other_driver_number, r.other_driver_surname, r.swap_reference, r.is_confirmed, r.page_number, r.unique_key
    from jsonb_populate_recordset(null::public.annual_leave_allocations, jsonb_build_array(allocation)) r returning id into new_allocation_id;
      insert into public.annual_leave_periods
        (allocation_id, period_type, start_date, end_date)
        select new_allocation_id, r.period_type, r.start_date, r.end_date
        from jsonb_populate_recordset(null::public.annual_leave_periods, allocation->'periods') r;
    end loop;
  else
    raise exception 'Import kind does not match document type';
  end if;
  update public.roster_documents set processing_status = 'processed'
    where id = p_document_id and user_id = auth.uid();
  return jsonb_array_length(p_rows);
end;
$$;
revoke all on function public.replace_document_import(uuid, text, jsonb) from public, anon;
grant execute on function public.replace_document_import(uuid, text, jsonb) to authenticated;
