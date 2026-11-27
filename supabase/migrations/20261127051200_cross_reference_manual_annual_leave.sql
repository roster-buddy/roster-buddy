alter table public.roster_push_events
  drop constraint roster_push_events_kind_check,
  add constraint roster_push_events_kind_check check (kind in (
    'allocated', 'changed', 'leave_conflict', 'leave_confirmed', 'test',
    'shift_start', 'shift_finish', 'base_roster_action', 'subscription_renewal'
  ));

create or replace function roster_private.queue_completed_roster_push() returns trigger
language plpgsql security definer set search_path='' as $$
declare rec record; old_sig text; new_sig text; conflict_leave boolean; manual_leave boolean; confirmed_leave boolean;
        latest_sheet uuid; event_kind text; signature text;
begin
 if auth.uid() is not null and auth.uid()<>new.user_id then raise exception 'Uploader required'; end if;
 if auth.uid() is null and session_user<>'postgres' and coalesce(current_setting('request.jwt.claims',true),'') not like '%service_role%' then raise exception 'Authenticated processing required'; end if;
 for rec in
   select distinct on (p.user_id,d.duty_date) p.user_id,d.duty_date,d.duty_type,d.turn_number,d.book_on,d.book_off,d.source,d.amendment_code,p.payroll_number,p.depot
   from public.document_duties d join public.driver_profiles p on (roster_private.pay_matches(d.payroll_number,p.payroll_number)
     or (d.source='base_roster' and trim(d.driver_number)=trim(p.roster_number)))
   where d.document_id=new.id
     and (p.user_id=new.user_id or (d.source<>'base_roster' and lower(trim(p.depot))=new.depot))
     and d.source in ('base_roster','10_day','7_day','48_hour')
   order by p.user_id,d.duty_date,case d.source when '48_hour' then 4 when '7_day' then 3 when '10_day' then 2 else 1 end desc,d.created_at desc,d.id desc
 loop
   select s.signature into old_sig from roster_private.push_state s where s.user_id=rec.user_id and s.duty_date=rec.duty_date for update;
   if old_sig is null then old_sig:=roster_private.best_roster_signature(rec.user_id,rec.duty_date,new.id); end if;
   new_sig:=roster_private.best_roster_signature(rec.user_id,rec.duty_date);
   manual_leave := rec.source <> 'base_roster' and coalesce((
     select m.duty_type = 'annual_leave'
     from public.manual_duties m
     where m.user_id = rec.user_id and m.duty_date = rec.duty_date
     order by m.updated_at desc,
       case m.manual_change_type when 'manual_change' then 4 when 'edited_times' then 3
         when 'selected_turn' then 2 when 'rest_day_worked' then 1 else 0 end desc,
       m.id desc
     limit 1
   ), false);
   confirmed_leave := false;
   if manual_leave then
     select d.document_id into latest_sheet
     from public.document_duties d
     join public.roster_documents r on r.id = d.document_id
     where d.duty_date = rec.duty_date
       and d.source in ('10_day', '7_day', '48_hour')
       and r.processing_status = 'processed'
       and (r.user_id = rec.user_id or r.depot = lower(trim(rec.depot)))
       and roster_private.pay_matches(d.payroll_number, rec.payroll_number)
     order by case d.source when '48_hour' then 3 when '7_day' then 2 else 1 end desc,
       d.created_at desc, d.id desc
     limit 1;
     confirmed_leave := latest_sheet = new.id and rec.duty_type = 'annual_leave';
     conflict_leave := latest_sheet = new.id and rec.duty_type in
       ('working','training','medical','rest_day','sick','public_holiday','unavailable');
   else
     conflict_leave := rec.source <> 'base_roster' and rec.duty_type in
       ('working','training','medical') and roster_private.recorded_annual_leave(rec.user_id,rec.duty_date);
   end if;
   if confirmed_leave or conflict_leave or old_sig is distinct from new_sig then
     event_kind := case when confirmed_leave then 'leave_confirmed'
       when conflict_leave then 'leave_conflict'
       when old_sig is null then 'allocated' else 'changed' end;
     signature:=concat_ws('|',rec.source,rec.duty_type,rec.turn_number,rec.book_on,rec.book_off);
     insert into public.roster_push_events(user_id,document_id,duty_date,kind,title,body,event_key)
     values(rec.user_id,new.id,rec.duty_date,event_kind,
       case when confirmed_leave then 'Annual leave granted on ' || to_char(rec.duty_date, 'FMDD/FMMM/YY')
            when conflict_leave then 'Annual leave not shown on ' || to_char(rec.duty_date, 'FMDD/FMMM/YY')
            else roster_private.push_notice_title(rec.duty_date,rec.amendment_code,rec.duty_type,event_kind)
       end,
       roster_private.push_notice_detail(rec.source,rec.book_on,rec.book_off,rec.turn_number) ||
         case when confirmed_leave then ' sheet confirms your recorded annual leave.'
              when conflict_leave then ' shows ' || roster_private.push_duty_label(rec.amendment_code,rec.duty_type) ||
                '. Your leave is still recorded. Follow up with Rosters.'
              else '' end,
       rec.user_id::text||'|'||new.id::text||'|'||rec.duty_date::text||'|'||event_kind||'|'||md5(signature))
     on conflict(event_key) do nothing;
   end if;
   if new_sig is not null then
     insert into roster_private.push_state values(rec.user_id,rec.duty_date,new_sig)
     on conflict(user_id,duty_date) do update set signature=excluded.signature;
   end if;
 end loop;
 return new;
end $$;
