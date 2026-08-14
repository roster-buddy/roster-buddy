alter table public.annual_leave_block_pending_actions
  add column if not exists recipient_email text,
  add column if not exists email_subject text,
  add column if not exists email_body text,
  add column if not exists scheduled_for timestamptz,
  add column if not exists sent_at timestamptz,
  add column if not exists error_message text;

alter table public.annual_leave_block_pending_actions
  drop constraint if exists annual_leave_block_pending_actions_status_check;

alter table public.annual_leave_block_pending_actions
  add constraint annual_leave_block_pending_actions_status_check
  check (
    status in (
      'awaiting_union',
      'scheduled',
      'ready_to_send',
      'sent',
      'confirmed',
      'cancelled',
      'failed'
    )
  );

create index if not exists
  annual_leave_block_pending_actions_due_idx
on public.annual_leave_block_pending_actions (scheduled_for)
where status = 'scheduled';

comment on column public.annual_leave_block_pending_actions.scheduled_for is
  'UTC send time for a future block leave request, normally midnight Europe/London on 1 October before the leave year.';

comment on column public.annual_leave_block_pending_actions.recipient_email is
  'Union recipient for block leave exchange requests.';

comment on column public.annual_leave_block_pending_actions.email_subject is
  'Prepared email subject for the block leave request.';

comment on column public.annual_leave_block_pending_actions.email_body is
  'Prepared email body for the block leave request.';
