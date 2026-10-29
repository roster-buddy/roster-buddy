alter table public.annual_leave_requests add column if not exists cancellation_pending boolean not null default false;

create or replace function public.action_floating_leave_cancellation(p_ids uuid[], p_action text)
returns void language plpgsql security invoker set search_path = public as $$
declare n integer; expected integer;
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
  update public.annual_leave_requests set
    cancellation_pending=(p_action='request'),
    status=case when p_action='confirm' then 'cancelled' else status end,
    queue_position=case when p_action='confirm' then null else queue_position end,
    decision_at=case when p_action='confirm' then now() else decision_at end,
    updated_at=now()
    where user_id=auth.uid() and id=any(p_ids) and status='granted' and request_type='floating';
end $$;
revoke all on function public.action_floating_leave_cancellation(uuid[],text) from public, anon;
grant execute on function public.action_floating_leave_cancellation(uuid[],text) to authenticated;
