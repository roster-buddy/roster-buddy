-- Allow working duties to be manually replaced by a moved Rest Day.
-- The underlying parsed roster duty remains untouched and therefore
-- remains available in duty history.

alter table public.manual_duties
  drop constraint if exists manual_duties_manual_change_type_check;

alter table public.manual_duties
  add constraint manual_duties_manual_change_type_check
  check (
    manual_change_type in (
      'rest_day_worked',
      'edited_times',
      'selected_turn',
      'manual_change',
      'moved_rest_day'
    )
  );
