-- =====================================================================
-- 009_patient_home.sql
-- NurtureLink step 3.1: the database side of the patient Home tab.
--
-- WHAT IT DOES
--   1. app_settings gets one new row, status_fresh_hours (default 14): how
--      many hours a belt check counts as "recent". It is a DEFAULT pending the
--      medical officer, kept in a table so it is not hard-coded in the app.
--   2. public.my_home_status() - ONE function the signed-in patient calls to
--      get their green / amber / red / "no recent data" status. It reads the
--      alert limits from alert_thresholds (nothing hard-coded), the patient's
--      OPEN alerts, the latest belt check (including signal loss) and the
--      latest vitals, and returns a small JSON object. It takes no argument:
--      it only ever answers for auth.uid().
--   3. public.guard_sos_rate() + a BEFORE INSERT trigger on alerts: a patient
--      cannot raise a second SOS for themselves within 5 minutes of the last
--      one (error text: sos_rate_limited). Provider-made alerts, the SQL
--      Editor and the demo seed are not limited.
--
-- WHY A FUNCTION AND NOT A VIEW
--   Patients are not allowed to read alert_thresholds (005: providers only)
--   or app_settings (no client grant). A security_invoker view would run with
--   the patient's rights, see zero threshold rows, and could not tell a heart
--   rate in range from one out of range. So the limits must be read by a
--   SECURITY DEFINER function that returns only the verdict, never the limits.
--
-- STATUS RULES (all of them, in order)
--   urgent          an open SOS, or an open alert with severity 'critical'
--   attention       an open alert with a lower severity, OR the latest belt
--                   check lost the signal, OR the latest heart rate is outside
--                   the limits, OR the latest SpO2 is below its minimum, OR the
--                   latest temperature is above its maximum (limits from
--                   alert_thresholds, only if that threshold is enabled)
--   no_recent_data  none of the above, and there is no belt check inside the
--                   freshness window (or no belt check at all)
--   ok              a belt check inside the window, usable, inside the limits,
--                   and nothing open
--   An open alert is never hidden by old data: stale data plus an open critical
--   alert is still 'urgent'. 'ok' is only returned when there IS recent data.
--   Acknowledged and resolved alerts do not count (a provider has seen them);
--   the readings themselves still decide.
--   The result also lists the reasons (codes the app words with i18n).
--   This is monitoring and screening, not diagnosis. Limits, severities, the
--   "in a row" counts and the freshness window are all unconfirmed defaults.
--
-- DEPENDS ON: 000 to 008.
--
-- SAFE TO RE-RUN: yes ("create or replace", "drop trigger if exists",
--   "on conflict do nothing").
--
-- CHANGE THE FRESHNESS WINDOW (SQL Editor, as the admin):
--   update public.app_settings set value = '12' where key = 'status_fresh_hours';
--   (a whole number of hours from 1 to 168; anything else falls back to 14)
--
-- HOW TO UNDO:
--   drop trigger if exists alerts_guard_sos_rate on public.alerts;
--   drop function if exists public.guard_sos_rate();
--   drop function if exists public.my_home_status();
--   delete from public.app_settings where key = 'status_fresh_hours';
--   Then in supabase/tests/access_tests.sql change the expected list of client
--   functions back to the original five (remove my_home_status).
--
-- SECURITY NOTES
--   * my_home_status is SECURITY DEFINER because the patient cannot read
--     alert_thresholds or app_settings. search_path is fixed, every name is
--     schema-qualified, it takes no arguments, and it reads only rows where
--     patient_id = auth.uid(). It returns the verdict and timestamps, never the
--     limits. EXECUTE is revoked from PUBLIC and anon, granted to authenticated
--     only. anon gets nothing.
--   * guard_sos_rate is SECURITY INVOKER (it reads the caller's own alerts,
--     which RLS already allows). EXECUTE is revoked from everyone; a trigger
--     does not need the caller to hold it.
--   * Nothing here changes any table grant or RLS policy.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. The freshness setting (a default, pending the medical officer)
-- ---------------------------------------------------------------------
insert into public.app_settings (key, value, description)
values ('status_fresh_hours', '14',
        'DEFAULT, pending medical officer: hours a belt check counts as recent for the patient Home status. Whole number, 1 to 168.')
