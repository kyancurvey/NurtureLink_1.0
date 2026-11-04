# Attacker and reviewer pass, step 3.6 (end of Phase 3)

Written 2026-11-02. **The attack scripts were run on a local Postgres 16 that copies Supabase's roles. Since 2026-11-03 migration 014 and all nine SQL test files have also been run on the live project by the user (014 tests 54 PASS, access 205, others unchanged, all 0 FAIL). The repros below (section 4, F1 to F4) have not been run live; nothing was run in a real browser.**

## 1. Result in one paragraph

No way was found for a patient to read or change another patient's data, for a provider to read or change an unassigned patient's data, or for anyone to read provider-only data, the audit log, the invites or the settings. That held for tables, views, all 14 client functions, SECURITY DEFINER misuse, Realtime, the SOS path, the simulator path, re-runs of 004 and 005, and `anon`. Four gaps of a different kind were found: **one signed-in account could fill the database, and any provider could switch off alerts for every patient.** They are fixed in `014_phase3_review_hardening.sql` with the numbers you chose on 2026-11-02. The shared-role lesson from 2.2 held again: `authenticated` is one role for patients, providers and admin, so a grant given "for providers" is given to patients too, and a row policy cannot pick columns.

## 2. Attacker models

- **Patient:** `patient01` (has a provider) and `patient10` (no provider), calling the Data API, RPC and Realtime directly with a valid login, ignoring the app.
- **Provider with no assignment to the target:** `provider01` against patients 06 to 10, `provider02` against patients 01 to 05 and 10.
- **anon:** no login at all.

How to act as a user in the SQL Editor (all repros below use this; it changes nothing outside the transaction because of the `rollback`):

```sql
begin;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'patient01@example.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
-- ... the attack statement here ...
rollback;
```

(Use `set local role anon;` and no claims for the anon cases. The role stays `authenticated` until the `rollback`, so run the whole block at once.)

## 3. Write-surface inventory (after migration 013, before 014)

`authenticated` is one shared role: column grants apply to everyone, RLS limits only the rows. Columns not listed cannot be written by any client role. "Shown to others" means a provider (or the patient) can see the value in the app.

| Table | Who writes (grant) | Columns | Limits that existed | Limits added by 014 | Shown to someone else? |
|---|---|---|---|---|---|
| `profiles` | patient or provider, own row | `language` only (013 removed `display_name`) | language must be en or fil (function) | none needed | no |
| `pregnancy_profiles` | nobody directly (013) | none; `save_pregnancy_details()` writes | due date range, 1000-char history, 10 x 60 conditions | none needed | yes, assigned provider (Phase 4) |
| `devices` | patient, own rows | `kind, label, hardware_id, battery_percent, last_seen_at, is_active` | label 100 chars; battery 0 to 100 | **max 5 per patient; hardware_id 100 chars** | patient only today; provider in Phase 4 |
| `belt_readings`, `maternal_vitals` | patient, own rows; insert only | values, `source`, `client_id`, `measured_at` | value ranges; future-time guard (008); manual guard (010) | **600 per rolling hour per table, by server time** | yes, assigned provider |
| `alerts` | patient inserts SOS only; provider updates handling columns on assigned patients; trigger inserts real alerts | `alert_type, severity, details` (patient); `status, acknowledged_*, action_taken, resolved_at` (provider) | patient may insert only `sos`/`critical` for self; one open alert per type; SOS 5-minute limit (009) | **`details` at most 2000 bytes** | yes |
| `alert_thresholds` | **was: any provider** | limits, severity, enabled | confirmation reset on edit (trigger) | **no client UPDATE at all; admin only** | read by providers and patients' `my_normal_ranges()` |
| `appointments` | patient and provider | no direct patient writes after 012 (functions); provider updates status and time on assigned patients | 1 h to 90 days, 3 open (012) | none needed | yes |
| `consult_notes` | assigned provider | `body` (1 to 10000 chars), `language` | length; assigned patients only | none (provider-only, Phase 6) | yes |
| `validation_pairs` | provider | study fields | provider-only | none | provider-only |
| `consent_records` | own rows | insert `user_id, document_id`; update `withdrawn_at` | one active record per document | none (see open items) | no |
| `deletion_requests` | patient, own | `note` (1000 chars) | one pending request per patient | none needed | admin only |
| `audit_log` | providers, insert only | `actor_id, patient_id, action, details` | action 1 to 64 chars | **`details` at most 2000 bytes** | nobody via the API |
| everything else (`provider_invites`, `app_settings`, `consent_documents` writes, `pregnancy_profiles` direct) | nobody | none | | | |

