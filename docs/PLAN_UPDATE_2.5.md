# PLAN_UPDATE_2.5.md
Paste these into PLAN.md. Nothing below says "run live" unless you have run it: I could not run any SQL in this session (no Postgres in the sandbox). Flip the "pending" words after you run each item.

## A. Section 11 (Environment State): rows to replace or add

**Replace the row "Migrations already run, in order" ending (after "...fake accounts only until the reviewer approves and every placeholder is filled.") by adding:**
> **008 (reading time guard) written 2026-10-19, run live: pending.** After 008 run: `access_tests.sql` expected **200 PASS, 0 FAIL** (197 plus 3 new; not yet run).

**Add row: Demo data (step 2.5)**
| Item | Status / value |
|---|---|
| Demo data (step 2.5) | `supabase/seed/demo_seed.sql` written, **not yet run**. Needs `demo_mode = on` and 12 accounts created in Dashboard > Authentication > Users > Add user (Auto Confirm): `provider01`, `provider02`, `patient01` to `patient10` at `@example.test`, strong random passwords in a password manager. The seed refuses to run otherwise, changes only those 12 accounts, promotes the 2 providers, gives patients 01 to 05 to provider01, 06 to 09 to provider02, patient10 to nobody; patient07 is under 18; trimesters 2 / 5 / 3; 14 days of belt readings and vitals (3 a day, Asia/Manila); alerts come from the real trigger (6 generated: patient04 low_spo2 acknowledged, 05 signal_loss open, 06 FHR resolved, 08 FHR open, 09 fever open, 10 FHR open and invisible to both providers) plus 1 SOS for patient08. No consent records, notes or validation pairs are seeded. Re-runnable (deletes and rebuilds those accounts' readings, vitals, alerts, appointments, devices). `demo_mode` is currently whatever you last set it to (it was `off`). Undo statements are in the seed header. |

**Append to the row "Access model facts (004, 005)":**
> 008: a BEFORE INSERT trigger (`guard_reading_time`) on `belt_readings` and `maternal_vitals` refuses `measured_at` more than 5 minutes ahead of the server clock, for every role, with the message `reading_time_in_future`. Reason: the alert rule sorts by `measured_at`, so future-dated normal readings (a wrong phone clock) would hide later real alerts, and readings are append-only. Old readings (offline sync) are allowed. **Phase 3/5 must map `reading_time_in_future` in `src/lib/errors.js` (i18n, both languages) and omit `measured_at` for live readings.** `access_tests.sql` fake readings now use past dates; the admin deletion-request check no longer depends on real deletion requests.

**Append to "Files currently in repo":**
> **Step 2.5 added:** `supabase/migrations/008_reading_time_guard.sql`, `supabase/seed/demo_seed.sql`, `supabase/tests/demo_isolation_checks.sql` (expected 29 PASS), `docs/MANUAL_TEST_2_5.md`. Changed: `supabase/tests/access_tests.sql`. (The uploaded zip contained a `package-lock.json`; this plan says the repo has none. Confirm which is true.)

## B. Section 12 step table: add row
| 2.5 | Demo seed, final review, 8-step manual test | **written 2026-10-19, not yet run.** Closes Phase 2 when: demo accounts exist, seed runs, `access_tests.sql` shows 0 FAIL, `demo_isolation_checks.sql` shows 29 PASS 0 FAIL, and all 8 manual steps pass |

## C. Section 13 (Progress Log): new row
| 2026-10-19 | 2.5 Demo seed and Phase 2 review (written; nothing run) | `demo_seed.sql` (guards: demo_mode on, 12 accounts exist and have safe roles; self-check of alert results), `008_reading_time_guard.sql`, `demo_isolation_checks.sql`, fixed `access_tests.sql`, `MANUAL_TEST_2_5.md`. Review of the repo zip: no secrets, no `sb_secret`/`service_role` use in code, no `dangerouslySetInnerHTML`, no hard-coded visible text found by a scan, `i18n:check` passes (218 keys), every table has RLS and at least one policy, no broad grants found. Two real findings fixed: (1) future-dated readings could silence alerts (008); (2) one test counted all deletion requests and would have failed after your pending deletion-request live check | You: create 12 accounts, run 008, turn demo_mode on, run the seed, run `demo_isolation_checks.sql`, `access_tests.sql`, `006_consent_flow_tests.sql`, do the 8 manual steps, report the SUMMARY rows | Not verifiable here: all SQL (static syntax checks only), browser behavior. Seed does not fake consent: demo users accept it themselves. Demo providers can edit the shared alert limits: keep passwords strong, delete the accounts after Demo Day |

## D. Open items
**You still need to resolve (unchanged, with owners):**
- [ ] Medical officer confirms the alert thresholds (limits, "in a row" counts, severities), then ADMIN_SQL snippet 6. The demo alerts were generated from the unconfirmed defaults. Also ask: should the 110 to 160 range depend on gestational age (early pregnancy normally runs higher)? The seed keeps all values inside the default range.
- [ ] Midwife/medical officer reviews the Filipino wording (`docs/FILIPINO_REVIEW.md`) and the English status words.
- [ ] Ethics/legal reviewer approves Terms, Privacy Notice, consent text; fill the 7 placeholders. The published documents are DRAFT: fake accounts only.

**New from this review:**
- [ ] Patients with no assigned provider (like patient10): their alerts and SOS reach nobody. Phase 3/4 must say "no provider assigned yet" and SOS wording must not promise a response.
- [ ] Phase 3: map `reading_time_in_future` in `errors.js` and both locale files.
- [ ] Demo accounts: delete them (seed header) and turn demo_mode off before real users sign up.
- [ ] Confirm whether `package-lock.json` is in the repo (decision on `npm ci` is still open).
- [ ] Still open from before: any provider can edit the global alert limits; `/#/design` is public; the app cannot read `demo_mode`.
