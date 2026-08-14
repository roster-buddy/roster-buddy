-- The original annual_leave_block_overrides table used:
--   start_date
--   end_date
--   override_type
--
-- Block management now uses:
--   original_start_date
--   original_end_date
--   override_start_date
--   override_end_date
--   change_type
--
-- Keep the legacy columns for compatibility with existing rows, but they
-- must no longer be required for new block allocations.

alter table public.annual_leave_block_overrides
  alter column start_date drop not null,
  alter column end_date drop not null,
  alter column override_type drop not null;
