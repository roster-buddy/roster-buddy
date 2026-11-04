begin;
do $test$
declare who uuid:=gen_random_uuid(); day date; starts timestamp; d jsonb; got record;
 n integer; before_count integer; after_count integer;
begin
 insert into auth.users(id,email) values(who,'reminder-fixture-'||who::text||'@example.invalid');
 insert into public.driver_profiles(user_id,payroll_number,driver_number,roster_number,shift_reminder_minutes)
 values(who,'99999997','99999997','99999997',array[15,30,120])
 on conflict(user_id) do update set shift_reminder_minutes=excluded.shift_reminder_minutes;
 starts:=(date_trunc('minute',now()) at time zone 'Europe/London')+interval '30 minutes';
 day:=starts::date;
 insert into public.manual_duties(user_id,duty_date,duty_type,manual_change_type,book_on,book_off,turn_number)
 values(who,day,'working','edited_times',starts::time,(starts+interval '8 hours')::time,'215');
 select count(*) into n from roster_private.shift_reminder_candidates(who,now());
 if n<>4 then raise exception 'Expected three starts and one finish, got %',n; end if;
 select * into got from roster_private.shift_reminder_candidates(who,now()) where kind='shift_finish';
 if got.due_at is distinct from ((starts+interval '8 hours 5 minutes') at time zone 'Europe/London')
 then raise exception 'Finish + five minutes incorrect'; end if;
 update public.driver_profiles set shift_reminder_minutes='{}' where user_id=who;
 select count(*) into n from roster_private.shift_reminder_candidates(who,now());
 if n<>1 then raise exception 'Empty advance selection must preserve fixed finish check'; end if;
 update public.driver_profiles set shift_reminder_minutes=array[30] where user_id=who;
 insert into public.roster_push_subscriptions(user_id,endpoint,subscription)
 values(who,'https://web.push.apple.com/reminder-fixture-'||who::text,
   jsonb_build_object('endpoint','https://web.push.apple.com/reminder-fixture-'||who::text,'keys',jsonb_build_object('p256dh','fixture','auth','fixture')));
 update roster_private.shift_reminder_control set enabled=true;
 perform roster_private.queue_due_shift_reminders();
 select count(*) into before_count from public.roster_push_events where user_id=who and kind='shift_start';
 perform roster_private.queue_due_shift_reminders();
 select count(*) into after_count from public.roster_push_events where user_id=who and kind='shift_start';
 if before_count<>1 or after_count<>1 then raise exception 'Reminder queue is not idempotent'; end if;
 -- A granted leave day suppresses even a retained working record.
 insert into public.annual_leave_requests(user_id,leave_date,status,request_type)
 values(who,day,'granted','floating');
 if roster_private.effective_shift_for_reminder(who,day) is not null then raise exception 'Granted leave did not suppress work'; end if;
 delete from public.annual_leave_requests where user_id=who;
 update public.manual_duties set duty_type='rest_day' where user_id=who;
 select count(*) into n from roster_private.shift_reminder_candidates(who,now());
 if n<>0 then raise exception 'Rest day generated reminders'; end if;
 -- Overnight reminder belongs to the shift start date and uses the next day's UK offset.
 delete from public.manual_duties where user_id=who;
 insert into public.manual_duties(user_id,duty_date,duty_type,manual_change_type,book_on,book_off,turn_number)
 values(who,'2026-10-24','working','edited_times','17:11','01:31','215');
 select * into got from roster_private.shift_reminder_candidates(who,'2026-10-25 01:36:00+00') where kind='shift_finish';
 if got.due_at is distinct from '2026-10-25 01:36:00+00'::timestamptz or got.duty_date<>'2026-10-24'::date
 then raise exception 'Overnight / autumn clock change incorrect'; end if;
 if got.target_url<>'?shift=2026-10-24&bookOff=1' then raise exception 'Wrong shift date in reminder link'; end if;
 delete from public.manual_duties where user_id=who;
 insert into public.manual_duties(user_id,duty_date,duty_type,manual_change_type,book_on,book_off,turn_number)
 values(who,'2026-06-01','working','edited_times','12:00','20:00','215');
 select * into got from roster_private.shift_reminder_candidates(who,'2026-06-01 10:30:00+00') where kind='shift_start';
 if got.due_at is distinct from '2026-06-01 10:30:00+00'::timestamptz
 then raise exception 'British Summer Time offset incorrect'; end if;
