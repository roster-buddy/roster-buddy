# Roster Buddy: pre-Mac checklist

Updated 30 October 2026. This preserves the six core areas of the agreed August roadmap, with leave and cloud workflows included. Code present is not the same as an end-to-end verified feature.

## 1. Smart Scan
- Present: native ML Kit image OCR, multi-page PDF rendering, classification and page-text reconstruction.
- Tests: test/features/smart_scan/smart_scan_page_text_reconstructor_test.dart.
- [ ] Verify document classification, supported formats and failure/retry behaviour using representative fixtures.
- [ ] Verify duplicates, interrupted imports and repeat uploads do not create incorrect duties.
- Native test pending: camera photos, HEIC decoding, PDF rendering and OCR accuracy.
- Web currently uploads documents without running OCR. Browser/server AI recognition is not part of the original pre-Mac scope.

## 2. Base roster
- Present: base parser and tests in test/core/parser/base_roster_parser_test.dart.
- [ ] Audit 54-week wraparound, commencement Sunday, Sun–Sat coverage and driver matching.
- [ ] Verify mutual line/row rotation and replacement-roster behaviour.

## 3. Annual leave
- Present: leave parser, requests, block overrides, balances and pending actions.
- Tests: annual_leave_roster_parser_test.dart and annual_leave_block_cycle_test.dart.
- [ ] Reconcile imported leave against balance accounting; importing a manual calendar entry is not proof that a balance was deducted.
- [ ] Verify grant, cancellation, abeyance and year rollover.
- [ ] Verify scheduled floating and block requests.
- Confirmed gap: home_screen.dart reports automatic block email sending is not active; a server-side sender is required.
- External email sending needs an agreed provider/account and explicit sending scope before enabling it.

## 4. Job cards
- Present: parser, page splitter, storage service and lookup.
- Tests: job_card_parser_test.dart and job_card_page_splitter_test.dart.
- [ ] Verify real turn/day matching, duplicate versions and correct PDF page opening.

## 5. Roster engine
- Present: shared DutyResolver, manual duties, amendments and Hidden18Service.
- Tests: duty_resolver_test.dart, daily_amendment_resolution_integration_test.dart, hidden_18_service_test.dart.
- [ ] Audit priority Base → 10-Day → 7-Day → 48-Hour → manual, with leave overlays and cancellations.
- [ ] Verify overnight shifts, adjacent-day rest and fatigue boundary cases.
- [ ] Check whether imported manual entries should continue to override later official amendments; do not silently change this policy.

## 6. Calendar, dashboard and workflows
- Present: today/next shift, calendar, details/history, source badges, leave and swaps.
- [x] Allow imported annual leave without a request record to be corrected.
- [x] Expose manual correction for imported unknown/rest/public-holiday/sick/unavailable entries (permanent Sunday rules retain their own action).
- [ ] User-check save, reload and cross-screen consistency for those corrections.
- [ ] Audit settings, pending actions, Sunday availability and email handoff.
- [ ] Verify account isolation and relevant database/storage access rules before broader release.

## Completion evidence
Every area needs recorded test/fixture evidence and a list of remaining native-only checks before it is called complete. Existing CI runs flutter analyze, flutter test and a release web build before GitHub Pages deployment. Passing CI does not prove native camera/OCR or external email delivery.

## Native/Mac stage
Camera and multi-page capture; native OCR accuracy/performance; permissions and native file picking; notification delivery; signing and TestFlight. Later AI/photo enhancement remains a separate scope.

## Next pass
Start with annual-leave balance and overlay reconciliation, then parser fixture coverage. Do not enable unattended external emails as a side effect of this audit.

## 30 October verification pass
- Added `test/core/services/annual_leave_workflow_test.dart`: isolated HTTP fixture runs the real AnnualLeaveService and its REST filters, without production records or email.
- Covers requested → abeyance → granted → cancellation pending → cancelled, balance recalculation after each transition, queue clearance, and removing cancelled dates from active/pending lists.
- Covers both year boundaries, other-account exclusion, block-leave exclusion and allowance extras.
- Existing resolver suite covers Base → 10-Day → 7-Day → 48-Hour → manual and profile matching. Native/UI and live RLS isolation are separate checks, not established by fixture tests.
- Remaining: live browser cross-screen checks, rest-day transaction regression fixtures, import/retry fixtures and the native-only checks above.

### History cancellation fix
- A pending cancellation now stores the exact historical shift selected. Approving later through any cancellation entry point restores that shift and cancels leave in one database transaction.
- Keeping leave clears the stored restoration choice.
- Transaction checks passed for overnight time preservation, no premature restoration, clearing pending data, retaining leave and rejection of another authenticated account under RLS. Test records were rolled back.
- Security advisors show no new database findings.

## Rest-day and classifier verification pass — 30 October
- SQL regression fixture: `docs/sql/test_rest_day_move_workflow.sql`. Ran under authenticated RLS using temporary users, then rolled back.
- Verified pending requests do not alter roster; confirmed work becomes rest; old rests await allocation without copied turns/times; each new shift saves separately; overnight duration; failed saves preserve the prior saved date; queue completes only after every allocation; repeated confirmation preserves allocations; another account cannot allocate.
- Also verified one-date approval/allocation and cancelling an unapproved request without changing roster.
- Hardened same-week validation across both working and rest dates, plus missing fields/types. Sunday and duplicate-date rejections verified.
- Rest-day email handoff now requires a successful launch before recording the pending request.
- Added classification regressions for Wolverhampton vs WO, amendment leave rows, Sunday sheets, turn-code OCR variants, annual-leave documents and empty/unknown text.
- Remaining upload reliability work: replacement imports currently delete old rows and insert batches separately. Move these writes into a transaction and test retry/interruption before calling import reliability complete. Native camera/OCR testing remains pending.