on conflict (key) do nothing;


-- ---------------------------------------------------------------------
-- 2. The status function
-- ---------------------------------------------------------------------
create or replace function public.my_home_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_hours      integer;
  v_cut        timestamptz;
  v_belt_at    timestamptz;
  v_belt_lost  boolean;
  v_belt_fhr   smallint;
  v_vit_at     timestamptz;
  v_spo2       smallint;
  v_temp       numeric;
  v_fresh_belt boolean;
  v_fresh_vit  boolean;
  v_sos        boolean;
  v_crit       boolean;
  v_other      boolean;
  v_reasons    text[] := '{}';
  v_status     text;
  th           public.alert_thresholds%rowtype;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  -- How recent is "recent": the setting, or 14 hours if it is missing or not a sensible number.
  select case when s.value ~ '^[0-9]{1,3}$' then s.value::integer end
    into v_hours
  from public.app_settings s
  where s.key = 'status_fresh_hours';
  if v_hours is null or v_hours < 1 or v_hours > 168 then
    v_hours := 14;
  end if;
  v_cut := now() - make_interval(hours => v_hours);

  -- Latest belt check (a signal loss counts as a check; it has no usable value).
  select b.measured_at, b.signal_lost, b.fetal_hr_bpm
    into v_belt_at, v_belt_lost, v_belt_fhr
  from public.belt_readings b
  where b.patient_id = v_uid
  order by b.measured_at desc, b.created_at desc
  limit 1;
  v_fresh_belt := v_belt_at is not null and v_belt_at >= v_cut;

  -- Latest vitals time, and the latest SpO2 and temperature inside the window
  -- (a vitals row may hold only some of the three values).
  select max(m.measured_at) into v_vit_at
  from public.maternal_vitals m
  where m.patient_id = v_uid;
  v_fresh_vit := v_vit_at is not null and v_vit_at >= v_cut;

  select m.spo2_percent into v_spo2
  from public.maternal_vitals m
  where m.patient_id = v_uid and m.spo2_percent is not null and m.measured_at >= v_cut
  order by m.measured_at desc, m.created_at desc
  limit 1;

  select m.temperature_c into v_temp
  from public.maternal_vitals m
  where m.patient_id = v_uid and m.temperature_c is not null and m.measured_at >= v_cut
  order by m.measured_at desc, m.created_at desc
  limit 1;

  -- Open alerts of this patient.
  select coalesce(bool_or(a.alert_type = 'sos'), false),
         coalesce(bool_or(a.alert_type <> 'sos' and a.severity = 'critical'), false),
         coalesce(bool_or(a.alert_type <> 'sos' and a.severity <> 'critical'), false)
    into v_sos, v_crit, v_other
  from public.alerts a
  where a.patient_id = v_uid and a.status = 'open';

  if v_sos   then v_reasons := array_append(v_reasons, 'sos_open');       end if;
  if v_crit  then v_reasons := array_append(v_reasons, 'alert_critical'); end if;
  if v_other then v_reasons := array_append(v_reasons, 'alert_open');     end if;

  -- The latest belt check, against the limits in alert_thresholds.
  if v_fresh_belt then
    if v_belt_lost then
      v_reasons := array_append(v_reasons, 'signal_lost');
    elsif v_belt_fhr is not null then
      select * into th from public.alert_thresholds
      where alert_type = 'fhr_out_of_range' and enabled;
      if found
         and ((th.min_value is not null and v_belt_fhr < th.min_value)
           or (th.max_value is not null and v_belt_fhr > th.max_value)) then
        v_reasons := array_append(v_reasons, 'fhr_out_of_range');
      end if;
    end if;
  else
    v_reasons := array_append(v_reasons, 'no_recent_belt');
  end if;

  -- The latest vitals, against their limits.
  if v_spo2 is not null then
    select * into th from public.alert_thresholds
    where alert_type = 'low_spo2' and enabled;
    if found and th.min_value is not null and v_spo2 < th.min_value then
      v_reasons := array_append(v_reasons, 'low_spo2');
    end if;
  end if;

  if v_temp is not null then
    select * into th from public.alert_thresholds
    where alert_type = 'fever' and enabled;
    if found and th.max_value is not null and v_temp > th.max_value then
      v_reasons := array_append(v_reasons, 'fever');
    end if;
  end if;

  -- The verdict. 'ok' needs recent data; open alerts always beat old data.
  if v_sos or v_crit then
    v_status := 'urgent';
  elsif v_other or v_reasons && array['signal_lost', 'fhr_out_of_range', 'low_spo2', 'fever'] then
    v_status := 'attention';
  elsif not v_fresh_belt then
    v_status := 'no_recent_data';
  else
    v_status := 'ok';
  end if;

  return jsonb_build_object(
    'status',           v_status,
    'reasons',          to_jsonb(v_reasons),
    'fresh_hours',      v_hours,
    'fresh_belt',       v_fresh_belt,
    'fresh_vitals',     v_fresh_vit,
    'latest_belt_at',   v_belt_at,
    'latest_vitals_at', v_vit_at
  );