## 4. Findings

| # | Severity | Finding | Fixed by |
|---|---|---|---|
| F1 | **HIGH** | A patient could insert any number of readings (local test: 100,000 rows in about 3 seconds). That fills the free-tier database for every user and slows the alert trigger. | 014 part 1 |
| F2 | **HIGH** | Any provider, assigned or not, could edit the 4 global alert limits (`enabled = false`, or move the limits out of reach) and so silence alerts for **every** patient. | 014 part 3 |
| F3 | MEDIUM-HIGH | One patient could create unlimited device rows and a `hardware_id` of any length (a 1 MB value was accepted). | 014 part 2 |
| F4 | MEDIUM-HIGH | `alerts.details` and `audit_log.details` accepted any size (one 9.6 MB SOS row stored in under a second). | 014 part 4 |

### Repros (as a simulated user; each should now fail as shown)

**F1.** As `patient01`:
```sql
insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at)
select auth.uid(), 140, 'device', now() - (g || ' seconds')::interval from generate_series(1, 700) g;
```
Before 014: `INSERT 0 700`, and again, and again. After 014: `ERROR: too_many_readings` and nothing stored.

**F2.** As `provider02` (no patients needed):
```sql
update public.alert_thresholds set enabled = false where alert_type = 'fever' returning alert_type, enabled;
```
Before 014: 1 row changed. After 014: `ERROR: permission denied for table alert_thresholds`. A patient also gets the refusal now. Before 014 a patient's attempt changed 0 rows (the row policy stopped it, but the column grant was shared); the old test expected "0 rows" and now expects "permission denied".

**F3.** As `patient01`:
```sql
insert into public.devices (patient_id, kind) select auth.uid(), 'belt' from generate_series(1, 50);
insert into public.devices (patient_id, kind, hardware_id) values (auth.uid(), 'belt', repeat('x', 1000000));
```
Before: 50 rows and a 1 MB value stored. After: `ERROR: too_many_devices`, then `new row ... violates check constraint "devices_hardware_id_length"` (or `too_many_devices` first if 5 exist).

