-- =====================================================================
-- 010_monitor.sql
-- NurtureLink step 3.2: the database side of the patient Monitor tab.
--
-- WHAT IT DOES
--   1. public.my_normal_ranges() - a small read-only function the signed-in
--      patient calls to draw the shaded "normal range" band on the charts. It
--      returns ONLY the lowest and highest normal value (and whether the
--      medical officer has confirmed them) for the enabled limits of
--      fetal heart rate, SpO2 and temperature, read from alert_thresholds.
--      Example result:
--        {"fhr":  {"min":110,"max":160,"confirmed":false},
--         "spo2": {"min":95,"confirmed":false},
--         "temp": {"max":37.9,"confirmed":false}}
--      A limit that is disabled or missing is simply left out (the chart then
--      draws no band). Severities and "in a row" counts are NOT returned.
--
--   2. public.guard_manual_reading() + a BEFORE INSERT trigger on
--      belt_readings and on maternal_vitals. It checks only rows with
--      source = 'manual' that arrive from the app (roles anon / authenticated)
--      and refuses a row that is not a plain hand-typed entry:
--        * device_id must be empty (a typed entry is not tied to a device),
--        * belt rows: signal_lost must be false and signal_quality and
--          confidence must be empty (a person cannot claim a signal quality),
--          and the heart rate must be present,
--        * values must be inside plausible ENTRY limits (below),
--        * measured_at may not be older than 10 minutes: a typed entry is
--          stored with the server time, it cannot be back-dated. (A time in
--          the future is refused by the 008 guard, code reading_time_in_future.)
--      The error text is  manual_reading_invalid  (the app words it with i18n).
--
-- ENTRY LIMITS (data-entry sanity checks, NOT clinical limits; the alert
-- limits stay in alert_thresholds). Pending medical officer review:
--      baby heart rate        60 to 220 bpm
--      mother's heart rate    30 to 220 bpm
--      SpO2                   70 to 100 %
--      temperature            34.0 to 42.0 degrees C
--   The same numbers are in src/lib/patientData.js (MANUAL_LIMITS) so the
--   form can warn before saving; this trigger is the real check.
--
-- WHY NO "MANUAL DEVICE" ROW
--   device_id is nullable and the insert policy (005) only requires a device
--   to be the patient's own WHEN one is given. A typed entry has no device, so
--   it needs no device row, no change to the devices table and no new grants.
--   004 already grants INSERT on source and client_id.
--
-- WHAT IS NOT CHANGED
--   Grants on belt_readings, maternal_vitals, RLS policies (005), the alert
--   trigger (002; it ignores source, so a manual value counts like any other
--   and the "N in a row" rule still applies), the time guard (008). Readings
--   stay append-only. The SQL Editor, the demo seed and service_role are not
--   affected by the guard (it only looks at anon and authenticated).
--
-- DEPENDS ON: 000 to 009.
--
-- SAFE TO RE-RUN: yes ("create or replace", "drop trigger if exists").
--
-- HOW TO UNDO:
--   drop trigger if exists belt_readings_guard_manual   on public.belt_readings;
--   drop trigger if exists maternal_vitals_guard_manual on public.maternal_vitals;
--   drop function if exists public.guard_manual_reading();
--   drop function if exists public.my_normal_ranges();
--   Then in supabase/tests/access_tests.sql change the expected list of client
--   functions back (remove my_normal_ranges; 3 lines: header, label, list).
--
-- SECURITY NOTES
--   * my_normal_ranges is SECURITY DEFINER because patients cannot read
--     alert_thresholds (005: providers only). It takes no argument, needs a
--     signed-in user, fixes search_path, and returns only the numbers above.
--     EXECUTE is revoked from PUBLIC and anon and granted to authenticated only.
--   * guard_manual_reading is NOT SECURITY DEFINER (it only looks at the row
--     being saved, so current_user is the caller). EXECUTE is revoked from
--     everyone; a trigger does not need the caller to hold it.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. The normal ranges for the chart band
-- ---------------------------------------------------------------------
create or replace function public.my_normal_ranges()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_out jsonb := '{}'::jsonb;
  th    public.alert_thresholds%rowtype;
  v_key text;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;

  for th in
    select * from public.alert_thresholds
    where alert_type in ('fhr_out_of_range', 'low_spo2', 'fever') and enabled
  loop
    v_key := case th.alert_type
               when 'fhr_out_of_range' then 'fhr'
               when 'low_spo2'         then 'spo2'
               else 'temp'
             end;
    -- jsonb_strip_nulls drops an empty min or max (a one-sided limit)
    v_out := v_out || jsonb_build_object(
      v_key,
      jsonb_strip_nulls(jsonb_build_object(
        'min', th.min_value, 'max', th.max_value, 'confirmed', th.is_confirmed))
    );
  end loop;

  return v_out;
end
$$;

revoke all on function public.my_normal_ranges() from public, anon, authenticated;
grant execute on function public.my_normal_ranges() to authenticated;


-- ---------------------------------------------------------------------
-- 2. Guard for hand-typed (manual) readings
-- ---------------------------------------------------------------------
create or replace function public.guard_manual_reading()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Only typed entries that come through the app API are checked.
  if new.source is distinct from 'manual' or current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  if new.device_id is not null then
    raise exception 'manual_reading_invalid';
  end if;
  if new.measured_at < now() - interval '10 minutes' then
    raise exception 'manual_reading_invalid';
  end if;

  if tg_table_name = 'belt_readings' then
    if new.signal_lost
       or new.signal_quality is not null
       or new.confidence is not null
       or new.fetal_hr_bpm is null
       or new.fetal_hr_bpm not between 60 and 220 then
      raise exception 'manual_reading_invalid';
    end if;
  else  -- maternal_vitals
    if (new.heart_rate_bpm is not null and new.heart_rate_bpm not between 30 and 220)
       or (new.spo2_percent is not null and new.spo2_percent not between 70 and 100)
       or (new.temperature_c is not null and new.temperature_c not between 34.0 and 42.0) then
      raise exception 'manual_reading_invalid';
    end if;
  end if;

  return new;
end
$$;

revoke all on function public.guard_manual_reading() from public, anon, authenticated;

-- Trigger names sort before the 008 time guards, so a typed entry is checked
-- first; a future time then still reaches the 008 guard (reading_time_in_future).
drop trigger if exists belt_readings_guard_manual on public.belt_readings;
create trigger belt_readings_guard_manual
  before insert on public.belt_readings
  for each row execute function public.guard_manual_reading();

drop trigger if exists maternal_vitals_guard_manual on public.maternal_vitals;
create trigger maternal_vitals_guard_manual
  before insert on public.maternal_vitals
  for each row execute function public.guard_manual_reading();


-- ---------------------------------------------------------------------
-- Checks (read-only). Expect 2 trigger rows (tgenabled = O) and 2 function
-- rows: my_normal_ranges (security_definer = true, signed-in can run = true)
-- and guard_manual_reading (security_definer = false, nobody can run it).
-- ---------------------------------------------------------------------
select c.relname as table_name, t.tgname, t.tgenabled
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
where t.tgname in ('belt_readings_guard_manual', 'maternal_vitals_guard_manual')
  and not t.tgisinternal
order by c.relname;

select p.proname as function_name,
       p.prosecdef as security_definer,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_run,
       has_function_privilege('authenticated', p.oid, 'execute') as signed_in_can_run
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('my_normal_ranges', 'guard_manual_reading')
order by p.proname;
