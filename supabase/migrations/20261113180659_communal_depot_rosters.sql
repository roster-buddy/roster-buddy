alter table public.roster_documents
  add column depot text,
  add column base_roster_commencement date,
  add column base_roster_pages text[];

update public.roster_documents d set depot = lower(trim(p.depot))
from public.driver_profiles p where p.user_id = d.user_id;

create index roster_documents_depot_idx on public.roster_documents(depot);
create index if not exists roster_documents_storage_path_idx on public.roster_documents(storage_path);

-- Existing clients also publish to the uploader's depot.
create function public.set_roster_document_depot() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  select lower(nullif(trim(p.depot), '')) into new.depot
    from public.driver_profiles p where p.user_id = new.user_id;
  return new;
end;
$$;
create trigger set_roster_document_depot before insert or update of depot, user_id
on public.roster_documents for each row execute function public.set_roster_document_depot();

drop policy roster_documents_read_signed_in on public.roster_documents;
create policy roster_documents_read_depot on public.roster_documents for select to authenticated using (
  processing_status = 'processed' and depot = (
    select lower(trim(p.depot)) from public.driver_profiles p where p.user_id = (select auth.uid())
  )
);

drop policy document_duties_read_signed_in on public.document_duties;
drop policy document_duties_select_applicable on public.document_duties;
create policy document_duties_read_depot on public.document_duties for select to authenticated using (
  exists (select 1 from public.roster_documents d where d.id = document_duties.document_id
    and (d.user_id = (select auth.uid()) or (
      document_duties.source <> 'base_roster' and d.processing_status = 'processed'
      and d.depot = (select lower(trim(p.depot)) from public.driver_profiles p
                     where p.user_id = (select auth.uid()))
    )))
);

drop policy "Authenticated users can read job cards" on public.job_cards;
create policy job_cards_read_depot on public.job_cards for select to authenticated using (
  exists (select 1 from public.roster_documents d where d.id = job_cards.document_id
    and (d.user_id = (select auth.uid()) or (
      d.processing_status = 'processed'
      and d.depot = (select lower(trim(p.depot)) from public.driver_profiles p
                     where p.user_id = (select auth.uid()))
    )))
);

drop policy roster_files_read_signed_in on storage.objects;
create policy roster_files_read_depot on storage.objects for select to authenticated using (
  bucket_id = 'roster-documents'
  and exists (select 1 from public.roster_documents d where d.storage_path = objects.name
    and (d.user_id = (select auth.uid()) or (
      d.processing_status = 'processed'
      and d.depot = (select lower(trim(p.depot)) from public.driver_profiles p
                     where p.user_id = (select auth.uid()))
    )))
);

create or replace function roster_private.effective_shift_for_reminder(who uuid,day date)
returns jsonb language plpgsql stable set search_path='' as $$
declare profile public.driver_profiles%rowtype; result jsonb;
begin
 select * into profile from public.driver_profiles where user_id=who;
 if not found then return null; end if;
 -- A granted floating day remains leave until it is cancelled.
 if exists(select 1 from public.annual_leave_requests where user_id=who
   and leave_date=day and request_type='floating' and status='granted') then return null; end if;
 select jsonb_build_object('source','manual','duty_type',d.duty_type,
   'book_on',d.book_on,'book_off',d.book_off,'turn_number',d.turn_number,'amendment_code',null)
 into result from public.manual_duties d where d.user_id=who and d.duty_date=day
 order by d.updated_at desc,
   case d.manual_change_type when 'manual_change' then 4 when 'edited_times' then 3
     when 'selected_turn' then 2 when 'rest_day_worked' then 1 else 0 end desc,d.id desc limit 1;
 if result is not null then return result; end if;
 if exists(select 1 from roster_private.reminder_block_periods(who) l
   where day between l.start_date and l.end_date) then return null; end if;
 if extract(dow from day)=0 and not exists(
   select 1 from public.sunday_availability_overrides where user_id=who and sunday_date=day and is_available)
   and (profile.permanently_unavailable_sundays or exists(
     select 1 from roster_private.reminder_block_periods(who) l
     where l.end_date=day-1 and extract(dow from l.end_date)=6)) then return null; end if;
 select jsonb_build_object('source',d.source,'duty_type',d.duty_type,
   'book_on',d.book_on,'book_off',d.book_off,'turn_number',d.turn_number,'amendment_code',d.amendment_code)
 into result from public.document_duties d
 join public.roster_documents r on r.id=d.document_id and r.processing_status='processed'
 where (r.user_id=who or r.depot=lower(trim(profile.depot)))
 and d.duty_date=day and d.source in ('base_roster','10_day','7_day','48_hour','annual_leave')
 and (case when d.source='base_roster' then
     r.user_id=who and nullif(trim(d.driver_number),'')=nullif(trim(coalesce(profile.roster_number,profile.driver_number)),'')
   else roster_private.pay_matches(d.payroll_number,profile.payroll_number) end)
 order by case d.source when 'annual_leave' then 5 when '48_hour' then 4
   when '7_day' then 3 when '10_day' then 2 else 1 end desc,
   -- Same-source ordering matches the resolver's Duty.uniqueKey.
   concat_ws('|',d.duty_date,d.source,d.payroll_number,d.driver_number,d.turn_number,
     to_char(d.book_on,'HH24:MI'),to_char(d.book_off,'HH24:MI'),d.amendment_code) desc,
   d.id desc limit 1;
 return result;
end $$;

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
   where d.document_id=new.id
     and (p.user_id=new.user_id or (d.source<>'base_roster' and lower(trim(p.depot))=new.depot))
     and d.source in ('base_roster','10_day','7_day','48_hour')
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
