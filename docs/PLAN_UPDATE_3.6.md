# Plan update, step 3.6: Phase 3 review and close-out

Written 2026-11-02; updated 2026-11-03. **The SQL is proven live (014 and all nine test files, 0 FAIL, seen by the user); the user reports (2026-11-03) that the 12-step script was run and was all good (report only, no per-step detail).** The SQL was also run on a local Postgres 16 that copies Supabase's roles; see `docs/ATTACKER_REVIEW_3.6.md` for what that does and does not prove.

## 1. What this step did

- Attacker pass and write-surface inventory: `docs/ATTACKER_REVIEW_3.6.md`. Four findings (2 HIGH, 2 MEDIUM-HIGH), none about reading another person's data. All fixed in `supabase/migrations/014_phase3_review_hardening.sql`, tested by `supabase/tests/014_phase3_review_tests.sql`.
- Reviewer pass over the front end: same document, section 6. One code change: the new error `too_many_readings` is mapped in `src/lib/errors.js` and both locale files (560 keys).
- `004_grants.sql`, `005_rls.sql` and `access_tests.sql` edited so that re-running them cannot undo 014 (the alert-limit UPDATE grant and the provider UPDATE policy are gone from them).
- `docs/FILIPINO_REVIEW.md`: duplicate section numbers relabelled (4a, 4b, 4c); section 11 added for the one new string.
- `docs/ADMIN_SQL.md` snippet 6: the admin now edits and confirms alert limits (and must set `is_confirmed = false` by hand after a change).
- PLAN.md: this step recorded; open items cleaned; Phase 3 close-out added.

## 2. The live script: one pass, 12 steps, phone and laptop

**Before step 1 (SQL Editor, not counted below):** 014 and all test files are already run (2026-11-03). Delete the old test alert for patient01 (`delete from public.alerts where alert_type = 'fhr_out_of_range' and patient_id = (select id from auth.users where email = 'patient01@example.test');` only if it exists), then re-run `supabase/seed/demo_seed.sql` (demo mode must be on).

Accounts are `patientNN@example.test`. **Laptop A** = a normal browser window, **Laptop B** = a private window, **Phone** = your phone's browser or the installed app. Times in the app are always Asia/Manila. Note anything that looks wrong with the screen, the account and the time, and send it.

