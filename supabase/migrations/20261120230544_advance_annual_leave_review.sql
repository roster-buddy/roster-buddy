alter table public.annual_leave_scheduled_requests
  drop constraint annual_leave_scheduled_requests_status_check,
  alter column status drop default,
  add constraint annual_leave_scheduled_requests_status_check
    check (status in ('manual_review', 'sent', 'cancelled', 'failed')) not valid;

update public.annual_leave_scheduled_requests
set status = 'manual_review',
    scheduled_for = ((leave_date - 365)::timestamp at time zone 'Europe/London')
where status = 'scheduled';

alter table public.annual_leave_scheduled_requests
  validate constraint annual_leave_scheduled_requests_status_check;

create unique index if not exists annual_leave_advance_active_date_key
  on public.annual_leave_scheduled_requests (user_id, leave_date)
  where status = 'manual_review';

create index if not exists annual_leave_advance_review_due_idx
  on public.annual_leave_scheduled_requests (user_id, scheduled_for)
  where status = 'manual_review';

revoke execute on function public.schedule_annual_leave_email(date, text, text, text, text)
  from public, anon, authenticated;

create or replace function public.track_advance_annual_leave(
  p_leave_date date,
  p_recipient_email text,
  p_email_subject text,
  p_email_body text,
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid;
  v_id uuid;
  v_today date;
  v_scheduled_for timestamptz;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'You must be signed in before tracking annual leave.';
  end if;

  if extract(isodow from p_leave_date) = 7 then
    raise exception 'Annual leave cannot be requested for a Sunday.';
  end if;

  v_today := (now() at time zone 'Europe/London')::date;

  if p_leave_date <= v_today + 365 then
    raise exception
      'This annual leave date is already within the 365-day request window.';
  end if;

  if nullif(trim(p_recipient_email), '') is null then
    raise exception 'Recipient email is required.';
  end if;

  if nullif(trim(p_email_subject), '') is null then
    raise exception 'Email subject is required.';
  end if;

  if nullif(trim(p_email_body), '') is null then
    raise exception 'Email body is required.';
  end if;

  v_scheduled_for :=
    ((p_leave_date - 365)::timestamp at time zone 'Europe/London');

  insert into public.annual_leave_scheduled_requests (
    user_id,
    leave_date,
    scheduled_for,
    recipient_email,
    email_subject,
    email_body,
    notes,
    status
  )
  values (
    v_user_id,
    p_leave_date,
    v_scheduled_for,
    trim(p_recipient_email),
    p_email_subject,
    p_email_body,
    nullif(trim(p_notes), ''),
    'manual_review'
  )
  on conflict (user_id, leave_date) where status = 'manual_review'
  do update set recipient_email = excluded.recipient_email,
                email_subject = excluded.email_subject,
                email_body = excluded.email_body,
                updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.track_advance_annual_leave(
  date,
  text,
  text,
  text,
  text
) to authenticated;

create or replace function public.record_advance_annual_leave_outcome(
  p_leave_date date,
  p_in_abeyance boolean default false
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
    and status = 'manual_review'
  for update;

  if v_scheduled_id is null then
    raise exception 'There is no advance annual leave request for this date.';
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
    and leave_year = extract(year from p_leave_date)::integer
  for update;

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
    and status = 'granted'
    and leave_date <> p_leave_date;

  if not p_in_abeyance and v_committed >= v_total_available then
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
    case when p_in_abeyance then 'abeyance' else 'granted' end,
    'floating',
    now(),
    now(),
    v_notes,
    null,
    now()
  )
  on conflict (user_id, leave_date, request_type)
  do update set
    status = excluded.status,
    requested_at = now(),
    decision_at = now(),
    notes = excluded.notes,
    queue_position = null,
    updated_at = now()
  where not p_in_abeyance or annual_leave_requests.status <> 'granted'
  returning id into v_request_id;

  if v_request_id is null then
    raise exception 'This annual leave date has already been granted.';
  end if;

  update public.annual_leave_scheduled_requests
  set status = 'cancelled',
      error_message = null,
      updated_at = now()
  where id = v_scheduled_id
    and user_id = v_user_id
    and status = 'manual_review';

  return v_request_id;
end;
$$;

grant execute on function public.record_advance_annual_leave_outcome(date, boolean)
to authenticated;
