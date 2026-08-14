create or replace function public.confirm_scheduled_annual_leave_granted(
  p_leave_date date
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid;
  v_scheduled_id uuid;
  v_request_id uuid;
  v_notes text;
  v_total_available integer;
  v_committed integer;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'You must be signed in before changing annual leave.';
  end if;

  select id, notes
  into v_scheduled_id, v_notes
  from public.annual_leave_scheduled_requests
  where user_id = v_user_id
    and leave_date = p_leave_date
    and status = 'scheduled'
  for update;

  if v_scheduled_id is null then
    raise exception 'There is no queued annual leave request for this date.';
  end if;

  insert into public.annual_leave_balances (
    user_id,
    leave_year,
    entitlement_days,
    starting_balance_days,
    carry_over_days
  )
  values (
    v_user_id,
    extract(year from p_leave_date)::integer,
    14,
    14,
    0
  )
  on conflict (user_id, leave_year) do nothing;

  select
    starting_balance_days
      + coalesce(bonus_days, 0)
      + coalesce(carry_over_days, 0)
      + coalesce(lieu_days, 0)
  into v_total_available
  from public.annual_leave_balances
  where user_id = v_user_id
    and leave_year = extract(year from p_leave_date)::integer;

  select count(*)::integer
  into v_committed
  from public.annual_leave_requests
  where user_id = v_user_id
    and request_type = 'floating'
    and leave_date >= make_date(
      extract(year from p_leave_date)::integer,
      1,
      1
    )
    and leave_date <= make_date(
      extract(year from p_leave_date)::integer,
      12,
      31
    )
    and status in ('requested', 'abeyance', 'granted')
    and leave_date <> p_leave_date;

  if v_committed >= v_total_available then
    raise exception
      'You do not have any floating annual leave days remaining.';
  end if;

  insert into public.annual_leave_requests (
    user_id,
    leave_date,
    status,
    request_type,
    requested_at,
    decision_at,
    notes,
    queue_position,
    updated_at
  )
  values (
    v_user_id,
    p_leave_date,
    'granted',
    'floating',
    now(),
    now(),
    v_notes,
    null,
    now()
  )
  on conflict (user_id, leave_date, request_type)
  do update set
    status = 'granted',
    requested_at = now(),
    decision_at = now(),
    notes = excluded.notes,
    queue_position = null,
    updated_at = now()
  returning id into v_request_id;

  update public.annual_leave_scheduled_requests
  set status = 'cancelled',
      error_message = null,
      updated_at = now()
  where id = v_scheduled_id
    and user_id = v_user_id
    and status = 'scheduled';

  return v_request_id;
end;
$$;

grant execute on function public.confirm_scheduled_annual_leave_granted(date)
to authenticated;
