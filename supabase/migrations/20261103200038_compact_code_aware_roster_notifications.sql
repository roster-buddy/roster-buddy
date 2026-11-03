-- Code meanings generated from DutyCodeLibrary in lib/core/models/duty_code.dart.
create or replace function roster_private.push_duty_label(code text, duty_type text) returns text
language sql immutable security invoker set search_path='' as $$
 select case duty_type
 when 'annual_leave' then 'Annual leave' when 'medical' then 'Medical'
 when 'rest_day' then 'Rest day' when 'sick' then 'Sick' when 'public_holiday' then 'Bank holiday'
 else case when upper(trim(code))='TS' then 'Safety brief' else coalesce(
 '{"AC":"Accident at work","ACC":"Accommodation – Non Traincrew","ALD":"Daily Annual Leave","ALW":"Annual Leave Weekly","AS":"Strike","AW":"Absent Without Leave","BH":"Bank Holiday","BHL":"Annual Leave (Bank Holiday)","BL":"Bereavement Leave","C1":"Civic Duties","C2":"Attendance at Tribunal","C4":"Magisterial Leave","C5":"School Governor Leave","CC":"Chain of Care","CL":"Compensatory Leave","CO":"Represent Company at Court","CW":"Court Witness","D1":"Grievance Hearing","D2":"MFA Interview","D3":"Safety Related Incident","D4":"Welcome Back Interview","D5":"Planned Authorised Detachment","D6":"Interview","DI":"Driver Instructor","DR2":"Minimum Turn Break Broken","DR3":"Minimum Break with a ND Broken","DR4":"Turn Overtime Exceeded","DR5":"Number of Consecutive Turns Exceeded","DR7":"Move From Booked Time Exceeded","DX":"Disciplinary Hearing","EL":"Education Leave","FL":"First Aid Leave","HA":"Hospital Appointment","HG":"Higher Grade Duty","HR":"Household Removals","HS":"Booked off Sick","JL":"Jury Service","LA":"Company Council","LC":"LLC Duties","LD":"Restricted/Non-core duties/Back to work plan","LH":"Health and Safety","MD":"Marriage Day","ME":"Medical – Special","ML":"Maternity Leave","MP":"Medical – Periodical","MR":"Medical – Review","NL":"Parental Leave – nil pay","PL":"Paid leave (Authorised only by TOM)","PR":"Suspension – Full Pay","PS":"Suspension – Nil Pay","PT":"Paternity Leave","RK":"Route Knowledge Failure","RL":"Route Learning","RR":"Route or Traction Refresh","RU":"Rules/Summary Day","RW":"Rest Day Work","SF":"Sick","SI":"S Conductor Instructing","SK":"Traction Knowledge Failure","SP":"Spare","TA":"Territorial Army","TC":"Training Course","TS":"Safety Brief/STUD/CA","TT":"Traction Training","TW":"Training at Work","UL":"Unpaid Leave","XD":"Cross Depot Allocated","ZB":"No Bank Holiday Work","ZC":"Considerate Duties","ZD":"Restricted no work","ZF":"Forced Rest Day","ZR":"No rest day work","ZS":"No Sunday work"}'::jsonb ->> regexp_replace(upper(trim(code)),'[^A-Z0-9]','','g'),
 case duty_type when 'training' then 'Training' when 'unavailable' then 'Unavailable' when 'unknown' then 'Duty' else 'Shift' end) end end
$$;
create or replace function roster_private.push_notice_title(day date,code text,duty_type text,kind text) returns text
language sql immutable security invoker set search_path='' as $$
 select (case when kind='leave_conflict' then 'Annual leave conflict' else
 roster_private.push_duty_label(code,duty_type)||case when kind='changed' then ' updated' else ' allocated' end end)
 ||' on '||to_char(day,'FMDD/FMMM/YY')
$$;
create or replace function roster_private.push_notice_detail(source text,book_on time,book_off time,turn_number text) returns text
language sql immutable security invoker set search_path='' as $$
 select concat_ws(' ',case source when '48_hour' then '48HR' when '7_day' then '7D' when '10_day' then '10D' else 'BASE' end,
 case when book_on is not null and book_off is not null then to_char(book_on,'HH24MI')||'–'||to_char(book_off,'HH24MI') end,
 case when nullif(trim(turn_number),'') is not null then 'T'||trim(turn_number) end)
$$;
revoke all on function roster_private.push_duty_label(text,text),roster_private.push_notice_title(date,text,text,text),roster_private.push_notice_detail(text,time,time,text) from public,anon,authenticated;
grant execute on function roster_private.push_duty_label(text,text),roster_private.push_notice_title(date,text,text,text),roster_private.push_notice_detail(text,time,time,text) to service_role;

create or replace function roster_private.queue_completed_roster_push() returns trigger
language plpgsql security definer set search_path='' as $$
declare rec record; old_sig text; new_sig text; conflict_leave boolean; event_kind text; signature text; label text;
begin
 if auth.uid() is not null and auth.uid()<>new.user_id then raise exception 'Uploader required'; end if;
 if auth.uid() is null and session_user<>'postgres' and coalesce(current_setting('request.jwt.claims',true),'') not like '%service_role%' then raise exception 'Authenticated processing required'; end if;
 for rec in
   select distinct on (p.user_id,d.duty_date) p.user_id,d.duty_date,d.duty_type,d.turn_number,d.book_on,d.book_off,d.source,d.amendment_code
   from public.document_duties d join public.driver_profiles p on (roster_private.pay_matches(d.payroll_number,p.payroll_number)
     or (d.source='base_roster' and trim(d.driver_number)=trim(p.roster_number)))
   where d.document_id=new.id and d.source in ('base_roster','10_day','7_day','48_hour')
   order by p.user_id,d.duty_date,case d.source when '48_hour' then 4 when '7_day' then 3 when '10_day' then 2 else 1 end desc,d.created_at desc
 loop
   select s.signature into old_sig from roster_private.push_state s where s.user_id=rec.user_id and s.duty_date=rec.duty_date for update;
   if old_sig is null then old_sig:=roster_private.best_roster_signature(rec.user_id,rec.duty_date,new.id); end if;
   new_sig:=roster_private.best_roster_signature(rec.user_id,rec.duty_date);
   conflict_leave:=rec.source<>'base_roster' and rec.duty_type in ('working','training','medical') and roster_private.recorded_annual_leave(rec.user_id,rec.duty_date);
   if conflict_leave or old_sig is distinct from new_sig then
     event_kind:=case when conflict_leave then 'leave_conflict' when old_sig is null then 'allocated' else 'changed' end;
     signature:=concat_ws('|',rec.source,rec.duty_type,rec.turn_number,rec.book_on,rec.book_off);
     label:=case rec.source when '48_hour' then '48HR' when '7_day' then '7D' when '10_day' then '10D' else 'BASE' end;
     insert into public.roster_push_events(user_id,document_id,duty_date,kind,title,body,event_key)
     values(rec.user_id,new.id,rec.duty_date,event_kind,
       roster_private.push_notice_title(rec.duty_date,rec.amendment_code,rec.duty_type,event_kind),
       roster_private.push_notice_detail(rec.source,rec.book_on,rec.book_off,rec.turn_number)||
         case when conflict_leave then ' · Investigate: working on recorded annual leave.' else '' end,
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