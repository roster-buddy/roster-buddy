-- Roster Buddy annual leave workflow:
-- requested -> abeyance -> granted
-- or requested/abeyance/granted -> cancelled.
--
-- There is deliberately no "refused" state. If leave cannot currently
-- be granted it is held in abeyance with a queue position.

update public.annual_leave_requests
set status = 'abeyance'
where status = 'refused';

alter table public.annual_leave_requests
  drop constraint if exists annual_leave_requests_status_check;

alter table public.annual_leave_requests
  add constraint annual_leave_requests_status_check
  check (
    status in (
      'requested',
      'abeyance',
      'granted',
      'cancelled'
    )
  );

alter table public.annual_leave_requests
  add column if not exists queue_position integer;

alter table public.annual_leave_requests
  drop constraint if exists annual_leave_requests_queue_position_check;

alter table public.annual_leave_requests
  add constraint annual_leave_requests_queue_position_check
  check (
    queue_position is null
    or queue_position > 0
  );

comment on column public.annual_leave_requests.queue_position is
  'Driver position in the annual leave abeyance queue. Null when not in abeyance or when position is not yet known.';
