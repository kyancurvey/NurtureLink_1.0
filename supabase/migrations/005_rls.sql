-- =====================================================================
-- 005_rls.sql
-- NurtureLink: Row Level Security. Lock 2 of 2: which ROWS each signed-in
-- user may read or change. (Lock 1, the grants, is in 004.)
--
-- WHAT IT DOES
--   1. Turns RLS on for EVERY table in public (default deny).
--   2. Removes every existing policy in public, then creates the policies
--      below. So the policies in the database always equal this file.
--   3. Adds one small trigger that protects the alert limits (see section 4).
--
-- WHO SEES WHAT (summary)
--   patient   own rows only. Never provider notes, validation pairs, the
--             audit log, the alert limits or other patients.
--   provider  rows of patients ASSIGNED to them (is_assigned_provider).
--             Assignment is made by the admin in the SQL Editor, never by the
--             provider, so a provider cannot give themselves access.
--   admin     works in the SQL Editor. A signed-in admin account additionally
--             sees all deletion requests and unpublished consent documents.
--   anon      nothing (no grant, no policy).
--   Roles are read from the profiles table through is_provider(), is_admin()
--   and is_assigned_provider(). Never from the JWT or user_metadata.
--
-- DEPENDS ON: 001 (tables), 002 (helper functions), 004 (grants).
--
-- SAFE TO RE-RUN: yes. Every policy is dropped before it is created.
--
-- HOW TO UNDO (everything is denied again; RLS stays ON):
--   do $$ declare p record; begin
--     for p in select policyname, tablename from pg_policies where schemaname = 'public' loop
--       execute format('drop policy %I on public.%I', p.policyname, p.tablename);
--     end loop; end $$;
--   drop trigger if exists alert_thresholds_guard on public.alert_thresholds;
--   drop function if exists public.guard_threshold_update();
--
-- Policy style: "(select auth.uid())" is written with a select so Postgres
-- evaluates it once per query instead of once per row.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. RLS on for every table in public, including any not known to this file
-- ---------------------------------------------------------------------
do $$
declare
  t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end
$$;


-- ---------------------------------------------------------------------
-- 2. Clean slate: remove every policy, so nothing old or hand-made survives.
-- (During the next few statements every table is simply "deny all".)
-- ---------------------------------------------------------------------
do $$
declare
  p record;
begin
  for p in select policyname, tablename from pg_policies where schemaname = 'public'
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end
$$;


-- ---------------------------------------------------------------------
-- 3. Policies
-- ---------------------------------------------------------------------

-- ===== profiles =====================================================
-- Read: your own row, or the row of a patient assigned to you.
-- (A patient does NOT get to read their provider's profile: the profile
--  holds a date of birth. Add a small function for it later if needed.)
-- Update: your own row only; the column grant limits it to language and
-- display_name. No insert (signup trigger) and no delete.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_assigned_provider(id));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));


-- ===== pregnancy_profiles ===========================================
drop policy if exists pregnancy_profiles_select on public.pregnancy_profiles;
create policy pregnancy_profiles_select on public.pregnancy_profiles
  for select to authenticated
  using (patient_id = (select auth.uid()) or public.is_assigned_provider(patient_id));

drop policy if exists pregnancy_profiles_insert_own on public.pregnancy_profiles;
create policy pregnancy_profiles_insert_own on public.pregnancy_profiles
  for insert to authenticated
  with check (patient_id = (select auth.uid()));

drop policy if exists pregnancy_profiles_update_own on public.pregnancy_profiles;
create policy pregnancy_profiles_update_own on public.pregnancy_profiles
  for update to authenticated
  using (patient_id = (select auth.uid()))
  with check (patient_id = (select auth.uid()));


-- ===== devices ======================================================
drop policy if exists devices_select on public.devices;
create policy devices_select on public.devices
  for select to authenticated
  using (patient_id = (select auth.uid()) or public.is_assigned_provider(patient_id));

drop policy if exists devices_insert_own on public.devices;
create policy devices_insert_own on public.devices
  for insert to authenticated
  with check (patient_id = (select auth.uid()));

