alter table public.annual_leave_scheduled_requests
  add column if not exists recipient_email text,
  add column if not exists email_subject text,
  add column if not exists email_body text;

create or replace function public.schedule_annual_leave_email(
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
    raise exception 'You must be signed in before scheduling annual leave.';
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

  select id
  into v_id
  from public.annual_leave_scheduled_requests
  where user_id = v_user_id
    and leave_date = p_leave_date
    and status = 'scheduled'
  limit 1;

  if v_id is not null then
    update public.annual_leave_scheduled_requests
    set scheduled_for = v_scheduled_for,
        recipient_email = trim(p_recipient_email),
        email_subject = p_email_subject,
        email_body = p_email_body,
        notes = nullif(trim(p_notes), ''),
        sent_at = null,
        error_message = null,
        updated_at = now()
    where id = v_id
      and user_id = v_user_id;

    return v_id;
  end if;

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
    'scheduled'
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.schedule_annual_leave_email(
  date,
  text,
  text,
  text,
  text
) to authenticated;
