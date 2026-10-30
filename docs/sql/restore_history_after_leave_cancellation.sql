-- Keep a chosen historical shift until cancellation is approved.
alter table public.annual_leave_requests
  add column if not exists history_restore jsonb;

create or replace function public.action_floating_leave_cancellation(p_ids uuid[], p_action text)
returns void language plpgsql security invoker set search_path = public as $$
declare n integer; expected integer; r record; d jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in before changing leave'; end if;
  if p_action not in ('request','confirm','retain') then raise exception 'Invalid cancellation action'; end if;
  select count(distinct x) into expected from unnest(p_ids) x;
  if expected = 0 then raise exception 'Select at least one date'; end if;
  perform id from public.annual_leave_requests
    where user_id=auth.uid() and id=any(p_ids) and status='granted' and request_type='floating'
    order by id for update;
  select count(*) into n from public.annual_leave_requests
    where user_id=auth.uid() and id=any(p_ids) and status='granted' and request_type='floating';
  if n <> expected then raise exception 'Some selected leave has changed. Refresh and select the dates again.'; end if;
  if p_action='confirm' then
    for r in select leave_date,history_restore from public.annual_leave_requests
      where user_id=auth.uid() and id=any(p_ids) and history_restore is not null
    loop
      d := r.history_restore;
      if jsonb_typeof(d) <> 'object' or (d->>'duty_type') is null
        or (d->>'duty_type') not in ('working','training','medical')
        or (d->>'duty_date') is distinct from r.leave_date::text
        or nullif(d->>'book_on','') is null or nullif(d->>'book_off','') is null
      then raise exception 'Invalid historical shift'; end if;
      insert into public.manual_duties (
        user_id,duty_date,manual_change_type,duty_type,turn_number,book_on,book_off,
        rostered_minutes,remarks,original_source,original_duty_type,original_turn_number,
        original_book_on,original_book_off,updated_at
      ) values (
        auth.uid(),r.leave_date,'manual_change',d->>'duty_type',d->>'turn_number',
        (d->>'book_on')::time,(d->>'book_off')::time,(d->>'rostered_minutes')::integer,
        d->>'remarks',d->>'original_source',d->>'original_duty_type',d->>'original_turn_number',
        (d->>'original_book_on')::time,(d->>'original_book_off')::time,now()
      ) on conflict (user_id,duty_date,manual_change_type) do update set
        duty_type=excluded.duty_type,turn_number=excluded.turn_number,
        book_on=excluded.book_on,book_off=excluded.book_off,rostered_minutes=excluded.rostered_minutes,
        remarks=excluded.remarks,original_source=excluded.original_source,
        original_duty_type=excluded.original_duty_type,original_turn_number=excluded.original_turn_number,
        original_book_on=excluded.original_book_on,original_book_off=excluded.original_book_off,updated_at=now();
    end loop;
  end if;
  update public.annual_leave_requests set
    cancellation_pending=(p_action='request'),
    status=case when p_action='confirm' then 'cancelled' else status end,
    queue_position=case when p_action='confirm' then null else queue_position end,
    decision_at=case when p_action='confirm' then now() else decision_at end,
    history_restore=case when p_action='request' then history_restore else null end,
    updated_at=now()
    where user_id=auth.uid() and id=any(p_ids) and status='granted' and request_type='floating';
end $$;

create or replace function public.cancel_leave_for_history(p_id uuid,p_action text,p_restore jsonb)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in before changing leave'; end if;
  if p_action not in ('request','confirm') then raise exception 'Invalid cancellation action'; end if;
  update public.annual_leave_requests set history_restore=p_restore
    where id=p_id and user_id=auth.uid() and status='granted' and request_type='floating';
  if not found then raise exception 'Annual leave has changed. Refresh and try again.'; end if;
  perform public.action_floating_leave_cancellation(array[p_id],p_action);
end $$;
revoke all on function public.action_floating_leave_cancellation(uuid[],text) from public,anon;
grant execute on function public.action_floating_leave_cancellation(uuid[],text) to authenticated;
revoke all on function public.cancel_leave_for_history(uuid,text,jsonb) from public,anon;
grant execute on function public.cancel_leave_for_history(uuid,text,jsonb) to authenticated;
