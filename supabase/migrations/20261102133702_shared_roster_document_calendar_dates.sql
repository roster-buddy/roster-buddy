-- All registered roster documents are shared read-only with signed-in users.
-- Upload, update and delete permissions remain restricted to the uploader.
alter table public.roster_documents add column if not exists identified_dates date[] not null default '{}';
create index if not exists roster_documents_identified_dates_idx on public.roster_documents using gin(identified_dates);
create policy roster_documents_read_signed_in on public.roster_documents for select to authenticated using ((select auth.uid()) is not null);
create policy document_duties_read_signed_in on public.document_duties for select to authenticated using ((select auth.uid()) is not null);
create policy roster_files_read_signed_in on storage.objects for select to authenticated using (
  bucket_id='roster-documents' and (select auth.uid()) is not null
  and exists(select 1 from public.roster_documents r where r.storage_path=storage.objects.name)
);
with dated as (
  select document_id, duty_date as day from public.document_duties
  union
  select c.document_id, g.day::date from public.job_cards c
    cross join lateral generate_series(c.valid_from::timestamp,c.valid_to::timestamp,interval '1 day') g(day)
    where c.valid_to>=c.valid_from and c.valid_to-c.valid_from<=3660
  union
  select a.document_id, g.day::date from public.annual_leave_allocations a
    join public.annual_leave_periods p on p.allocation_id=a.id
    cross join lateral generate_series(p.start_date::timestamp,p.end_date::timestamp,interval '1 day') g(day)
    where p.end_date>=p.start_date and p.end_date-p.start_date<=3660
), grouped as (
  select document_id,array_agg(distinct day order by day) as dates from dated where day is not null group by document_id
)
update public.roster_documents r set identified_dates=g.dates from grouped g where g.document_id=r.id;
