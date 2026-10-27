-- =====================================================================
-- 009_patient_home_tests.sql
-- NurtureLink step 3.1: proves that migration 009 does what it should.
--   * my_home_status() gives the right green / amber / red / "no recent data"
--     verdict, uses the limits in alert_thresholds (nothing hard-coded), never
--     says "ok" without recent data, and only ever answers for the caller.
--   * anon cannot run it; nobody can call the SOS guard directly.
--   * a patient's SOS is limited (one per 5 minutes, ten rapid presses store
--     one), and providers, the SQL Editor and other patients are not affected.
--   * a reading dated in the future is refused (migration 008) with the code
--     the app turns into a friendly message.
--
-- HOW IT WORKS: like access_tests.sql. Clearly fake users (emails end in
-- ".invalid") and fake data are created inside ONE block that is deliberately
-- aborted at its end, so everything is rolled back (the report survives). For
-- each test the session switches to the role "authenticated" or "anon" with a
-- fake user's id in request.jwt.claims, exactly like a real API request.
-- The alert limits and the freshness setting are set to known values INSIDE the
-- block so the result does not depend on what you edited live; that too is
-- rolled back. Real data is never changed.
--
-- AFTER the block, read-only INFO lines show the status the 10 demo patients
-- get RIGHT NOW (if the demo accounts exist). Those use your real limits and
-- real data, and are for reading, not pass/fail.
--
-- HOW TO RUN: run 009_patient_home.sql first. Paste this WHOLE file into a new
-- SQL Editor tab and click Run (if asked about "destructive operations",
-- click Run: the file only creates temporary functions; the fake data is rolled
-- back). Result: one table, SUMMARY first, then FAIL, INFO, PASS.
-- Expected: "N PASS, 0 FAIL".
-- WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and every FAIL row.
--
-- DEPENDS ON: 000 to 009. READ-ONLY for your real data.
-- SAFE TO RE-RUN: yes, any number of times. HOW TO UNDO: nothing to undo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers (temporary: they disappear when the session ends)
-- ---------------------------------------------------------------------
create or replace function pg_temp.x(p_sql text, p_uid uuid default null, p_role text default 'authenticated')
returns text
language plpgsql
as $fn$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql;
    reset role;
    return 'ok';
  exception when others then
    reset role;
    return 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
end
$fn$;

create or replace function pg_temp.ck(p_name text, p_ok boolean, p_detail text default '')
returns text
language sql
as $fn$
  select case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end || '|' || p_name || '|' ||
         case when coalesce(p_ok, false) then '' else coalesce(p_detail, '') end
$fn$;

-- Call my_home_status() as a signed-in user (null = signed in with no user id).
-- Returns the JSON, or {"error": "<sqlstate> <message>"} if the call failed.
create or replace function pg_temp.st(p_uid uuid)
returns jsonb
language plpgsql
as $fn$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  set local role authenticated;
  begin
    v := public.my_home_status();
  exception when others then
    reset role;
    return jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  reset role;
  return v;
end
$fn$;

-- Does the status result list this reason code?
create or replace function pg_temp.has(p_status jsonb, p_code text)
returns boolean
language sql
as $fn$
  select coalesce((p_status -> 'reasons') @> to_jsonb(p_code), false)
$fn$;

-- Number of SOS rows a patient has (read as the owner, so RLS does not hide any).
create or replace function pg_temp.sos_count(p_uid uuid)
returns integer
language sql
as $fn$
  select count(*)::int from public.alerts where patient_id = p_uid and alert_type = 'sos'
$fn$;

-- ---------------------------------------------------------------------
-- The tests
-- ---------------------------------------------------------------------
create or replace function pg_temp.nl_home_tests()
returns text[]
language plpgsql
as $fn$
declare
  r   text[] := '{}';
  -- patients, named after what they have
  u_ok        uuid := gen_random_uuid();   -- fresh normal data, nothing open
  u_none      uuid := gen_random_uuid();   -- no readings at all
  u_stale     uuid := gen_random_uuid();   -- normal data, 30 hours old
  u_lost      uuid := gen_random_uuid();   -- latest belt check lost the signal
  u_fhr       uuid := gen_random_uuid();   -- latest heart rate below the minimum, only once
  u_spo2      uuid := gen_random_uuid();   -- latest SpO2 below the minimum, only once
  u_fever     uuid := gen_random_uuid();   -- latest temperature above the maximum, only once
  u_crit      uuid := gen_random_uuid();   -- open critical alert
  u_warn      uuid := gen_random_uuid();   -- open warning alert
  u_sos       uuid := gen_random_uuid();   -- open SOS
  u_ack       uuid := gen_random_uuid();   -- only an acknowledged alert
  u_stalecrit uuid := gen_random_uuid();   -- old data AND an open critical alert
  u_limit     uuid := gen_random_uuid();   -- SOS rate-limit tests, assigned to p1
  u_limit2    uuid := gen_random_uuid();   -- another patient, must not be affected
  u_fast      uuid := gen_random_uuid();   -- ten rapid presses
  p1          uuid := gen_random_uuid();   -- a provider assigned to u_ok and u_limit
  v    jsonb;
  s    text;
  n    integer;
  i    integer;
  okb  boolean;
  uid  uuid;
  fn_exists boolean;
  pass_n integer;
  fail_n text;
