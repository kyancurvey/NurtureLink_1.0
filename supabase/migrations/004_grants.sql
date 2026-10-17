-- =====================================================================
-- 004_grants.sql
-- NurtureLink: the minimum table, sequence and function privileges for each
-- database role. This is lock 1 of 2; the row rules (lock 2) are in 005.
--
-- WHAT IT DOES
--   1. Wipes every table and sequence privilege that anon and authenticated
--      hold in the public schema (clean slate, so nothing stray survives),
--      and removes the right to CREATE objects in public.
--   2. Sets the privileges of every function explicitly.
--   3. Grants anon NOTHING. (There is no exception.)
--   4. Grants authenticated only what the app needs. Reading is granted per
--      table; writing is granted per COLUMN, so for example nobody can write
--      profiles.role, alerts.severity or pregnancy_profiles.assigned_provider_id.
--   5. Grants no sequence privileges (inserting into audit_log needs none).
--
-- IMPORTANT: "authenticated" is ONE database role shared by patients,
-- providers and admins. A grant here gives that ability to all of them;
-- 005 (row level security) then decides who may do it to which rows. So a
-- patient who reads a provider-only table gets an empty result or a
-- "row-level security" error, not "permission denied". "Permission denied"
-- appears only where NO grant exists (anon everywhere, and the tables marked
-- "no client access" below).
--
-- Admin-only tables and actions (provider_invites, app_settings, writing
-- consent_documents, reading audit_log, editing roles) are reached through
-- the SQL Editor, which runs as postgres. They get no client grant at all.
--
-- DEPENDS ON: 000 to 003 (tables and functions must exist).
--
-- SAFE TO RE-RUN: yes. It starts by removing and then re-adding the same
--   grants, so the result is always exactly what this file says. Re-run it
--   (and then 005) after any change to a grant.
--
-- HOW TO UNDO (closes the app completely; every client request is denied):
--   revoke all on all tables    in schema public from anon, authenticated;
--   revoke execute on function public.is_provider(), public.is_admin(),
--     public.is_assigned_provider(uuid), public.redeem_provider_invite(text),
--     public.set_my_language(text) from authenticated;
--
-- NOTE FOR LATER: every column you add to a table is readable by anyone who
-- can read the table's rows. Before adding a sensitive column, give it its
-- own table or restrict reads with a function.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Clean slate
-- ---------------------------------------------------------------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke create on schema public from public, anon, authenticated;   -- nobody creates objects in public through the API
grant usage on schema public to anon, authenticated;               -- same as 000; the schema stays visible


-- ---------------------------------------------------------------------
-- 2. Functions: EXECUTE is never given to PUBLIC or anon.
-- Trigger functions need no EXECUTE for anyone: triggers still fire.
-- Only five functions are callable by signed-in users.
-- ---------------------------------------------------------------------
revoke all on function public.set_updated_at()                from public, anon, authenticated;
revoke all on function public.guard_profile_role()            from public, anon, authenticated;
revoke all on function public.handle_new_user()               from public, anon, authenticated;
revoke all on function public.create_alerts_from_reading()    from public, anon, authenticated;
revoke all on function public.nl_enable_rls_on_new_tables()   from public, anon, authenticated;

revoke all on function public.is_provider()                   from public, anon, authenticated;
revoke all on function public.is_admin()                      from public, anon, authenticated;
revoke all on function public.is_assigned_provider(uuid)      from public, anon, authenticated;
revoke all on function public.redeem_provider_invite(text)    from public, anon, authenticated;
revoke all on function public.set_my_language(text)           from public, anon, authenticated;

grant execute on function public.is_provider()                to authenticated;  -- used inside policies and by the app for routing
grant execute on function public.is_admin()                   to authenticated;  -- used inside policies
grant execute on function public.is_assigned_provider(uuid)   to authenticated;  -- used inside policies
grant execute on function public.redeem_provider_invite(text) to authenticated;  -- provider invite screen
grant execute on function public.set_my_language(text)        to authenticated;  -- language toggle


-- ---------------------------------------------------------------------
-- 3. anon: nothing.
-- (No statement needed: step 1 removed everything and nothing below names anon.)
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- 4. authenticated: tables
-- Reads are table-wide (rows are limited by 005). Writes list their columns.
-- Columns that are NOT listed for insert get their default; columns that are
-- not listed for update cannot be changed at all.
-- ---------------------------------------------------------------------

-- profiles: rows are created only by the signup trigger. Users may change
-- language and display name. NOT role, NOT date_of_birth (a minor must not be
-- able to turn into an adult by editing it).
grant select on public.profiles to authenticated;
grant update (language, display_name) on public.profiles to authenticated;

