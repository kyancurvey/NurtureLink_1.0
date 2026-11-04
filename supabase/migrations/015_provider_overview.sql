-- =====================================================================
-- 015_provider_overview.sql
-- NurtureLink step 4.1: the database side of the provider Overview tab.
--
-- WHAT IT DOES
--   1. public.status_fresh_hours() - a tiny SECURITY DEFINER helper that
--      returns ONE whole number: how many hours a belt check counts as
--      "recent". It reads the same setting as my_home_status() (009), with the
--      same rule (a whole number from 1 to 168, anything else gives 14).
--      Why it exists: providers cannot read app_settings (no grant, policy
--      "using (false)"), so a function that runs with the provider's own rights
--      cannot read that setting itself. The number is the same for everybody
--      and patients already receive it inside my_home_status(), so this
--      discloses nothing new.
--   2. public.provider_overview() - a SECURITY INVOKER function the signed-in
--      PROVIDER calls to get the triage list of their ASSIGNED patients, one row
--      per patient, already sorted by priority. Columns (nothing else):
--        patient_id        the patient's id (the detail route needs it)
--        label_code        first 6 hex characters of the id, upper case
--                          ("Patient 7F3A12" on screen); computed here
--        display_name      the name the patient chose (trimmed; null if none).
--                          Unverified text: show it as plain text, never as verified.
--        status            urgent | attention | no_recent_data | ok
--                          (the same four codes and the same rules as
--                          my_home_status(); the screen words them Critical,
--                          Warning, No recent data, Stable)
--        last_check_at     time of the newest belt check (null = no check yet)
--        open_alert_count  open alerts including an SOS (acknowledged and
--                          resolved alerts do not count)
--        sos_open          true if an SOS is open
--        sos_since         time of the OLDEST open SOS (null if none)
--        missed_check      true if there is no belt check inside the last
--                          status_fresh_hours() hours (or none at all)
--      It never reads or returns a date of birth, an email, readings values,
--      history, notes or an alert's details.
--
-- WHY INVOKER, NOT DEFINER (the safety design)
--   "authenticated" is ONE database role shared by patients, providers and
--   admins. If this function ran as its owner (SECURITY DEFINER) it would bypass
--   row-level security, so one mistake in its own WHERE clause would show every
--   patient's status to every signed-in account. As SECURITY INVOKER it runs
--   with the caller's rights, so the database's own policies (005) limit every
--   table it reads to the caller's assigned patients. On top of that it
--   (a) returns nothing unless the caller is a provider, and (b) filters
--   pregnancy_profiles.assigned_provider_id = auth.uid() itself: two locks.
--   A patient, an admin, a provider with no patients and anon all get NO rows
--   (anon cannot even call it: no EXECUTE). It takes no argument, so nobody can
--   ask about a patient by id.
--
-- STATUS RULES (copied from 009 on purpose; 009 and the live patient Home are
--   NOT changed by this file; supabase/tests/015_provider_overview_tests.sql
--   proves both functions give the same status for the same patient)
--   urgent          an open SOS, or an open non-SOS alert with severity critical
--   attention       an open alert with a lower severity, OR (inside the freshness
--                   window) the latest belt check lost the signal or its heart
--                   rate is outside the limits, OR the latest SpO2 in the window is
--                   below its minimum, OR the latest temperature in the window is
--                   above its maximum (limits from alert_thresholds, only when that
--                   threshold is enabled)
--   no_recent_data  none of the above, and no belt check inside the window
--   ok              a recent belt check, usable, inside the limits, nothing open
--   An open alert is never hidden by old data. "no_recent_data" is never "ok".
--
-- MISSED CHECK (DRAFT, pending medical officer; replaced by per-patient wear
--   schedules in step 4.5)
--   missed_check = no belt check (any source, including a signal-lost check and a
--   typed one) with measured_at inside the last status_fresh_hours() hours.
--   measured_at is inclusive: a check exactly that old is NOT missed. Maternal
--   vitals alone do not count. It is independent of status: an open alert can
--   outrank stale data and the flag still shows.
--
-- SORT ORDER (DRAFT, pending medical officer: the position of no_recent_data)
--   1 open SOS, 2 urgent, 3 attention, 4 no_recent_data, 5 ok. Ties: missed
--   check first, then more open alerts, then the OLDEST last check (no check
--   yet first), then patient_id so the order never jumps.
--
-- DEPENDS ON: 000 to 014 (009 for the setting row; 001, 004, 005 for tables and rows).
--
-- SAFE TO RE-RUN: yes ("create or replace"; the grants are repeated).
--   Re-running 004 or 005 does not touch these two functions' grants.
--
-- HOW TO UNDO:
--   drop function if exists public.provider_overview();
--   drop function if exists public.status_fresh_hours();
--   Then in supabase/tests/access_tests.sql and 014_phase3_review_tests.sql change the
--   expected list of client functions back to the original fourteen (remove
--   provider_overview and status_fresh_hours), and delete 015_provider_overview_tests.sql.
--
-- SECURITY NOTES
--   * status_fresh_hours is SECURITY DEFINER only because providers cannot read
--     app_settings. Fixed search_path, every name schema-qualified, no arguments,
--     returns one integer. EXECUTE revoked from PUBLIC and anon, granted to
--     authenticated only.
--   * provider_overview is SECURITY INVOKER with a fixed search_path. EXECUTE
--     revoked from PUBLIC and anon, granted to authenticated (it must be callable
--     by the signed-in provider; for everyone else it returns no rows).
--   * Nothing here changes any table grant or RLS policy. No grant to anon.
--     No DELETE. No GRANT ALL.
--   * The audit row for "provider looked at the Overview" is written by the app
--     (action overview_viewed). audit_log.action has only a length check (1 to
--     64 characters), so the new action value needs no migration.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. The freshness helper (same rule as 009: whole number 1 to 168, else 14)
-- The cast sits inside a nested CASE so it only runs on text that is digits.
-- ---------------------------------------------------------------------
create or replace function public.status_fresh_hours()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select case when s.value ~ '^[0-9]{1,3}$'
                 then case when s.value::integer between 1 and 168 then s.value::integer end
            end
       from public.app_settings s
      where s.key = 'status_fresh_hours'),
    14);