| # | Where / who | Do | Verify |
|---|---|---|---|
| 1 | Laptop A, patient01 | Log in. Open Home. Press **Check now**. Open Monitor and switch Day, Week, Month. Open the **Adjust belt** panel. | Home shows a status with an icon and a word (Normal) and the disclaimer. After Check now the "last check" time is new. Day/Week/Month change the charts; the shaded normal band sits at the limits in `alert_thresholds` (110 to 160 bpm for the baby by default). The Adjust belt panel shows its steps. *(Closes 3.1 baseline, 3.2 a and g.)* |
| 2 | Laptop A and Laptop B open; Phone | Laptop A: patient01, **Alerts** tab, leave it open. Laptop B: patient02, Alerts tab. Phone: patient01, Monitor, type baby heart rate **170**, **171**, **172**, confirming each. | Each typed value appears at the top of the Monitor history on the phone. Within a few seconds Laptop A shows a new open alert **without a refresh**; write down how many seconds. Laptop B (patient02) shows nothing new. Phone Home now says needs attention with an open alert. Open count on Alerts = the reason line on Home. *(3.2 c and d; 3.3 check 2 and arrival timing, check 6.)* |
| 3 | Laptop A, patient01 | Alerts: press **Mark as seen** on that alert. Refresh the page. Try to press it again. | The button is replaced by a "seen" time; after refresh it is still seen; it cannot be pressed twice. The alert stays open (seen is information only). Laptop B still shows nothing of patient01. *(3.3 check 3.)* |
| 4 | Phone, patient08 then patient04 | Log out, log in as patient08, open Alerts and Home. Then log out and log in as patient04. | patient08: an open FHR alert and an SOS in its own section; Home says urgent. patient04: the low SpO2 alert is under **Handled** (acknowledged), Open is 0, and Home does not say urgent because of it. Nothing of patient01 appears on either account. *(3.3 check 1.)* |
| 5 | Phone, patient05 then patient09 | Log in as patient05: Home, Monitor (week). Then patient09: Home, Alerts. | patient05: needs attention because the belt lost signal; the signal-lost points show as **gaps**, never joined by a line; the Adjust belt guidance is offered. patient09: open fever alert in the list and a fever reason on Home. *(3.2 b, 3.3 check 6.)* |
| 6 | Phone, patient10 (no provider) | Log in. Open Home, its SOS card, then Alerts, Care and Profile. | "No provider assigned yet" appears; the SOS card is guidance only and has **no Send button**; the wording promises no response; Care cannot submit a request; no screen shows an error. *(3.1 b, 3.3 check 5.)* |
| 7 | Phone, patient01; Laptop A on Alerts | Home: press the SOS button and send it. Press it again right away. | First press: the in-app "sent" wording and Home turns urgent. Second press: "already sent a moment ago"; the SOS count stays **1**. Laptop A shows the SOS in its SOS section without a refresh. *(3.1 a; the 5-minute limit; Realtime a second time.)* |
| 8 | Phone, patient01 then patient07 | Care: request an appointment at least a day ahead; cancel it; request again and **reschedule** it; try a time under 1 hour ahead. Then log in as patient07 (under 18) and open Care. | The request appears as "Requested" with the "not confirmed until your provider confirms" wording and the provider name. Cancel and reschedule work; the too-soon time is refused with a calm message (no code shown). patient07 gets the same screens and rules. *(3.4 checks.)* |
| 9 | Phone, patient01 | Profile: save pregnancy details (due date in 4 to 6 months, a short history, two conditions); try a due date far in the past. Set a display name; clear it. Look at the health timeline, devices and Help. | Saved values are still there after you reload. Weeks and trimester show and say they are not a diagnosis. The bad date is refused with a calm message, not database text. The name changes and clears. Devices are read only and labelled "reported by your app, not verified". *(3.5 checks 1 to 9.)* |
| 10 | Phone then Laptop A, patient01 | Toggle **FIL** on every tab (Home, Monitor, Alerts, Care, Profile). Log out and log in again on the phone. Log in on Laptop A. | Every visible string is Filipino (no English left except names and numbers); after logging out and in, and on the other device, it is still Filipino. Switch back to English at the end. *(3.2 h, 3.3 check 7, 3.5, language persistence.)* |
| 11 | Phone and Laptop A | Phone: **Log out** (Profile or header). Press the browser Back button. Then log in as patient04 on the same phone. Laptop A: open DevTools, Network, filter "WS", then log out there too. | After logout you see the login screen; Back does not show any patient screen; patient04 sees none of patient01's data. Laptop A's websocket line closes after logout. Logging out on the phone did not log out Laptop A until you did it. *(Session cleared, Realtime closed.)* |
| 12 | Laptop, Supabase SQL Editor | Run the four repros in `docs/ATTACKER_REVIEW_3.6.md` section 4 (F1 to F4), then as `patient01` try `update public.alerts set status = 'resolved' where patient_id = auth.uid() returning id;` and an insert into `belt_readings` with another patient's `device_id`. | F1 `too_many_readings`; F2 `permission denied for table alert_thresholds`; F3 `too_many_devices` and the `hardware_id` check; F4 `details_too_large`; the status change shows 0 rows (no row rule lets a patient update an alert; `UPDATE 0` is the correct answer, not an error); the reading with another patient's device is refused with a row-level security error. Each block ends in `rollback`. *(014 live, 3.3 check 4, 3.2 e.)* |