end
$$;

revoke all on function public.my_home_status() from public, anon, authenticated;
grant execute on function public.my_home_status() to authenticated;


-- ---------------------------------------------------------------------
-- 3. SOS rate limit
-- A patient raising an SOS for themselves is allowed once per 5 minutes.
-- The advisory lock is per patient and lasts to the end of the transaction, so
-- ten presses sent at the same instant are handled one after another and only
-- the first is stored (the others see it and are refused). The app shows the
-- refusal as "your SOS was already sent", not as a failure.
-- Not limited: alerts made by the SQL Editor / seed (current_user is not an
-- API role), alerts a provider adds for an assigned patient (auth.uid() is the
-- provider, not the patient), and every alert type other than 'sos'.
-- The 5-minute window is a plain default; to change it, edit the interval below
-- and run this file again.
-- ---------------------------------------------------------------------
create or replace function public.guard_sos_rate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.alert_type = 'sos'
     and current_user in ('anon', 'authenticated')
     and new.patient_id = (select auth.uid()) then

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('nl_sos:' || new.patient_id::text, 0));

    if exists (
      select 1 from public.alerts a
      where a.patient_id = new.patient_id
        and a.alert_type = 'sos'
        and a.created_at > now() - interval '5 minutes'
    ) then
      raise exception 'sos_rate_limited';
    end if;
  end if;
  return new;
end
$$;
revoke all on function public.guard_sos_rate() from public, anon, authenticated;

drop trigger if exists alerts_guard_sos_rate on public.alerts;
create trigger alerts_guard_sos_rate
  before insert on public.alerts
  for each row execute function public.guard_sos_rate();


-- ---------------------------------------------------------------------
-- Check (read-only, one result). Expect exactly 4 rows:
--   setting    status_fresh_hours = 14   (or the value you set)
--   function   my_home_status: security_definer = true, anon = false, signed_in = true
--   function   guard_sos_rate: security_definer = false, anon = false, signed_in = false
--   trigger    alerts_guard_sos_rate: enabled = O
-- ---------------------------------------------------------------------
select 'setting' as what, 'status_fresh_hours = ' || s.value as detail
from public.app_settings s where s.key = 'status_fresh_hours'
union all
select 'function', p.proname::text || ': security_definer = ' || p.prosecdef::text
       || ', anon can run = ' || has_function_privilege('anon', p.oid, 'execute')::text
       || ', signed-in can run = ' || has_function_privilege('authenticated', p.oid, 'execute')::text
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('my_home_status', 'guard_sos_rate')
union all
select 'trigger', t.tgname::text || ': enabled = ' || t.tgenabled::text
from pg_trigger t
where t.tgrelid = 'public.alerts'::regclass and t.tgname = 'alerts_guard_sos_rate' and not t.tgisinternal
order by 1, 2;