$$;

revoke all on function public.status_fresh_hours() from public, anon, authenticated;
grant execute on function public.status_fresh_hours() to authenticated;


-- ---------------------------------------------------------------------
-- 2. The triage function (runs with the CALLER's rights)
-- ---------------------------------------------------------------------
create or replace function public.provider_overview()
returns table (
  patient_id       uuid,
  label_code       text,
  display_name     text,
  status           text,
  last_check_at    timestamptz,
  open_alert_count integer,
  sos_open         boolean,
  sos_since        timestamptz,
  missed_check     boolean
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid      uuid := auth.uid();
  v_hours    integer;
  v_cut      timestamptz;
  v_fhr_min  numeric;
  v_fhr_max  numeric;
  v_spo2_min numeric;
  v_temp_max numeric;
begin
  -- Lock 1: only a signed-in provider gets anything. Everyone else: no rows.
  if v_uid is null or not public.is_provider() then
    return;
  end if;

  v_hours := public.status_fresh_hours();
  v_cut   := now() - make_interval(hours => v_hours);

  -- The limits (providers may read alert_thresholds). Only enabled limits count;
  -- a missing or disabled limit leaves its variable null, which never flags.
  select t.min_value, t.max_value into v_fhr_min, v_fhr_max
  from public.alert_thresholds t
  where t.alert_type = 'fhr_out_of_range' and t.enabled;

  select t.min_value into v_spo2_min
  from public.alert_thresholds t
  where t.alert_type = 'low_spo2' and t.enabled;

  select t.max_value into v_temp_max
  from public.alert_thresholds t
  where t.alert_type = 'fever' and t.enabled;

  return query
  select
    s.patient_id,
    upper(left(s.patient_id::text, 6)),
    s.display_name,
    s.status,
    s.last_check_at,
    s.open_alert_count,
    s.sos_open,
    s.sos_since,
    s.missed_check
  from (
    select
      pp.patient_id                                         as patient_id,
      nullif(btrim(pr.display_name), '')                    as display_name,
      case
        when coalesce(al.sos, false) or coalesce(al.crit, false)
          then 'urgent'
        when coalesce(al.other, false)
          or (bb.measured_at >= v_cut and bb.signal_lost)
          or (bb.measured_at >= v_cut and not bb.signal_lost and bb.fetal_hr_bpm is not null
              and ((v_fhr_min is not null and bb.fetal_hr_bpm < v_fhr_min)
                or (v_fhr_max is not null and bb.fetal_hr_bpm > v_fhr_max)))
          or (sp.spo2_percent is not null and v_spo2_min is not null and sp.spo2_percent < v_spo2_min)
          or (tp.temperature_c is not null and v_temp_max is not null and tp.temperature_c > v_temp_max)
          then 'attention'
        when bb.measured_at is null or bb.measured_at < v_cut
          then 'no_recent_data'
        else 'ok'
      end                                                   as status,
      bb.measured_at                                        as last_check_at,
      coalesce(al.open_count, 0)::integer                   as open_alert_count,
      coalesce(al.sos, false)                               as sos_open,
      al.sos_since                                          as sos_since,
      (bb.measured_at is null or bb.measured_at < v_cut)    as missed_check
    from public.pregnancy_profiles pp
    -- Lock 2 is the WHERE below; the caller's RLS (005) limits every table here too.
    left join public.profiles pr on pr.id = pp.patient_id
    left join lateral (
      select b.measured_at, b.signal_lost, b.fetal_hr_bpm
      from public.belt_readings b
      where b.patient_id = pp.patient_id
      order by b.measured_at desc, b.created_at desc
      limit 1
    ) bb on true
    left join lateral (
      select m.spo2_percent
      from public.maternal_vitals m
      where m.patient_id = pp.patient_id and m.spo2_percent is not null and m.measured_at >= v_cut
      order by m.measured_at desc, m.created_at desc
      limit 1
    ) sp on true
    left join lateral (
      select m.temperature_c
      from public.maternal_vitals m
      where m.patient_id = pp.patient_id and m.temperature_c is not null and m.measured_at >= v_cut
      order by m.measured_at desc, m.created_at desc
      limit 1
    ) tp on true
    left join lateral (
      select count(*)                                                                  as open_count,
             bool_or(a.alert_type = 'sos')                                             as sos,
             bool_or(a.alert_type <> 'sos' and a.severity = 'critical')                as crit,
             bool_or(a.alert_type <> 'sos' and a.severity <> 'critical')               as other,
             min(a.created_at) filter (where a.alert_type = 'sos')                     as sos_since
      from public.alerts a
      where a.patient_id = pp.patient_id and a.status = 'open'
    ) al on true
    where pp.assigned_provider_id = v_uid
  ) s
  order by
    case when s.sos_open then 0
         when s.status = 'urgent' then 1
         when s.status = 'attention' then 2
         when s.status = 'no_recent_data' then 3
         else 4 end,
    s.missed_check desc,
    s.open_alert_count desc,
    s.last_check_at asc nulls first,
    s.patient_id;
end
$$;

revoke all on function public.provider_overview() from public, anon, authenticated;
grant execute on function public.provider_overview() to authenticated;


-- ---------------------------------------------------------------------
-- Check (read-only, one result). Expect exactly 3 rows:
--   function  status_fresh_hours: security_definer = true,  anon = false, signed-in = true
--   function  provider_overview:  security_definer = false, anon = false, signed-in = true
--   count     signed-in users can run 16 functions in public (not counting Supabase's own rls_auto_enable)
-- ---------------------------------------------------------------------
select 'function' as what,
       p.proname::text || ': security_definer = ' || p.prosecdef::text
       || ', anon can run = ' || has_function_privilege('anon', p.oid, 'execute')::text
       || ', signed-in can run = ' || has_function_privilege('authenticated', p.oid, 'execute')::text as detail
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('status_fresh_hours', 'provider_overview')
union all
select 'count',
       'signed-in users can run ' || count(*)::text || ' functions in public (expected 16)'
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname <> 'rls_auto_enable'
  and has_function_privilege('authenticated', p.oid, 'execute')
order by 1, 2;
