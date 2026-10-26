# MANUAL_TEST_2_5.md

Eight steps to prove, with the demo accounts, that **a patient cannot reach provider screens or data** and **a provider sees only assigned patients**. Use a phone and a laptop. Fake accounts only; never type a real person's details.

**Be clear about what each kind of step proves.** The patient and provider screens are still placeholders (Phases 3 and 4), so they show no readings yet. Steps 1, 2, 3, 7 and 8 prove the *screens and routing*. Steps 5 and 6 prove the *data*: they run in the SQL Editor and behave exactly like each demo user's real request to the database, which is where the real protection lives. A screen guard alone proves nothing about data.

## Before you start

1. Migration `008_reading_time_guard.sql` has been run.
2. The 12 demo accounts exist and `supabase/seed/demo_seed.sql` ran with `demo_mode = on` (it ended with 10 summary rows).
3. The consent documents are published (they are, since 2026-10-19).
4. You have the demo passwords from your password manager (never in chat).
5. **One browser profile = one signed-in account.** `kyancurvey.github.io` is one origin, so a second account in another tab of the same browser replaces the first. On the laptop use a normal window for one account and a **private/incognito window** for the other (or two different browsers).

Site: `https://kyancurvey.github.io/NurtureLink_1.0/`

Write PASS or FAIL next to each step. Stop and send me the step number and what you saw (no real data) if any step fails.

---

## Step 1. Phone: a patient signs in
1. On the phone, open the site and sign in as `patient01@example.test`.
2. The consent screen appears. Expect **four required items** (Terms of Use, Privacy Notice, Informed Consent, Medical Disclaimer) and one **optional, unticked** study item. There must be **no** guardian assent item (the seed gave patient01 an adult date of birth; if you see guardian assent, the seed has not run).
3. Tick the four required items, accept.

**Pass if:** you land on the patient home with five bottom tabs (Home, Monitor, Alerts, Care, Profile), and each tab shows its placeholder with the line "monitoring and screening, not diagnosis".

## Step 2. Phone: the patient tries provider and admin addresses
Still signed in as patient01, change the end of the address bar and press Go, one at a time:
`.../NurtureLink_1.0/#/provider` then `#/provider/patients` then `#/provider/alerts` then `#/admin`.

**Pass if:** every time you end up on the patient home (`#/patient`), and no provider screen, patient list or sidebar ever stays on screen.

## Step 3. Laptop: a provider signs in and cannot use patient screens
1. In a **private window** on the laptop, sign in as `provider01@example.test`.
2. Consent screen: expect **three required items** (Provider Confidentiality Agreement, Terms of Use, Privacy Notice). Accept.
3. Expect the provider dashboard with a **sidebar of seven tabs** (Overview, Patients, Alerts, Consults, Validation, Reports, Settings).
4. Change the address to `.../NurtureLink_1.0/#/patient`.

**Pass if:** you see the seven-tab sidebar and are sent back to `#/provider` from step 4.

## Step 4. Laptop: the provider login was recorded
In the normal window (SQL Editor), run:

```sql
select al.created_at, al.action, u.email as actor
from public.audit_log al
left join auth.users u on u.id = al.actor_id
where al.action = 'provider_login'
order by al.created_at desc
limit 5;
```

**Pass if:** the top row is `provider01@example.test` with a time from a few minutes ago.

## Step 5. Laptop: who can see which patient (the data proof)
Paste the whole file `supabase/tests/demo_isolation_checks.sql` into a new SQL Editor tab and run it.

**Pass if:** the first row says `29 PASS, 0 FAIL`, and the INFO rows read:
- `provider01 can see: patient01, patient02, patient03, patient04, patient05`
- `provider02 can see: patient06, patient07, patient08, patient09`
- patient10 appears in neither list (patient10 has no provider, and has an open critical alert that nobody can see).

## Step 6. Laptop: the full access tests still pass
Run `supabase/tests/access_tests.sql`, then `supabase/tests/006_consent_flow_tests.sql` (each pasted whole into a new tab).

**Pass if:** the first says `200 PASS, 0 FAIL` and the second `30 PASS, 0 FAIL`. (If the first shows a different PASS number but 0 FAIL, send me the SUMMARY row; I could not run it here, so the exact count is my expectation: 197 before plus 3 new.)

## Step 7. Phone: the second provider, and patient screens stay closed
1. Sign out on the phone (Log out in the header), then sign in as `provider02@example.test` and accept the three provider documents.
2. Expect **five bottom tabs** (Overview, Patients, Alerts, Consults, Settings; Validation and Reports are laptop-only for now).
3. Change the address to `#/patient`.

**Pass if:** you see the five provider tabs and are sent back to `#/provider`.

## Step 8. Both: signing out really closes the door
1. On the phone, tap **Log out**, then press the browser **Back** button several times.
2. On the laptop private window, do the same.

**Pass if:** you only ever see the login screen (or the site root that sends you to login); the previous account's screens never come back. Then close the private window.

---

## Done when
All eight steps are PASS, `demo_isolation_checks.sql` shows `29 PASS, 0 FAIL`, and `access_tests.sql` shows 0 FAIL. Send me the two SUMMARY rows and the PASS/FAIL of steps 1 to 8; I will then record Phase 2 as closed.

## Afterwards
- Leave demo mode and the demo accounts only for as long as you need them. Before real users sign up: delete the demo accounts and turn demo mode off (the undo statements are in the header of `demo_seed.sql`, and `docs/ADMIN_SQL.md` snippet 4).
- Anyone who learns a demo provider password can read every demo patient and edit the shared alert limits, so keep those passwords strong and private.
