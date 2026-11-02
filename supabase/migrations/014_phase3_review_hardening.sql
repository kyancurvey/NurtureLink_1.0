-- =====================================================================
-- 014_phase3_review_hardening.sql
-- NurtureLink step 3.6 (Phase 3 review): four small fixes found by the attacker
-- pass. None of them lets anyone read another person's data (that was tried
-- and refused everywhere); they stop one signed-in account from filling the
-- database, and stop any provider from silencing the alerts of every patient.
--
-- WHAT IT DOES
--   1. READING CAP (HIGH). A patient could insert unlimited readings: in a local
--      test one account wrote 100,000 rows in about 3 seconds. Now an API request
--      (anon / authenticated) for the caller's OWN patient_id is refused with
--      'too_many_readings' once that patient already has 600 rows in that table
--      created in the last hour. Applies to belt_readings and maternal_vitals,
--      to every source (typed, simulator, device). Counted by created_at (server
--      time), so a back-dated measured_at does not help. The SQL Editor, the seed
--      and service_role are not limited. One index per table keeps the count fast.
--   2. DEVICE LIMITS (MEDIUM-HIGH). At most 5 device rows per patient
--      ('too_many_devices'), and hardware_id at most 100 characters (the existing
--      label limit is also 100). Existing rows are not re-checked (NOT VALID).
--   3. ALERT LIMITS ARE ADMIN-ONLY (HIGH). Any provider, assigned or not, could
--      edit the 4 global alert limits and so switch off alerts for every patient.
--      Now authenticated has NO update privilege on alert_thresholds and the
--      provider update policy is gone. Providers still READ the limits. The admin
--      changes them in the SQL Editor (docs/ADMIN_SQL.md, snippet 6). The old
--      guard trigger stays (harmless: the SQL Editor is not an API role).
--   4. JSON SIZE CAP (MEDIUM-HIGH). alerts.details and audit_log.details accepted
--      any size (one 9.6 MB SOS row was stored in under a second). Now an API
--      insert whose details text is over 2000 bytes is refused with
--      'details_too_large'. The app's SOS sends no details; the alert trigger
--      (runs as the database owner) is not affected.
--
-- ALL NUMBERS (600 per hour, 5 devices, 100 characters, 2000 bytes) ARE DRAFT
-- DEFAULTS chosen by the project owner on 2026-11-02, pending the medical officer
-- and the Phase 5 device design. To change one, edit the constant in this file
-- and run it again.
--
-- DEPENDS ON: 000 to 013.
--
-- SAFE TO RE-RUN: yes ("create or replace", "drop trigger if exists",
--   "create index if not exists", the constraint is added only if missing,
--   revoke and drop policy if exists).
--
-- ALSO EDITED IN THIS STEP so a re-run of the old files does not undo this one:
--   004_grants.sql  (the alert_thresholds UPDATE grant is removed)
--   005_rls.sql     (the alert_thresholds provider UPDATE policy is removed)
--   access_tests.sql (the checks that expected provider edits now expect refusal)
--
-- HOW TO UNDO (each part on its own):
--   1. drop trigger if exists belt_readings_guard_rate on public.belt_readings;
--      drop trigger if exists maternal_vitals_guard_rate on public.maternal_vitals;
--      drop function if exists public.guard_reading_rate();
--   2. drop trigger if exists devices_guard_limits on public.devices;
--      drop function if exists public.guard_device_limits();
--      alter table public.devices drop constraint if exists devices_hardware_id_length;
--   3. grant update (min_value, max_value, sustained_count, severity, enabled, notes)
--        on public.alert_thresholds to authenticated;
--      then re-create policy alert_thresholds_update_provider from the original
--      005 (for update to authenticated using and with check (select public.is_provider())).
--      (This reopens the risk: do it only if you accept it.)
--   4. drop trigger if exists alerts_guard_details on public.alerts;
--      drop trigger if exists audit_log_guard_details on public.audit_log;
--      drop function if exists public.guard_details_size();
--   The two indexes can stay (drop index if exists public.belt_readings_patient_created_idx,
--   public.maternal_vitals_patient_created_idx).
--   Then edit supabase/tests/014_phase3_review_tests.sql accordingly (or stop using it).
--
-- SECURITY NOTES
--   * Three new trigger functions, all SECURITY INVOKER with a fixed search_path.
--     EXECUTE is revoked from everyone (a trigger needs no EXECUTE). No new
--     client-callable function: the client function count stays 14.
--   * Every guard acts only when current_user is an API role. The caps for readings
--     and devices additionally apply only when patient_id = auth.uid() (a request
--     for someone else's patient_id is refused by RLS anyway, and must never take
--     that person's lock). Per-patient advisory locks make the counts exact when
--     two requests arrive together.
--   * No grant is added anywhere. Nothing is granted to anon.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Reading cap
-- ---------------------------------------------------------------------
create index if not exists belt_readings_patient_created_idx
  on public.belt_readings (patient_id, created_at desc);
create index if not exists maternal_vitals_patient_created_idx
  on public.maternal_vitals (patient_id, created_at desc);

create or replace function public.guard_reading_rate()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  c_max    constant integer  := 600;                 -- rows per patient, per table
  c_window constant interval := interval '1 hour';
  v_count  integer;
begin
  if current_user in ('anon', 'authenticated')
     and new.patient_id = (select auth.uid()) then

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('nl_rate:' || tg_table_name || ':' || new.patient_id::text, 0));

    if tg_table_name = 'belt_readings' then
      select count(*) into v_count from (
        select 1 from public.belt_readings r
        where r.patient_id = new.patient_id and r.created_at > now() - c_window
        limit c_max
      ) s;
    else  -- maternal_vitals
      select count(*) into v_count from (
        select 1 from public.maternal_vitals r
        where r.patient_id = new.patient_id and r.created_at > now() - c_window
        limit c_max
      ) s;
    end if;

    if v_count >= c_max then
      raise exception 'too_many_readings';
    end if;
  end if;
  return new;