-- pregnancy_profiles: the patient fills in the clinical details.
-- assigned_provider_id is NOT writable: assignment is made by the admin
-- (docs/ADMIN_SQL.md), otherwise anyone could give themselves access to a patient.
grant select on public.pregnancy_profiles to authenticated;
grant insert (patient_id, due_date, obstetric_history, conditions) on public.pregnancy_profiles to authenticated;
grant update (due_date, obstetric_history, conditions) on public.pregnancy_profiles to authenticated;

-- devices: patient pairs and updates their own belt and band.
grant select on public.devices to authenticated;
grant insert (patient_id, kind, label, hardware_id, battery_percent, last_seen_at, is_active) on public.devices to authenticated;
grant update (label, hardware_id, battery_percent, last_seen_at, is_active) on public.devices to authenticated;

-- belt_readings and maternal_vitals: append-only. No update, no delete, so a
-- recorded measurement cannot be rewritten afterwards. id and created_at
-- always come from the server.
grant select on public.belt_readings to authenticated;
grant insert (patient_id, device_id, measured_at, fetal_hr_bpm, signal_quality, confidence, signal_lost, source, client_id)
  on public.belt_readings to authenticated;

grant select on public.maternal_vitals to authenticated;
grant insert (patient_id, device_id, measured_at, heart_rate_bpm, spo2_percent, temperature_c, source, client_id)
  on public.maternal_vitals to authenticated;

-- alert_thresholds: providers read and edit the limits (005 enforces
-- "providers only"). Only the limits can be edited, never the alert_type, and
-- never is_confirmed (only the admin confirms, in the SQL Editor). No insert, no delete.
grant select on public.alert_thresholds to authenticated;
grant update (min_value, max_value, sustained_count, severity, enabled, notes) on public.alert_thresholds to authenticated;

-- alerts: normally created by the database. Patients may raise an SOS and
-- providers may add one (005 decides who). Providers update the handling
-- fields. Nobody can change the type, severity or patient of an existing alert.
grant select on public.alerts to authenticated;
grant insert (patient_id, alert_type, severity, details) on public.alerts to authenticated;
grant update (status, acknowledged_by, acknowledged_at, action_taken, resolved_at) on public.alerts to authenticated;

-- appointments: patient requests and cancels; provider schedules.
grant select on public.appointments to authenticated;
grant insert (patient_id, provider_id, starts_at, duration_minutes, status) on public.appointments to authenticated;
grant update (starts_at, duration_minutes, status) on public.appointments to authenticated;

-- consult_notes: provider notes. Patients hold the same grant but 005 gives
-- them no rows. No delete.
grant select on public.consult_notes to authenticated;
grant insert (patient_id, author_id, appointment_id, body, language) on public.consult_notes to authenticated;
grant update (body, language) on public.consult_notes to authenticated;

-- validation_pairs: provider-only research data (005). No delete.
grant select on public.validation_pairs to authenticated;
grant insert (session_id, patient_id, recorded_by, belt_reading_id, measured_at, gestational_age_weeks,
              belt_fhr_bpm, doppler_fhr_bpm, session_consent_confirmed)
  on public.validation_pairs to authenticated;
grant update (measured_at, gestational_age_weeks, belt_fhr_bpm, doppler_fhr_bpm, session_consent_confirmed,
              ob_signoff_by, ob_signoff_at, pediatrician_signoff_by, pediatrician_signoff_at)
  on public.validation_pairs to authenticated;

-- consent_documents: read only. Written by the admin in the SQL Editor.
grant select on public.consent_documents to authenticated;

-- consent_records: a user accepts (insert) and withdraws (update withdrawn_at
-- only). accepted_at is always the server time.
grant select on public.consent_records to authenticated;
grant insert (user_id, document_id) on public.consent_records to authenticated;
grant update (withdrawn_at) on public.consent_records to authenticated;

-- deletion_requests: patient asks; the admin handles it in the SQL Editor.
grant select on public.deletion_requests to authenticated;
grant insert (patient_id, note) on public.deletion_requests to authenticated;

-- audit_log: providers write entries. NOBODY reads it from the client (no
-- select grant): the admin reads it in the SQL Editor. This also means the app
-- must insert WITHOUT asking for the row back (no ".select()" after ".insert()").
grant insert (actor_id, patient_id, action, details) on public.audit_log to authenticated;

-- provider_invites and app_settings: no client access at all (no grant).
-- Invites are made and read in the SQL Editor; redeem_provider_invite() is the
-- only door. app_settings is changed in the SQL Editor (docs/ADMIN_SQL.md).