drop policy if exists devices_update_own on public.devices;
create policy devices_update_own on public.devices
  for update to authenticated
  using (patient_id = (select auth.uid()))
  with check (patient_id = (select auth.uid()));


-- ===== belt_readings / maternal_vitals (append-only) =================
-- A patient may only add readings for themselves, and only with one of their
-- own devices (so a reading cannot point at someone else's device id).
drop policy if exists belt_readings_select on public.belt_readings;
create policy belt_readings_select on public.belt_readings
  for select to authenticated
  using (patient_id = (select auth.uid()) or public.is_assigned_provider(patient_id));

drop policy if exists belt_readings_insert_own on public.belt_readings;
create policy belt_readings_insert_own on public.belt_readings
  for insert to authenticated
  with check (
    patient_id = (select auth.uid())
    and (device_id is null
         or exists (select 1 from public.devices d
                    where d.id = belt_readings.device_id and d.patient_id = (select auth.uid())))
  );

drop policy if exists maternal_vitals_select on public.maternal_vitals;
create policy maternal_vitals_select on public.maternal_vitals
  for select to authenticated
  using (patient_id = (select auth.uid()) or public.is_assigned_provider(patient_id));

drop policy if exists maternal_vitals_insert_own on public.maternal_vitals;
create policy maternal_vitals_insert_own on public.maternal_vitals
  for insert to authenticated
  with check (
    patient_id = (select auth.uid())
    and (device_id is null
         or exists (select 1 from public.devices d
                    where d.id = maternal_vitals.device_id and d.patient_id = (select auth.uid())))
  );


-- ===== alert_thresholds (global limits, providers only) ==============
-- The limits are not per patient, so "assigned patients" cannot apply: any
-- provider may edit them. Section 4 limits the damage (resets the medical
-- officer confirmation and writes the audit log). Patients get no rows.
drop policy if exists alert_thresholds_select_provider on public.alert_thresholds;
create policy alert_thresholds_select_provider on public.alert_thresholds
  for select to authenticated
  using ((select public.is_provider()));

drop policy if exists alert_thresholds_update_provider on public.alert_thresholds;
create policy alert_thresholds_update_provider on public.alert_thresholds
  for update to authenticated
  using ((select public.is_provider()))
  with check ((select public.is_provider()));


-- ===== alerts =======================================================
-- Read: own alerts, or alerts of assigned patients.
-- Insert: a patient may raise an SOS for themselves (nothing else, so they
--   cannot fake a clinical alert); a provider may add one for an assigned patient.
-- Update: assigned providers only (acknowledge, action taken, resolve).
--   Patients get no update on purpose: if a patient could acknowledge an alert
--   it would vanish from the provider's "unacknowledged" queue.
drop policy if exists alerts_select on public.alerts;
create policy alerts_select on public.alerts
  for select to authenticated
  using (patient_id = (select auth.uid()) or public.is_assigned_provider(patient_id));

drop policy if exists alerts_insert_patient_sos on public.alerts;
create policy alerts_insert_patient_sos on public.alerts
  for insert to authenticated
  with check (patient_id = (select auth.uid()) and alert_type = 'sos' and severity = 'critical');

drop policy if exists alerts_insert_provider on public.alerts;
create policy alerts_insert_provider on public.alerts
  for insert to authenticated
  with check (public.is_assigned_provider(patient_id));

drop policy if exists alerts_update_provider on public.alerts;
create policy alerts_update_provider on public.alerts
  for update to authenticated
  using (public.is_assigned_provider(patient_id))
  with check (
    public.is_assigned_provider(patient_id)
    and (acknowledged_by is null or acknowledged_by = (select auth.uid()))   -- no signing off as someone else
  );


-- ===== appointments =================================================
-- Patient: request (status 'requested', with their own assigned provider or
--   none), then reschedule or cancel. A patient cannot confirm or complete.
-- Provider: schedule, confirm, complete, cancel for assigned patients.
drop policy if exists appointments_select on public.appointments;
create policy appointments_select on public.appointments
  for select to authenticated
  using (patient_id = (select auth.uid()) or public.is_assigned_provider(patient_id));

drop policy if exists appointments_insert_patient on public.appointments;
create policy appointments_insert_patient on public.appointments
  for insert to authenticated
  with check (
    patient_id = (select auth.uid())
    and status = 'requested'
    and (provider_id is null
         or provider_id = (select pp.assigned_provider_id from public.pregnancy_profiles pp
                           where pp.patient_id = (select auth.uid())))
  );

drop policy if exists appointments_insert_provider on public.appointments;
create policy appointments_insert_provider on public.appointments
  for insert to authenticated
  with check (
    public.is_assigned_provider(patient_id)
    and (provider_id is null or provider_id = (select auth.uid()))
  );

drop policy if exists appointments_update_patient on public.appointments;
create policy appointments_update_patient on public.appointments
  for update to authenticated
  using (patient_id = (select auth.uid()) and status in ('requested', 'scheduled'))
  with check (patient_id = (select auth.uid()) and status in ('requested', 'cancelled'));

drop policy if exists appointments_update_provider on public.appointments;
create policy appointments_update_provider on public.appointments
  for update to authenticated
  using (public.is_assigned_provider(patient_id))
  with check (public.is_assigned_provider(patient_id));


-- ===== consult_notes (providers only) ================================
-- A provider reads notes of assigned patients and edits only notes they wrote.
-- Patients get no rows.
drop policy if exists consult_notes_select_provider on public.consult_notes;
create policy consult_notes_select_provider on public.consult_notes
  for select to authenticated
  using (public.is_assigned_provider(patient_id));

drop policy if exists consult_notes_insert_provider on public.consult_notes;
create policy consult_notes_insert_provider on public.consult_notes
  for insert to authenticated
  with check (
    public.is_assigned_provider(patient_id)
    and author_id = (select auth.uid())
    and (appointment_id is null
         or exists (select 1 from public.appointments a
                    where a.id = consult_notes.appointment_id and a.patient_id = consult_notes.patient_id))
  );

drop policy if exists consult_notes_update_own_provider on public.consult_notes;
create policy consult_notes_update_own_provider on public.consult_notes
  for update to authenticated
  using (public.is_assigned_provider(patient_id) and author_id = (select auth.uid()))
  with check (public.is_assigned_provider(patient_id) and author_id = (select auth.uid()));


-- ===== validation_pairs (providers only) =============================
-- Sign-offs must carry the signer's own id, and one person cannot give both
-- the OB and the pediatrician sign-off. (A second signer cannot see the row
-- yet: only the assigned provider can. The second sign-off is recorded by the
-- admin in the SQL Editor until a validation-team design exists.)
drop policy if exists validation_pairs_select_provider on public.validation_pairs;
create policy validation_pairs_select_provider on public.validation_pairs
  for select to authenticated
  using (public.is_assigned_provider(patient_id));

drop policy if exists validation_pairs_insert_provider on public.validation_pairs;
create policy validation_pairs_insert_provider on public.validation_pairs
  for insert to authenticated
  with check (
    public.is_assigned_provider(patient_id)
    and recorded_by = (select auth.uid())
    and (belt_reading_id is null
         or exists (select 1 from public.belt_readings b
                    where b.id = validation_pairs.belt_reading_id and b.patient_id = validation_pairs.patient_id))
  );

drop policy if exists validation_pairs_update_provider on public.validation_pairs;
create policy validation_pairs_update_provider on public.validation_pairs
  for update to authenticated
  using (public.is_assigned_provider(patient_id))
  with check (
    public.is_assigned_provider(patient_id)
    and (ob_signoff_by is null or ob_signoff_by = (select auth.uid()))
    and (pediatrician_signoff_by is null or pediatrician_signoff_by = (select auth.uid()))
    and (ob_signoff_by is null or ob_signoff_by is distinct from pediatrician_signoff_by)
  );


-- ===== consent_documents ============================================
-- Any signed-in user reads PUBLISHED documents. Admin accounts also see drafts.
-- No write policy and no write grant: the admin edits in the SQL Editor.
drop policy if exists consent_documents_select on public.consent_documents;
create policy consent_documents_select on public.consent_documents
  for select to authenticated
  using (is_published or (select public.is_admin()));


-- ===== consent_records ==============================================
-- Read and add your own, for published documents only. The only change allowed
-- afterwards is withdrawing once (withdrawn_at is set, never cleared).
drop policy if exists consent_records_select_own on public.consent_records;
create policy consent_records_select_own on public.consent_records
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists consent_records_insert_own on public.consent_records;
create policy consent_records_insert_own on public.consent_records
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.consent_documents d
                where d.id = consent_records.document_id and d.is_published)
  );