end $test$;
rollback;
select 'PASS: multiple offsets, permanent finish, idempotency, leave/rest suppression, overnight and BST/GMT' as result;

begin;
do $test$
declare who uuid:=gen_random_uuid(); starts timestamp; ends timestamp; day date;
 claimed jsonb; old_event uuid; n integer;
begin
 insert into auth.users(id,email) values(who,'reminder-delivery-'||who::text||'@example.invalid');
 insert into public.driver_profiles(user_id,shift_reminder_minutes) values(who,array[30])
 on conflict(user_id) do update set shift_reminder_minutes=array[30];
 insert into public.roster_push_subscriptions(user_id,endpoint,subscription)
 values(who,'https://web.push.apple.com/reminder-delivery-'||who::text,
   jsonb_build_object('endpoint','https://web.push.apple.com/reminder-delivery-'||who::text,'keys',jsonb_build_object('p256dh','fixture','auth','fixture')));
 update roster_private.shift_reminder_control set enabled=true;
 starts:=(date_trunc('minute',now()) at time zone 'Europe/London')+interval '30 minutes';
 day:=starts::date;
 insert into public.manual_duties(user_id,duty_date,duty_type,manual_change_type,book_on,book_off,turn_number)
 values(who,day,'working','edited_times',starts::time,(starts+interval '8 hours')::time,'215');
 perform roster_private.queue_due_shift_reminders();
 select id into old_event from public.roster_push_events where user_id=who and kind='shift_start';
 -- Change shift before deliveries have even been inserted: the old event must not get claimed.
 update public.manual_duties set book_on=(starts+interval '1 hour')::time where user_id=who;
 claimed:=roster_private.claim_push_deliveries();
 if exists(select 1 from public.roster_push_deliveries where event_id=old_event and status='sending')
 then raise exception 'Old reminder was claimed after shift changed'; end if;
 delete from public.manual_duties where user_id=who;
 ends:=(date_trunc('minute',now()) at time zone 'Europe/London')-interval '5 minutes';
 starts:=ends-interval '8 hours';
 day:=starts::date;
 insert into public.manual_duties(user_id,duty_date,duty_type,manual_change_type,book_on,book_off,turn_number)
 values(who,day,'working','edited_times',starts::time,ends::time,'215');
 claimed:=roster_private.claim_push_deliveries();
 update public.roster_push_deliveries d set status='sent' from public.roster_push_events e
 where e.id=d.event_id and e.user_id=who and e.kind='shift_finish';
 select count(*) into n from public.roster_push_events where user_id=who and kind='shift_finish';
 if n<>1 then raise exception 'Expected one fixed finish event'; end if;
 update public.manual_duties set book_on=(starts-interval '1 minute')::time where user_id=who;
 perform roster_private.queue_due_shift_reminders();
 select count(*) into n from public.roster_push_events where user_id=who and kind='shift_finish';
 if n<>1 then raise exception 'Book-off check repeated after time edit'; end if;
 begin
  update public.driver_profiles set shift_reminder_minutes=array[7] where user_id=who;
  raise exception 'Invalid preference accepted';
 exception when check_violation then null;
 end;
 if has_function_privilege('authenticated','roster_private.queue_due_shift_reminders()','EXECUTE')
 then raise exception 'Client can queue server notifications'; end if;
end $test$;
rollback;
select 'PASS: stale delivery cancellation, one finish check, preference validation and server-only queue' as result;