begin
  fn_exists := to_regprocedure('public.my_home_status()') is not null;
  r := r || pg_temp.ck('migration 009 has been run (my_home_status() exists)', fn_exists,
    'run supabase/migrations/009_patient_home.sql first');
  if not fn_exists then
    return array['SUMMARY|0 PASS, 1 FAIL|run supabase/migrations/009_patient_home.sql first'] || r;
  end if;

  r := r || pg_temp.ck('the setting status_fresh_hours exists and is a whole number',
    exists (select 1 from public.app_settings where key = 'status_fresh_hours' and value ~ '^[0-9]{1,3}$'),
    'run 009 again; the row is missing or not a number');

  begin   -- everything in this block is rolled back at the end

    ---------------------------------------------------------------
    -- Fake users and data
    ---------------------------------------------------------------
    insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
    select u, 'nl-home-' || u || '@nurturelink-test.invalid', now(), '{}'::jsonb
    from unnest(array[u_ok, u_none, u_stale, u_lost, u_fhr, u_spo2, u_fever, u_crit, u_warn, u_sos,
                      u_ack, u_stalecrit, u_limit, u_limit2, u_fast, p1]) u;
    update public.profiles set role = 'provider' where id = p1;
    insert into public.pregnancy_profiles (patient_id, assigned_provider_id, due_date) values
      (u_ok, p1, current_date + 100), (u_limit, p1, current_date + 100);

    -- Known limits and a known freshness window for this block only.
    update public.alert_thresholds set min_value = 110, max_value = 160, sustained_count = 3, severity = 'critical', enabled = true
      where alert_type = 'fhr_out_of_range';
    update public.alert_thresholds set min_value = null, max_value = null, sustained_count = 3, severity = 'warning', enabled = true
      where alert_type = 'signal_loss';
    update public.alert_thresholds set min_value = 95, max_value = null, sustained_count = 2, severity = 'warning', enabled = true
      where alert_type = 'low_spo2';
    update public.alert_thresholds set min_value = null, max_value = 37.9, sustained_count = 2, severity = 'warning', enabled = true
      where alert_type = 'fever';
    update public.app_settings set value = '14' where key = 'status_fresh_hours';

    -- Recent normal data (3 and 2 hours ago)
    insert into public.belt_readings (patient_id, fetal_hr_bpm, signal_quality, confidence, source, measured_at)
    select u, 140, 85, 90, 'simulator', now() - h * interval '1 hour'
    from unnest(array[u_ok, u_lost, u_fhr, u_spo2, u_fever, u_crit, u_warn, u_sos, u_ack]) u,
         unnest(array[3, 2]) h;
    insert into public.maternal_vitals (patient_id, heart_rate_bpm, spo2_percent, temperature_c, source, measured_at)
    select u, 80, 98, 36.8, 'simulator', now() - h * interval '1 hour'
    from unnest(array[u_ok, u_lost, u_fhr, u_spo2, u_fever, u_crit, u_warn, u_sos, u_ack]) u,
         unnest(array[3, 2]) h;

    -- Old normal data (30 and 29 hours ago)
    insert into public.belt_readings (patient_id, fetal_hr_bpm, signal_quality, confidence, source, measured_at)
    select u, 140, 85, 90, 'simulator', now() - h * interval '1 hour'
    from unnest(array[u_stale, u_stalecrit]) u, unnest(array[30, 29]) h;
    insert into public.maternal_vitals (patient_id, heart_rate_bpm, spo2_percent, temperature_c, source, measured_at)
    select u, 80, 98, 36.8, 'simulator', now() - h * interval '1 hour'
    from unnest(array[u_stale, u_stalecrit]) u, unnest(array[30, 29]) h;

    -- One bad latest reading each, too few in a row to raise an alert by themselves
    insert into public.belt_readings (patient_id, signal_quality, signal_lost, source, measured_at)
      values (u_lost, 8, true, 'simulator', now() - interval '1 hour');
    insert into public.belt_readings (patient_id, fetal_hr_bpm, signal_quality, confidence, source, measured_at)
      values (u_fhr, 100, 85, 90, 'simulator', now() - interval '1 hour');
    insert into public.maternal_vitals (patient_id, spo2_percent, source, measured_at)
      values (u_spo2, 93, 'simulator', now() - interval '1 hour');
    insert into public.maternal_vitals (patient_id, temperature_c, source, measured_at)
      values (u_fever, 38.2, 'simulator', now() - interval '1 hour');

    -- Alerts written by the owner (like the alert trigger or a provider would)
    insert into public.alerts (patient_id, alert_type, severity, status) values
      (u_crit,       'fhr_out_of_range', 'critical', 'open'),
      (u_warn,       'signal_loss',      'warning',  'open'),
      (u_sos,        'sos',              'critical', 'open'),
      (u_stalecrit,  'fhr_out_of_range', 'critical', 'open');
    insert into public.alerts (patient_id, alert_type, severity, status, acknowledged_by, acknowledged_at) values
      (u_ack, 'low_spo2', 'warning', 'acknowledged', p1, now());

    ---------------------------------------------------------------
    -- 1. Who may run what
    ---------------------------------------------------------------
    r := r || pg_temp.ck('my_home_status is SECURITY DEFINER, has a fixed search_path and takes no argument',
      exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'my_home_status' and p.prosecdef and p.pronargs = 0
                and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%')));
    r := r || pg_temp.ck('anon cannot run my_home_status (permission denied)',
      pg_temp.x('select public.my_home_status()', null, 'anon') like 'ERR 42501 permission denied for function%');
    r := r || pg_temp.ck('signed-in users can run my_home_status',
      has_function_privilege('authenticated', 'public.my_home_status()', 'EXECUTE')
      and pg_temp.x('select public.my_home_status()', u_ok) = 'ok');
    r := r || pg_temp.ck('nobody can call the SOS guard function directly',
      pg_temp.x('select public.guard_sos_rate()', null, 'anon') like 'ERR 42501%'
      and pg_temp.x('select public.guard_sos_rate()', u_ok) like 'ERR 42501%');
    r := r || pg_temp.ck('signed in with no user id is refused (not_signed_in)',
      coalesce(pg_temp.st(null) ->> 'error', '') like '% not_signed_in', pg_temp.st(null)::text);

    ---------------------------------------------------------------
    -- 2. The verdict
    ---------------------------------------------------------------
    v := pg_temp.st(u_ok);
    r := r || pg_temp.ck('recent normal data and nothing open is ok, with no reasons',
      v ->> 'status' = 'ok' and (v -> 'reasons') = '[]'::jsonb and (v ->> 'fresh_belt')::boolean, v::text);

    v := pg_temp.st(u_none);
    r := r || pg_temp.ck('a patient with no readings gets no_recent_data, never ok',
      v ->> 'status' = 'no_recent_data' and v ->> 'latest_belt_at' is null and v ->> 'latest_vitals_at' is null
      and pg_temp.has(v, 'no_recent_belt'), v::text);

    v := pg_temp.st(u_stale);
    r := r || pg_temp.ck('normal data older than the window gets no_recent_data, never ok',
      v ->> 'status' = 'no_recent_data' and not (v ->> 'fresh_belt')::boolean and v ->> 'latest_belt_at' is not null, v::text);

    v := pg_temp.st(u_lost);
    r := r || pg_temp.ck('a signal loss on the latest check is attention (signal_lost)',
      v ->> 'status' = 'attention' and pg_temp.has(v, 'signal_lost'), v::text);

    v := pg_temp.st(u_fhr);
    r := r || pg_temp.ck('one heart rate outside the limits is attention even before an alert exists',
      v ->> 'status' = 'attention' and pg_temp.has(v, 'fhr_out_of_range')
      and (select count(*) from public.alerts where patient_id = u_fhr) = 0, v::text);

    v := pg_temp.st(u_spo2);
    r := r || pg_temp.ck('one low SpO2 is attention (low_spo2)',
      v ->> 'status' = 'attention' and pg_temp.has(v, 'low_spo2'), v::text);

    v := pg_temp.st(u_fever);
    r := r || pg_temp.ck('one high temperature is attention (fever)',
      v ->> 'status' = 'attention' and pg_temp.has(v, 'fever'), v::text);

    v := pg_temp.st(u_crit);
    r := r || pg_temp.ck('an open critical alert is urgent',
      v ->> 'status' = 'urgent' and pg_temp.has(v, 'alert_critical'), v::text);

    v := pg_temp.st(u_warn);
    r := r || pg_temp.ck('an open warning alert is attention (alert_open)',
      v ->> 'status' = 'attention' and pg_temp.has(v, 'alert_open'), v::text);

    v := pg_temp.st(u_sos);
    r := r || pg_temp.ck('an open SOS is urgent (sos_open)',
      v ->> 'status' = 'urgent' and pg_temp.has(v, 'sos_open'), v::text);

    v := pg_temp.st(u_ack);
    r := r || pg_temp.ck('an acknowledged alert does not count; recent normal readings give ok',
      v ->> 'status' = 'ok', v::text);

    v := pg_temp.st(u_stalecrit);
    r := r || pg_temp.ck('old data does not hide an open critical alert (urgent, plus no_recent_belt)',
      v ->> 'status' = 'urgent' and pg_temp.has(v, 'alert_critical') and pg_temp.has(v, 'no_recent_belt'), v::text);

    ---------------------------------------------------------------
    -- 3. The limits and the window come from the tables
    ---------------------------------------------------------------
    update public.alert_thresholds set min_value = 90, max_value = 120 where alert_type = 'fhr_out_of_range';
    v := pg_temp.st(u_ok);
    r := r || pg_temp.ck('changing the heart-rate limits changes the verdict (140 is now too high)',
      v ->> 'status' = 'attention' and pg_temp.has(v, 'fhr_out_of_range'), v::text);
    update public.alert_thresholds set min_value = 110, max_value = 160 where alert_type = 'fhr_out_of_range';

    update public.alert_thresholds set enabled = false where alert_type = 'fhr_out_of_range';
    v := pg_temp.st(u_fhr);
    r := r || pg_temp.ck('a disabled heart-rate limit is not applied (100 bpm is then ok)',
      v ->> 'status' = 'ok' and not pg_temp.has(v, 'fhr_out_of_range'), v::text);
    update public.alert_thresholds set enabled = true where alert_type = 'fhr_out_of_range';

    update public.app_settings set value = '1' where key = 'status_fresh_hours';
    v := pg_temp.st(u_ok);
    r := r || pg_temp.ck('a shorter freshness window turns 2-hour-old data into no_recent_data',
      v ->> 'status' = 'no_recent_data' and (v ->> 'fresh_hours')::int = 1, v::text);
    update public.app_settings set value = 'abc' where key = 'status_fresh_hours';
    v := pg_temp.st(u_ok);
    r := r || pg_temp.ck('a freshness setting that is not a number falls back to 14 hours',
      (v ->> 'fresh_hours')::int = 14 and v ->> 'status' = 'ok', v::text);
    update public.app_settings set value = '14' where key = 'status_fresh_hours';

    ---------------------------------------------------------------
    -- 4. Only the caller's own data
    ---------------------------------------------------------------
    v := pg_temp.st(p1);
    r := r || pg_temp.ck('an assigned provider calling it gets only their own (empty) answer, not a patient''s',
      v ->> 'status' = 'no_recent_data' and v ->> 'latest_belt_at' is null and v ->> 'latest_vitals_at' is null, v::text);
    r := r || pg_temp.ck('one patient''s alerts do not change another patient''s status',
      pg_temp.st(u_ok) ->> 'status' = 'ok' and pg_temp.st(u_crit) ->> 'status' = 'urgent'
      and pg_temp.st(u_none) ->> 'status' = 'no_recent_data');

    ---------------------------------------------------------------
    -- 5. SOS limit
    ---------------------------------------------------------------
    r := r || pg_temp.ck('a patient can raise an SOS for themselves',
      pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'critical')$q$, u_limit), u_limit) = 'ok');
    s := pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'critical')$q$, u_limit), u_limit);
    r := r || pg_temp.ck('a second SOS right away is refused with sos_rate_limited', s = 'ERR P0001 sos_rate_limited', s);
    r := r || pg_temp.ck('only one SOS row was stored', pg_temp.sos_count(u_limit) = 1, pg_temp.sos_count(u_limit)::text);

    for i in 1..10 loop
      s := pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'critical')$q$, u_fast), u_fast);
    end loop;
    r := r || pg_temp.ck('ten rapid SOS presses store exactly one', pg_temp.sos_count(u_fast) = 1, pg_temp.sos_count(u_fast)::text);

    r := r || pg_temp.ck('another patient is not blocked by someone else''s SOS',
      pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'critical')$q$, u_limit2), u_limit2) = 'ok');

    r := r || pg_temp.ck('a provider can still add SOS alerts for an assigned patient (not limited)',
      pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'warning')$q$, u_limit), p1) = 'ok'
      and pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'warning')$q$, u_limit), p1) = 'ok');

    update public.alerts set created_at = now() - interval '6 minutes' where patient_id = u_limit and alert_type = 'sos';
    r := r || pg_temp.ck('after 5 minutes the patient can raise a new SOS',
      pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'critical')$q$, u_limit), u_limit) = 'ok');
    s := pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'critical')$q$, u_limit), u_limit);
    r := r || pg_temp.ck('and the limit starts again from that SOS', s = 'ERR P0001 sos_rate_limited', s);

    okb := true;
    begin
      insert into public.alerts (patient_id, alert_type, severity) values (u_fast, 'sos', 'critical'), (u_fast, 'sos', 'critical');
    exception when others then
      okb := false;
    end;
    r := r || pg_temp.ck('the SQL Editor and the seed are not limited (owner inserts several SOS rows in a row)', okb);

    ---------------------------------------------------------------
    -- 6. A reading dated in the future is refused (008), a slightly fast clock is not
    ---------------------------------------------------------------
    s := pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at) values (%L, 140, 'simulator', now() + interval '1 hour')$q$, u_ok), u_ok);
    r := r || pg_temp.ck('a belt reading dated 1 hour ahead is refused with reading_time_in_future', s = 'ERR P0001 reading_time_in_future', s);
    s := pg_temp.x(format($q$insert into public.maternal_vitals (patient_id, heart_rate_bpm, source, measured_at) values (%L, 80, 'simulator', now() + interval '1 hour')$q$, u_ok), u_ok);
    r := r || pg_temp.ck('a vitals row dated 1 hour ahead is refused with reading_time_in_future', s = 'ERR P0001 reading_time_in_future', s);
    r := r || pg_temp.ck('a reading with the time left out (a live reading) is accepted',
      pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 140, 'simulator')$q$, u_ok), u_ok) = 'ok');

    -- Abort the block so every fake row above is rolled back. The report in r is kept.
    raise exception 'nl_rollback' using errcode = 'NL999';
  exception
    when sqlstate 'NL999' then
      null;
  end;

  ---------------------------------------------------------------
  -- After the rollback: what the real demo patients get right now (information only)
  ---------------------------------------------------------------
  for i in 1..10 loop
    select u.id into uid from auth.users u where lower(u.email) = 'patient' || lpad(i::text, 2, '0') || '@example.test';
    if uid is not null then
      v := pg_temp.st(uid);
      r := r || ('INFO|patient' || lpad(i::text, 2, '0') || ' gets status ' || coalesce(v ->> 'status', v ->> 'error')
                 || ' (reasons ' || coalesce((v -> 'reasons')::text, '-') || ', last belt check ' || coalesce(v ->> 'latest_belt_at', 'none') || ')|')::text;
    end if;
  end loop;
  r := r || ('INFO|expected for the demo patients while their data is still recent (right after the seed, or after pressing Check now): '
             || 'patient01 ok, 02 ok, 03 ok, 04 ok, 05 attention (open signal loss alert), 06 ok, 07 ok, 08 urgent (open alert and SOS), '
             || '09 attention (open fever alert), 10 urgent (open alert, no provider). Once the newest check is older than the window, a patient '
             || 'with nothing open correctly shows no_recent_data until a new check is saved.|')::text;

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')::text
    into pass_n, fail_n from unnest(r) e;
  return array['SUMMARY|' || pass_n || ' PASS, ' || fail_n || ' FAIL|' ||
               case when fail_n = '0' then 'patient Home status and SOS guard behave as designed' else 'send me every FAIL row' end] || r;
end
$fn$;

-- ---------------------------------------------------------------------
-- The report: SUMMARY first, then FAIL, then INFO, then PASS
-- ---------------------------------------------------------------------
select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_home_tests()) with ordinality as x(e, o)
order by 1;
