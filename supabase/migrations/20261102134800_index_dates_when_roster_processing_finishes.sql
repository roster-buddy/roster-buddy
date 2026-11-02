create or replace function public.index_processed_roster_document_dates()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.identified_dates := array(
    select distinct dates.day from (
      select unnest(new.identified_dates) as day
      union select d.duty_date from public.document_duties d where d.document_id=new.id
      union select g.day::date from public.job_cards c
        cross join lateral generate_series(c.valid_from::timestamp,c.valid_to::timestamp,interval '1 day') g(day)
        where c.document_id=new.id and c.valid_to>=c.valid_from and c.valid_to-c.valid_from<=3660
      union select g.day::date from public.annual_leave_allocations a
        join public.annual_leave_periods p on p.allocation_id=a.id
        cross join lateral generate_series(p.start_date::timestamp,p.end_date::timestamp,interval '1 day') g(day)
        where a.document_id=new.id and p.end_date>=p.start_date and p.end_date-p.start_date<=3660
    ) dates where dates.day is not null order by dates.day
  );
  return new;
end;
$$;
revoke all on function public.index_processed_roster_document_dates() from public, anon;
grant execute on function public.index_processed_roster_document_dates() to authenticated, service_role;
create trigger index_processed_roster_document_dates
before update of processing_status on public.roster_documents
for each row when (new.processing_status='processed')
execute function public.index_processed_roster_document_dates();