Not in the script on purpose (each needs a code edit and a redeploy, so it stays open): 3.1 (c) and 3.2 (f), the "wrong clock" messages via `TEST_CLOCK_SKEW_MINUTES` and `TEST_MANUAL_CLOCK_SKEW_MINUTES`.

## 3. Phase 3 open items

"Closed by this review" means closed in the written files; it becomes closed live only after you run 014 and report the tests.

### 3a. Closed by this review

| Item | How |
|---|---|
| Abuse limits for readings, devices and big JSON (PLAN items "abuse limits", "no rate limit on typed readings", "alerts.details no size limit") | 014: 600 readings per rolling hour per table; 5 devices and `hardware_id` 100 characters; `details` 2000 bytes. SOS 5-minute limit unchanged |
| Whether providers may edit the global alert limits | Decided: admin only (014, 004, 005, ADMIN_SQL snippet 6) |
| Duplicate section numbers in `FILIPINO_REVIEW.md` | Relabelled 4a, 4b, 4c; no reference broke |
| Reviewer pass: plain-text rendering, no secrets, no personal data in console, no coral-with-white-text, PWA caches shell only, channel cleanup on unmount | Read and built; nothing needed changing (live proof is in the script) |

### 3b. Still open

| Item | Who decides |
|---|---|
| Run 014, its tests and the 12-step script, and report them | **me (project owner)** |
| Alert limits (110 to 160, 3 in a row, and the others), eligibility checklist, then `is_confirmed = true`; whether the 110 to 160 range should depend on gestational age | **medical officer** |
| The 14-hour freshness window, signal labels (80/50), low battery 20%, manual entry limits, scheduling limits, Profile limits, trimester rule, Home, SOS, Alerts, Care and Profile wording | **medical officer** (wording also **midwife**) |
| Filipino wording, `docs/FILIPINO_REVIEW.md` sections 4a to 11 | **midwife** |
| English status words and the disclaimer line | **medical officer** |
| Terms, Privacy Notice, consent, guardian assent, under-18 note; the placeholders (controller, DPO, NPC status, lawyer, ethics protocol, region country, deletion time); FDA device wording; breach procedure | **lawyer** and **ethics reviewer** (names and placeholders from **me**) |
| Whether real patient data will ever be used (would need a separate private setup) | **me** |
| Whether a typed reading may raise a critical FHR alert on its own | **medical officer**, then **me** |
| Whether "acknowledged" and "resolved" both read as "Handled" | **medical officer** |
| Delete the demo accounts and turn `demo_mode` off before real users | **me** |
| Confirm email OFF (needs custom SMTP before ON); custom SMTP | **me** |
| Brand colours, tagline, `i18n:check` in the workflow, lockfile and `npm ci` | **me** (designer for colours) |
| Run the Security Advisor and send anything flagged | **me** |
| Raw database detail line on permission errors (`FormError.jsx`, `PregnancyDetails.jsx`): remove before real users | **me**, built in Phase 4 or at release |
| Remove `/#/design` before release | **me**, at release |
| No Content-Security-Policy (GitHub Pages sets no headers; a meta tag is possible later) | **me** |
| Realtime "Allow public access" setting and optional pg_graphql disable: do not change without testing | **me** |
| Main chunk 626 kB (182 kB gzip): provider area and auth are still in it | Phase 4 (split the provider area) |
| Appointments with no provider (patient10's seeded request); optional cleanup | **me** |
| Whether to add a "delivered / pregnancy ended" state | **me**, later phase |
| Zero-width joiner refusal in display names | **me**, if a real user is affected |
| Consent churn: a patient can withdraw and re-accept without limit (low) | **me**, Phase 4 or later |
| Simultaneous-request timing (advisory locks, row lock) is not proven by any test | **me**: optional two-session test on the live project |

### 3c. Moved to Phase 4 or 5

| Item | Phase |
|---|---|
| Gate or remove **Check now** (the stub writes synthetic readings into the signed-in patient's real rows; `TEST_*_CLOCK_SKEW_MINUTES` must stay 0). Needs a way for the app to read `demo_mode` (a read-only function or a flags table) | 5 (before real users) |
| Device state is still spoofable: `battery_percent`, `last_seen_at`, `is_active`, `label` are patient-written (014 limited only the count and `hardware_id` length). Real fix: derive `last_seen_at` from the database clock, move battery reports into a function | 5 |
| Readings backlog over 600 per hour after an offline period must be sent in batches or the cap raised | 5 |
| Realtime for `belt_readings` and `maternal_vitals`; live updates on Home | 5 |
| Provider screens must show `seen_by_patient_at` as information only | 4 |
| Care card shows the provider's chosen name without saying it is not verified | 4 |
| Audit by construction: a read function that logs, instead of the app inserting audit rows | 4 (decision) |
| A provider confirms a request by setting `status = 'scheduled'`; nothing stops re-opening a cancelled row | 4 (decision) |
| Provider phone tab bar (5 of 7 tabs); validation-team access; provider consent screen; database-level consent enforcement; blocking edits to published consent documents | 4 |
| Chat, video, consult history | 6 |
| Provider audit_log insert volume (count unlimited; size now capped) | 4 |

## 4. Ready for Phase 4

**Phase 4 may rely on** (each was seen to pass on the live project, as reported to Claude): the access, consent, home, monitor, alerts, care and profile test files at 0 FAIL: `access_tests.sql` 209, `006_consent_flow_tests.sql` 30, `demo_isolation_checks.sql` 29, `009_patient_home_tests.sql` 37, `010_monitor_tests.sql` 57, `011_patient_alerts_tests.sql` 57, `012_patient_care_tests.sql` 130, `013_patient_profile_tests.sql` 144. That proves, for the state through migration 013: a patient reads and writes only their own rows; a provider reads only assigned patients; no view exists; the 14 client functions are exactly the ones listed in PLAN.md; `anon` has nothing; `alerts` is the only published Realtime table.

**Also proven live since 2026-11-03:** 014 and its 54 checks (reading cap, device limits, 2000-byte limit, alert limits admin only, 14 client functions) and `access_tests.sql` at 205, with the older files unchanged. **Phase 4 must not assume** the real-time behaviour of those guards under two simultaneous requests (no one-session test proves it). It must also not assume: that the live screens work in every state (only the user's overall report for 3.4 and 3.5 exists, and the 12-step script is unrun); that two simultaneous requests are safe; that the status of the alert limits is "confirmed" (they are unconfirmed defaults); that `source` proves where a reading came from.

**Notes for Phase 4:**

- `seen_by_patient_at` is **information only**: show it ("Patient has seen this" with the Manila time) next to an open alert; never use it to sort, hide, snooze or close an alert, and never treat it as acknowledged.
- A provider **confirms** an appointment request by updating `status` to `scheduled` (the existing provider policy). The patient sees "Confirmed". A cancelled row can still be re-opened by a provider: decide in Phase 4.
- **Provider display name path:** a provider sets a name with `set_my_display_name()`; patients read it only through `my_provider_name()`. The name is chosen by the provider and unverified: say so wherever it is shown.
- **Audit by construction** is an open decision: today the app inserts audit rows, so a missing insert means a missing record. Prefer a read function that logs inside the database.
- **Shared-role lesson:** `authenticated` is one role for patients, providers and admin, so every grant applies to everyone and RLS limits only rows. Anything a provider must do but a patient must not (change a column, edit global settings) belongs in a SECURITY DEFINER function that checks the caller, or in the SQL Editor, never in a column grant or a row policy alone. The 3.6 alert-limit finding was exactly this.
- Admin edits to `alert_thresholds` in the SQL Editor do **not** clear `is_confirmed`; set it to false in the same statement (ADMIN_SQL snippet 6).
