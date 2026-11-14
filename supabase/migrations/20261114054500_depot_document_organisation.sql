alter table public.roster_documents
  add column filing_category text,
  add column filing_date date,
  add column filing_title text,
  add constraint roster_documents_filing_category_check check (
    filing_category in (
      'automatic', 'base_roster', '10_day_amendment', '7_day_amendment',
      '48_hour_amendment', 'annual_leave_roster', 'job_card'
    )
  );

-- Existing rows stay unfiled. New rows use their scanned category and dates.
alter table public.roster_documents
  alter column filing_category set default 'automatic';