**F4.** As `patient01`:
```sql
insert into public.alerts (patient_id, alert_type, severity, details)
values (auth.uid(), 'sos', 'critical', jsonb_build_object('x', repeat('a', 100000)));
```
Before: stored. After: `ERROR: details_too_large`. (The app's SOS sends no details, so real use is unchanged.)

### Smallest fix (what 014 does)

One trigger function per concern with a fixed `search_path`, acting only when the caller is an API role and the row is for the caller's own `patient_id`; one `REVOKE UPDATE` and one `DROP POLICY` for F2. No new client-callable function: the client function count stays **14**. Per-patient advisory locks make the counts exact when two requests arrive together (the lock itself is not proven by a test, see section 7).

Numbers (all drafts, chosen by you on 2026-11-02): 600 readings per rolling hour per table, 5 devices, 100 characters, 2000 bytes.

## 5. Vectors tried and refused (no finding)

| Vector | Result |
|---|---|
| Read or write another patient's rows through every table, as patient and as unassigned provider | Refused (RLS, 0 rows or error) |
| Views | None in `public` |
| All 14 client functions with wrong, null, foreign and oversized arguments | Each answers only for `auth.uid()` |
| SECURITY DEFINER misuse: call the trigger and helper functions directly; change `search_path`; call as `anon` | No EXECUTE for client roles; fixed `search_path`; anon has none |
| Role change, self-assignment to a provider, fake provider invite | Refused (three layers for role, as in 2.2) |
| Realtime: subscribe to another patient's alert changes; subscribe to readings, vitals, devices | Only `alerts` is published; Realtime applies the same row rule; nothing else is published |
| SOS path: second SOS inside 5 minutes; SOS for someone else; patient with no provider; details payload | Rate limit holds (also under 014); others refused; details now size-capped |
| Simulator path (`deviceSimulator.js`, `source = 'simulator'`) | It uses the same insert rights as any reading. **`source` is a label the client writes, never evidence.** Now counts toward the 600/hour cap |
| Re-running 004 and 005 after 014, and 014 twice | Identical result (grants, policies, triggers compared before and after) |
| `anon` on every table, view, function and Realtime | Nothing |

One result that looked like a finding and is not: in the local harness, `set role postgres` from an `authenticated` session succeeds because the harness session is a superuser. Supabase's API roles cannot do that.

## 6. Reviewer pass over the front end (read, built and statically checked; not run in a browser)

| Check | Result |
|---|---|
| Hard-coded visible strings, missing i18n keys | None found by reading and by `npm run i18n:check` (560 keys in both files, none missing). Known, intended: manifest description, `<title>` and `lang="en"` in `index.html` |
| Missing disclaimers | Every reading screen reviewed carries the disclaimer line (Home, Monitor, Alerts, Care, Profile, placeholders). Not re-seen in a browser |
| Hard-coded thresholds | The band and statuses come from `my_normal_ranges()` and `my_home_status()`. The manual-entry limits exist twice on purpose (guard function and `MANUAL_LIMITS`), documented in PLAN.md. Profile and scheduling limits exist in SQL and in the matching `.js` files, documented |
| Colour-only status | Status is icon plus words plus colour (`StatusBadge.jsx`, Alerts, Care). Not re-seen in a browser |
| Coral with white text | None. `tokens.css` states the rule; the primary button is violet |
| `dangerouslySetInnerHTML`, unescaped database text | None. Alert sentences are built from numbers; consent, names and notes render as plain React text |
| Console logging of personal data | None. The only `console` calls are the missing-translation warning (key name only) and two key-configuration warnings in `supabase.js` |
| Leaked keys | Only `VITE_SUPABASE_URL` and the publishable key (`sb_publishable_...`) are read; `supabase.js` refuses an `sb_secret_` key; `.env.example` holds placeholders; no secret in the repo |
| Realtime channel closed on logout | `useAlerts` removes its channel when its screen unmounts; logging out unmounts the patient area. **Not proven in a browser** (see the live script, step 11) |
| Session cleared on logout | `signOut` uses `scope: 'local'`; `SIGNED_OUT` clears session and profile in `auth.jsx`. Not run live |
| Raw database errors shown to people | All errors go through `friendlyError`. **One exception, deliberate:** a permission-denied error shows its technical detail line (`FormError.jsx`, `PregnancyDetails.jsx`). Remove or hide it before real users (open item) |
| Bundle sizes, code splitting | Build run: main chunk 626 kB (182 kB gzip, over Vite's 500 kB warning); chart chunk 356 kB loads only on Monitor; Home, Profile, Care, Alerts, Privacy are separate chunks; Provider, auth and the design page are still in the main chunk (Phase 4) |
| PWA cache safety | `vite-plugin-pwa` precaches the app shell only (36 entries, 1.4 MB); no runtime caching rule, so Supabase calls and patient data are never stored by the service worker |
| "Check now" stub | **Not gated.** It writes synthetic `simulator` readings into whichever patient is signed in. Fine for demo accounts; must be gated behind demo mode before real users (open item). 014 limits the damage (600/hour) but does not gate it |
| `/#/design` | Still routed (`App.jsx`). Remove before release (open item) |

## 7. What could not be run, and why

- **The F1 to F4 repros and the app screens on the live project** (live script step 12). The SQL tests themselves were run live 2026-11-03 with the counts above.
- **Two requests at the same instant** (the advisory locks). A test file is one session, so it cannot prove them.
- **Request-body size limits** at the API gateway are not visible from SQL.
- **Real browsers, real phones, Realtime delivery between two devices, the service worker, installation.** Covered only by the live script.
- **`003_patient_isolation_smoke.sql`** needs real signed-up users; not meaningfully run locally.
- **An offline backlog over 600 readings in one hour** (a future belt reconnecting) would be refused in part; Phase 5 must send backlogs in batches.
- **Mutation testing** of the new tests: 13 deliberately broken variants of 014 were each caught by at least one test (run locally).