end
$$;
revoke all on function public.guard_reading_rate() from public, anon, authenticated;

drop trigger if exists belt_readings_guard_rate on public.belt_readings;
create trigger belt_readings_guard_rate
  before insert on public.belt_readings
  for each row execute function public.guard_reading_rate();

drop trigger if exists maternal_vitals_guard_rate on public.maternal_vitals;
create trigger maternal_vitals_guard_rate
  before insert on public.maternal_vitals
  for each row execute function public.guard_reading_rate();


-- ---------------------------------------------------------------------
-- 2. Device limits
-- ---------------------------------------------------------------------
create or replace function public.guard_device_limits()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  c_max constant integer := 5;                       -- device rows per patient
begin
  if current_user in ('anon', 'authenticated')
     and new.patient_id = (select auth.uid()) then

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('nl_devices:' || new.patient_id::text, 0));

    if (select count(*) from public.devices d where d.patient_id = new.patient_id) >= c_max then
      raise exception 'too_many_devices';
    end if;
  end if;
  return new;
end
$$;
revoke all on function public.guard_device_limits() from public, anon, authenticated;

drop trigger if exists devices_guard_limits on public.devices;
create trigger devices_guard_limits
  before insert on public.devices
  for each row execute function public.guard_device_limits();

-- hardware_id length: NOT VALID = checked for every new or changed row, existing
-- rows are left alone (so this cannot fail on data that is already there).
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'devices_hardware_id_length' and conrelid = 'public.devices'::regclass) then
    alter table public.devices
      add constraint devices_hardware_id_length
      check (hardware_id is null or char_length(hardware_id) <= 100) not valid;
  end if;
end
$$;


-- ---------------------------------------------------------------------
-- 3. Alert limits: admin-only
-- (providers keep SELECT and the alert_thresholds_select_provider policy)
-- ---------------------------------------------------------------------
revoke update on public.alert_thresholds from authenticated;
drop policy if exists alert_thresholds_update_provider on public.alert_thresholds;


-- ---------------------------------------------------------------------
-- 4. JSON size cap for alerts.details and audit_log.details
-- ---------------------------------------------------------------------
create or replace function public.guard_details_size()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  c_max_bytes constant integer := 2000;
begin
  if current_user in ('anon', 'authenticated')
     and octet_length(new.details::text) > c_max_bytes then
    raise exception 'details_too_large';
  end if;
  return new;
end
$$;
revoke all on function public.guard_details_size() from public, anon, authenticated;

drop trigger if exists alerts_guard_details on public.alerts;
create trigger alerts_guard_details
  before insert on public.alerts
  for each row execute function public.guard_details_size();

drop trigger if exists audit_log_guard_details on public.audit_log;
create trigger audit_log_guard_details
  before insert on public.audit_log
  for each row execute function public.guard_details_size();


-- ---------------------------------------------------------------------
-- Check (read-only). Expect exactly 9 rows:
--   1 row  alert_thresholds: signed-in update = false, signed-in select = true, update policies = 0
--   3 rows function (guard_details_size, guard_device_limits, guard_reading_rate):
--          security_definer = false, anon can run = false, signed-in can run = false
--   5 rows trigger (alerts_guard_details, audit_log_guard_details, devices_guard_limits,
--          belt_readings_guard_rate, maternal_vitals_guard_rate): every one enabled = O
-- ---------------------------------------------------------------------
select 'trigger' as what, c.relname::text || '.' || t.tgname::text || ': enabled = ' || t.tgenabled::text as detail
from pg_trigger t join pg_class c on c.oid = t.tgrelid
where c.relnamespace = 'public'::regnamespace and not t.tgisinternal
  and t.tgname in ('belt_readings_guard_rate', 'maternal_vitals_guard_rate', 'devices_guard_limits',
                   'alerts_guard_details', 'audit_log_guard_details')
union all
select 'function', p.proname::text || ': security_definer = ' || p.prosecdef::text
       || ', anon can run = ' || has_function_privilege('anon', p.oid, 'execute')::text
       || ', signed-in can run = ' || has_function_privilege('authenticated', p.oid, 'execute')::text
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('guard_reading_rate', 'guard_device_limits', 'guard_details_size')
union all
select 'alert_thresholds',
       'signed-in update = ' || (has_table_privilege('authenticated', 'public.alert_thresholds', 'UPDATE')
                                 or exists (select 1 from pg_attribute a
                                            where a.attrelid = 'public.alert_thresholds'::regclass and a.attnum > 0
                                              and not a.attisdropped
                                              and has_column_privilege('authenticated', 'public.alert_thresholds', a.attnum, 'UPDATE')))::text
       || ', signed-in select = ' || has_table_privilege('authenticated', 'public.alert_thresholds', 'SELECT')::text
       || ', update policies = ' || (select count(*) from pg_policies
                                     where schemaname = 'public' and tablename = 'alert_thresholds' and cmd in ('UPDATE', 'ALL'))::text
order by 1, 2;