drop policy if exists consent_records_withdraw_own on public.consent_records;
create policy consent_records_withdraw_own on public.consent_records
  for update to authenticated
  using (user_id = (select auth.uid()) and withdrawn_at is null)
  with check (user_id = (select auth.uid()) and withdrawn_at is not null);


-- ===== deletion_requests ============================================
-- A patient files and reads their own. An admin account reads all. The admin
-- completes requests in the SQL Editor (no client update).
drop policy if exists deletion_requests_select on public.deletion_requests;
create policy deletion_requests_select on public.deletion_requests
  for select to authenticated
  using (patient_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists deletion_requests_insert_own on public.deletion_requests;
create policy deletion_requests_insert_own on public.deletion_requests
  for insert to authenticated
  with check (patient_id = (select auth.uid()));


-- ===== audit_log ====================================================
-- Insert-only, and only for providers, and only as themselves, and only about
-- their own assigned patients (or about nobody). No read policy: the admin
-- reads the log in the SQL Editor.
drop policy if exists audit_log_insert_provider on public.audit_log;
create policy audit_log_insert_provider on public.audit_log
  for insert to authenticated
  with check (
    (select public.is_provider())
    and actor_id = (select auth.uid())
    and (patient_id is null or public.is_assigned_provider(patient_id))
  );


-- ===== provider_invites, app_settings: no client access ==============
-- No grant exists either. These explicit "deny" policies document the intent
-- and keep Supabase's advisor from reporting "RLS enabled, no policy".
drop policy if exists provider_invites_no_client_access on public.provider_invites;
create policy provider_invites_no_client_access on public.provider_invites
  for all to authenticated
  using (false) with check (false);

drop policy if exists app_settings_no_client_access on public.app_settings;
create policy app_settings_no_client_access on public.app_settings
  for all to authenticated
  using (false) with check (false);


-- ---------------------------------------------------------------------
-- 4. Guard for the alert limits
-- Any provider can edit the global limits, and a weaker limit means fewer
-- alerts for every patient. So when a signed-in user (not the SQL Editor)
-- changes a limit, this trigger:
--   * stamps updated_by with who did it,
--   * sets is_confirmed back to false (the medical officer approved the OLD
--     numbers, not these), and
--   * writes an audit_log row with the old and new values.
-- SECURITY INVOKER on purpose: it runs with the editor's own rights, so the
-- audit insert goes through the normal audit_log policy.
-- ---------------------------------------------------------------------
create or replace function public.guard_threshold_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated') then
    new.updated_by := (select auth.uid());

    if (new.min_value, new.max_value, new.sustained_count, new.severity, new.enabled)
       is distinct from
       (old.min_value, old.max_value, old.sustained_count, old.severity, old.enabled) then

      new.is_confirmed := false;

      insert into public.audit_log (actor_id, action, details)
      values (
        (select auth.uid()),
        'alert_threshold_updated',
        jsonb_build_object(
          'alert_type', old.alert_type,
          'old', jsonb_build_object('min', old.min_value, 'max', old.max_value, 'readings', old.sustained_count,
                                    'severity', old.severity, 'enabled', old.enabled),
          'new', jsonb_build_object('min', new.min_value, 'max', new.max_value, 'readings', new.sustained_count,
                                    'severity', new.severity, 'enabled', new.enabled)
        )
      );
    end if;
  end if;
  return new;
end
$$;
revoke all on function public.guard_threshold_update() from public, anon, authenticated;

drop trigger if exists alert_thresholds_guard on public.alert_thresholds;
create trigger alert_thresholds_guard
  before update on public.alert_thresholds
  for each row execute function public.guard_threshold_update();
