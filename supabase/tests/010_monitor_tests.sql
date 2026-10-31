-- =====================================================================
-- 010_monitor_tests.sql
-- NurtureLink step 3.2: proves that migration 010 does what it should.
--   * my_normal_ranges() returns the limits that the chart band needs, read
--     from alert_thresholds (nothing hard-coded), leaves out a disabled limit,
--     returns no severity or counts, and is closed to anon.
--   * A hand-typed ("manual") reading is accepted when it is a plain entry and
--     refused (manual_reading_invalid) when it names a device, claims a signal
--     quality, marks signal lost, is outside the entry limits or is back-dated.
--   * A reading dated in the future is refused (reading_time_in_future).
--   * A patient cannot add a reading for another patient or with another
--     patient's device, cannot edit or delete a reading, and cannot read
--     another patient's readings.
--   * Manual out-of-range values go through the NORMAL alert trigger: they
--     raise an alert only after the "N in a row" rule, and count together with
--     device and simulator readings.
--   * Readings that are not manual (old device readings sent after an offline
--     period) and the SQL Editor / demo seed are not affected by the guard.
--
-- HOW IT WORKS: like access_tests.sql and 009_patient_home_tests.sql. Clearly
-- fake users (emails end in ".invalid") and fake data are created inside ONE
-- block that is deliberately aborted at its end, so everything is rolled back
-- (the report survives). For each test the session switches to the role
-- "authenticated" or "anon" with a fake user's id in request.jwt.claims,
-- exactly like a real API request. The alert limits are set to known values
-- INSIDE the block, so the result does not depend on what you edited live;
-- that too is rolled back. Real data is never changed.
--
-- AFTER the block, one read-only INFO line shows the limits that are stored
-- RIGHT NOW. Compare it with the shaded band on the Monitor charts.
--
-- HOW TO RUN: run 010_monitor.sql first. Paste this WHOLE file into a new SQL
-- Editor tab and click Run (if asked about "destructive operations", click
-- Run: the file only creates temporary functions; the fake data is rolled
-- back). Result: one table, SUMMARY first, then FAIL, INFO, PASS.
-- Expected: "N PASS, 0 FAIL".
-- WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and every FAIL row.
--
-- DEPENDS ON: 000 to 010. READ-ONLY for your real data.
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

-- Number of rows a signed-in user can see with a "select count(*) ..." statement.
create or replace function pg_temp.cnt(p_sql text, p_uid uuid)
returns integer
language plpgsql
as $fn$
declare
  n integer;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  begin
    execute p_sql into n;
  exception when others then
    reset role;
    return -1;
  end;
  reset role;
  return n;
end
$fn$;

-- Call my_normal_ranges() as a signed-in user.
-- Returns the JSON, or {"error": "<sqlstate> <message>"} if the call failed.
create or replace function pg_temp.rg(p_uid uuid)
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
    v := public.my_normal_ranges();
  exception when others then
    reset role;
    return jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  reset role;
  return v;
end
$fn$;

-- Open alerts of one type for a patient (read as the owner, so RLS hides nothing).
create or replace function pg_temp.open_alerts(p_uid uuid, p_type text)
returns integer
language sql
as $fn$
  select count(*)::int from public.alerts where patient_id = p_uid and alert_type = p_type and status = 'open'
$fn$;

-- A typed belt entry as a signed-in patient. Extra columns can be added.
create or replace function pg_temp.manual_belt(p_uid uuid, p_fhr integer, p_extra_cols text default '', p_extra_vals text default '')
returns text
language sql
as $fn$
  select pg_temp.x(format(
    'insert into public.belt_readings (patient_id, fetal_hr_bpm, source%s) values (%L, %s, ''manual''%s)',
    p_extra_cols, p_uid, coalesce(p_fhr::text, 'null'), p_extra_vals), p_uid)
$fn$;

-- A typed vitals entry as a signed-in patient.
create or replace function pg_temp.manual_vit(p_uid uuid, p_cols text, p_vals text)
returns text
language sql
as $fn$
  select pg_temp.x(format(
    'insert into public.maternal_vitals (patient_id, source, %s) values (%L, ''manual'', %s)',
    p_cols, p_uid, p_vals), p_uid)
$fn$;

-- ---------------------------------------------------------------------
-- The tests
-- ---------------------------------------------------------------------
create or replace function pg_temp.nl_monitor_tests()
returns text[]
language plpgsql
as $fn$
declare
  r   text[] := '{}';
  u_a    uuid := gen_random_uuid();   -- patient with her own belt, manual entries
  u_b    uuid := gen_random_uuid();   -- another patient with her own belt
  u_fhr  uuid := gen_random_uuid();   -- three high typed heart rates in a row
  u_ok   uuid := gen_random_uuid();   -- three normal typed heart rates
  u_mix  uuid := gen_random_uuid();   -- simulator + typed readings together
  u_temp uuid := gen_random_uuid();   -- typed fever readings
  u_off  uuid := gen_random_uuid();   -- offline device reading sent late (not manual)
  p1     uuid := gen_random_uuid();   -- provider assigned to u_a
  d_a    uuid;
  d_b    uuid;
  v    jsonb;
  s    text;
  n    integer;
  i    integer;
  fn_exists boolean;
  trg_n integer;
  pass_n integer;
  fail_n text;
  live text;
begin
  fn_exists := to_regprocedure('public.my_normal_ranges()') is not null;
  r := r || pg_temp.ck('migration 010 has been run (my_normal_ranges() exists)', fn_exists,
    'run supabase/migrations/010_monitor.sql first');
  if not fn_exists then
    return array['SUMMARY|0 PASS, 1 FAIL|run supabase/migrations/010_monitor.sql first'] || r;
  end if;

  select count(*) into trg_n from pg_trigger t
   where t.tgname in ('belt_readings_guard_manual', 'maternal_vitals_guard_manual') and not t.tgisinternal and t.tgenabled = 'O';
  r := r || pg_temp.ck('both manual-reading guards exist and are enabled', trg_n = 2, trg_n::text || ' of 2 found');

  begin   -- everything in this block is rolled back at the end

    ---------------------------------------------------------------
    -- Fake users, devices and known limits
    ---------------------------------------------------------------
    insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
    select u, 'nl-monitor-' || u || '@nurturelink-test.invalid', now(), '{}'::jsonb
    from unnest(array[u_a, u_b, u_fhr, u_ok, u_mix, u_temp, u_off, p1]) u;
    update public.profiles set role = 'provider' where id = p1;
    insert into public.pregnancy_profiles (patient_id, assigned_provider_id, due_date) values (u_a, p1, current_date + 100);

    insert into public.devices (patient_id, kind, label) values (u_a, 'belt', 'test belt A') returning id into d_a;
    insert into public.devices (patient_id, kind, label) values (u_b, 'belt', 'test belt B') returning id into d_b;

    update public.alert_thresholds set min_value = 110, max_value = 160, sustained_count = 3, severity = 'critical', enabled = true, is_confirmed = false
      where alert_type = 'fhr_out_of_range';
    update public.alert_thresholds set min_value = null, max_value = null, sustained_count = 3, severity = 'warning', enabled = true
      where alert_type = 'signal_loss';
    update public.alert_thresholds set min_value = 95, max_value = null, sustained_count = 2, severity = 'warning', enabled = true, is_confirmed = false
      where alert_type = 'low_spo2';
    update public.alert_thresholds set min_value = null, max_value = 37.9, sustained_count = 2, severity = 'warning', enabled = true, is_confirmed = false
      where alert_type = 'fever';

    ---------------------------------------------------------------
    -- 1. my_normal_ranges(): the band for the charts
    ---------------------------------------------------------------
    r := r || pg_temp.ck('my_normal_ranges is SECURITY DEFINER, has a fixed search_path and takes no argument',
      exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'my_normal_ranges' and p.prosecdef and p.pronargs = 0
                and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')));
    r := r || pg_temp.ck('anon cannot run my_normal_ranges (permission denied)',
      pg_temp.x('select public.my_normal_ranges()', null, 'anon') like 'ERR 42501 permission denied for function%');
    v := pg_temp.rg(null);
    r := r || pg_temp.ck('signed in with no user id gets not_signed_in', (v ->> 'error') = 'P0001 not_signed_in', v::text);

    v := pg_temp.rg(u_a);
    r := r || pg_temp.ck('a patient gets the heart-rate limits from alert_thresholds (110 to 160, not confirmed)',
      (v #>> '{fhr,min}')::numeric = 110 and (v #>> '{fhr,max}')::numeric = 160 and (v #>> '{fhr,confirmed}') = 'false', v::text);
    r := r || pg_temp.ck('SpO2 has only a minimum (95) and temperature only a maximum (37.9)',
      (v #>> '{spo2,min}')::numeric = 95 and not (v -> 'spo2') ? 'max'
      and (v #>> '{temp,max}')::numeric = 37.9 and not (v -> 'temp') ? 'min', v::text);
    r := r || pg_temp.ck('the result carries no severity and no "in a row" counts',
      v::text not like '%severity%' and v::text not like '%sustained%' and v::text not like '%critical%', v::text);

    update public.alert_thresholds set min_value = 100, max_value = 170, is_confirmed = true where alert_type = 'fhr_out_of_range';
    v := pg_temp.rg(u_a);
    r := r || pg_temp.ck('the band follows the table: after an edit the new limits and the confirmed flag come back',
      (v #>> '{fhr,min}')::numeric = 100 and (v #>> '{fhr,max}')::numeric = 170 and (v #>> '{fhr,confirmed}') = 'true', v::text);
    update public.alert_thresholds set min_value = 110, max_value = 160, is_confirmed = false where alert_type = 'fhr_out_of_range';

    update public.alert_thresholds set enabled = false where alert_type = 'low_spo2';
    v := pg_temp.rg(u_a);
    r := r || pg_temp.ck('a disabled limit is left out (no band is drawn for it)', not v ? 'spo2' and v ? 'fhr', v::text);
    update public.alert_thresholds set enabled = true where alert_type = 'low_spo2';

    r := r || pg_temp.ck('a patient still cannot read alert_thresholds directly (0 rows)',
      pg_temp.cnt('select count(*) from public.alert_thresholds', u_a) = 0);

    ---------------------------------------------------------------
    -- 2. A plain typed belt entry
    ---------------------------------------------------------------
    s := pg_temp.manual_belt(u_a, 140);
    r := r || pg_temp.ck('a typed heart rate with no device and no time is accepted', s = 'ok', s);
    r := r || pg_temp.ck('it is stored as source manual, with no device, no signal quality, signal not lost, and the server time',
      exists (select 1 from public.belt_readings
              where patient_id = u_a and source = 'manual' and device_id is null and signal_quality is null
                and confidence is null and not signal_lost and fetal_hr_bpm = 140
                and abs(extract(epoch from (measured_at - now()))) < 5));

    s := pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source, client_id) values (%L, 141, 'manual', %L)$q$, u_a, 'aaaaaaaa-0000-4000-8000-000000000001'), u_a);
    r := r || pg_temp.ck('a typed entry with a client_id is accepted', s = 'ok', s);
    s := pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source, client_id) values (%L, 141, 'manual', %L)$q$, u_a, 'aaaaaaaa-0000-4000-8000-000000000001'), u_a);
    r := r || pg_temp.ck('sending the same entry again is refused as a duplicate (23505), so a retry never doubles it',
      s like 'ERR 23505%', s);
    r := r || pg_temp.ck('exactly one row exists for that client_id',
      (select count(*) from public.belt_readings where patient_id = u_a and client_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 1);

    r := r || pg_temp.ck('the entry limits are inclusive: 60 and 220 are accepted',
      pg_temp.manual_belt(u_a, 60) = 'ok' and pg_temp.manual_belt(u_a, 220) = 'ok');
    s := pg_temp.manual_belt(u_a, 59);
    r := r || pg_temp.ck('59 is refused with manual_reading_invalid', s = 'ERR P0001 manual_reading_invalid', s);
    s := pg_temp.manual_belt(u_a, 221);
    r := r || pg_temp.ck('221 is refused with manual_reading_invalid', s = 'ERR P0001 manual_reading_invalid', s);
    s := pg_temp.manual_belt(u_a, null);
    r := r || pg_temp.ck('a typed entry with no heart rate is refused', s like 'ERR %', s);

    s := pg_temp.manual_belt(u_a, 140, ', device_id', format(', %L', d_a));
    r := r || pg_temp.ck('a typed entry that names a device (even her own) is refused', s = 'ERR P0001 manual_reading_invalid', s);
    s := pg_temp.manual_belt(u_a, 140, ', signal_lost', ', true');
    r := r || pg_temp.ck('a typed entry that marks the signal as lost is refused', s = 'ERR P0001 manual_reading_invalid', s);
    s := pg_temp.manual_belt(u_a, 140, ', signal_quality', ', 95');
    r := r || pg_temp.ck('a typed entry that claims a signal quality is refused', s = 'ERR P0001 manual_reading_invalid', s);
    s := pg_temp.manual_belt(u_a, 140, ', confidence', ', 95');
    r := r || pg_temp.ck('a typed entry that claims a confidence is refused', s = 'ERR P0001 manual_reading_invalid', s);
    s := pg_temp.manual_belt(u_a, 140, ', measured_at', ', now() - interval ''1 hour''');
    r := r || pg_temp.ck('a typed entry dated 1 hour ago is refused (it cannot be back-dated)', s = 'ERR P0001 manual_reading_invalid', s);
    s := pg_temp.manual_belt(u_a, 140, ', measured_at', ', now() - interval ''5 minutes''');
    r := r || pg_temp.ck('a typed entry dated 5 minutes ago is accepted (a slow phone)', s = 'ok', s);
    s := pg_temp.manual_belt(u_a, 140, ', measured_at', ', now() + interval ''1 hour''');
    r := r || pg_temp.ck('a typed entry dated 1 hour ahead is refused with reading_time_in_future', s = 'ERR P0001 reading_time_in_future', s);
    s := pg_temp.manual_belt(u_a, 140, ', measured_at', ', now() + interval ''2 minutes''');
    r := r || pg_temp.ck('a typed entry 2 minutes ahead (a fast clock) is accepted', s = 'ok', s);

    ---------------------------------------------------------------
    -- 3. Typed vitals
    ---------------------------------------------------------------
    r := r || pg_temp.ck('typed vitals are accepted: heart rate only, SpO2 only, temperature only, all three',
      pg_temp.manual_vit(u_a, 'heart_rate_bpm', '80') = 'ok'
      and pg_temp.manual_vit(u_a, 'spo2_percent', '97') = 'ok'
      and pg_temp.manual_vit(u_a, 'temperature_c', '36.8') = 'ok'
      and pg_temp.manual_vit(u_a, 'heart_rate_bpm, spo2_percent, temperature_c', '80, 97, 36.8') = 'ok');
    r := r || pg_temp.ck('vitals limits are inclusive: 30 and 220 bpm, SpO2 70 and 100, 34.0 and 42.0 degrees',
      pg_temp.manual_vit(u_a, 'heart_rate_bpm', '30') = 'ok' and pg_temp.manual_vit(u_a, 'heart_rate_bpm', '220') = 'ok'
      and pg_temp.manual_vit(u_a, 'spo2_percent', '70') = 'ok' and pg_temp.manual_vit(u_a, 'spo2_percent', '100') = 'ok'
      and pg_temp.manual_vit(u_a, 'temperature_c', '34.0') = 'ok' and pg_temp.manual_vit(u_a, 'temperature_c', '42.0') = 'ok');
    r := r || pg_temp.ck('vitals just outside are refused with manual_reading_invalid (29, 221, 69, 101, 33.9, 42.1)',
      pg_temp.manual_vit(u_a, 'heart_rate_bpm', '29') = 'ERR P0001 manual_reading_invalid'
      and pg_temp.manual_vit(u_a, 'heart_rate_bpm', '221') = 'ERR P0001 manual_reading_invalid'
      and pg_temp.manual_vit(u_a, 'spo2_percent', '69') = 'ERR P0001 manual_reading_invalid'
      and pg_temp.manual_vit(u_a, 'spo2_percent', '101') = 'ERR P0001 manual_reading_invalid'
      and pg_temp.manual_vit(u_a, 'temperature_c', '33.9') = 'ERR P0001 manual_reading_invalid'
      and pg_temp.manual_vit(u_a, 'temperature_c', '42.1') = 'ERR P0001 manual_reading_invalid');
    s := pg_temp.manual_vit(u_a, 'heart_rate_bpm, device_id', format('80, %L', d_a));
    r := r || pg_temp.ck('typed vitals that name a device are refused', s = 'ERR P0001 manual_reading_invalid', s);
    s := pg_temp.manual_vit(u_a, 'heart_rate_bpm, measured_at', '80, now() - interval ''1 hour''');
    r := r || pg_temp.ck('typed vitals dated 1 hour ago are refused', s = 'ERR P0001 manual_reading_invalid', s);
    s := pg_temp.manual_vit(u_a, 'heart_rate_bpm, measured_at', '80, now() + interval ''1 hour''');
    r := r || pg_temp.ck('typed vitals dated 1 hour ahead are refused with reading_time_in_future', s = 'ERR P0001 reading_time_in_future', s);

    ---------------------------------------------------------------
    -- 4. Whose reading is it? Devices, other patients, edits, visibility
    ---------------------------------------------------------------
    s := pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 140, 'manual')$q$, u_b), u_a);
    r := r || pg_temp.ck('a patient cannot add a reading for another patient (row-level security)',
      s like 'ERR 42501 new row violates row-level security%', s);
    s := pg_temp.manual_belt(u_a, 140, ', device_id', format(', %L', d_b));
    r := r || pg_temp.ck('a typed entry that names ANOTHER patient''s device is refused', s like 'ERR %', s);
    s := pg_temp.x(format($q$insert into public.belt_readings (patient_id, device_id, fetal_hr_bpm, signal_quality, source) values (%L, %L, 140, 90, 'simulator')$q$, u_a, d_b), u_a);
    r := r || pg_temp.ck('a non-manual reading with ANOTHER patient''s device is refused by the existing policy (42501)',
      s like 'ERR 42501 new row violates row-level security%', s);
    s := pg_temp.x(format($q$insert into public.belt_readings (patient_id, device_id, fetal_hr_bpm, signal_quality, source) values (%L, %L, 140, 90, 'simulator')$q$, u_a, d_a), u_a);
    r := r || pg_temp.ck('a simulator reading with her OWN device still works (unchanged)', s = 'ok', s);
    s := pg_temp.x(format($q$insert into public.maternal_vitals (patient_id, device_id, heart_rate_bpm, source) values (%L, %L, 80, 'simulator')$q$, u_a, d_b), u_a);
    r := r || pg_temp.ck('vitals with ANOTHER patient''s device are refused (42501)', s like 'ERR 42501 new row violates row-level security%', s);

    r := r || pg_temp.ck('a patient cannot edit a stored reading (permission denied)',
      pg_temp.x(format($q$update public.belt_readings set fetal_hr_bpm = 150 where patient_id = %L$q$, u_a), u_a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient cannot delete a stored reading (permission denied)',
      pg_temp.x(format($q$delete from public.belt_readings where patient_id = %L$q$, u_a), u_a) like 'ERR 42501 permission denied%');

    r := r || pg_temp.ck('the patient sees her own typed readings (the history query works)',
      pg_temp.cnt(format($q$select count(*) from public.belt_readings where patient_id = %L and source = 'manual'$q$, u_a), u_a) >= 3);
    r := r || pg_temp.ck('another patient sees none of them',
      pg_temp.cnt(format($q$select count(*) from public.belt_readings where patient_id = %L$q$, u_a), u_b) = 0);
    r := r || pg_temp.ck('the assigned provider sees them',
      pg_temp.cnt(format($q$select count(*) from public.belt_readings where patient_id = %L and source = 'manual'$q$, u_a), p1) >= 3);
    r := r || pg_temp.ck('a patient with no readings at all gets an empty list, not an error',
      pg_temp.cnt(format($q$select count(*) from public.belt_readings where patient_id = %L$q$, u_off), u_off) = 0);

    ---------------------------------------------------------------
    -- 5. Typed values go through the NORMAL alert trigger
    ---------------------------------------------------------------
    for i in 1..2 loop
      s := pg_temp.manual_belt(u_fhr, 170);
    end loop;
    r := r || pg_temp.ck('two typed high heart rates in a row raise no alert yet (limit is 3 in a row)',
      pg_temp.open_alerts(u_fhr, 'fhr_out_of_range') = 0);
    s := pg_temp.manual_belt(u_fhr, 170);
    r := r || pg_temp.ck('the third typed high heart rate raises one open fhr_out_of_range alert',
      s = 'ok' and pg_temp.open_alerts(u_fhr, 'fhr_out_of_range') = 1, s);
    r := r || pg_temp.ck('that alert records the value and points at a typed (manual) reading',
      exists (select 1 from public.alerts a join public.belt_readings b on b.id = a.belt_reading_id
              where a.patient_id = u_fhr and a.alert_type = 'fhr_out_of_range' and a.status = 'open'
                and b.source = 'manual' and (a.details ->> 'value')::int = 170));
    s := pg_temp.manual_belt(u_fhr, 175);
    r := r || pg_temp.ck('a fourth high value does not create a second open alert', pg_temp.open_alerts(u_fhr, 'fhr_out_of_range') = 1, s);

    for i in 1..3 loop
      s := pg_temp.manual_belt(u_ok, 140);
    end loop;
    r := r || pg_temp.ck('three typed normal heart rates raise no alert', pg_temp.open_alerts(u_ok, 'fhr_out_of_range') = 0);

    insert into public.belt_readings (patient_id, fetal_hr_bpm, signal_quality, source, measured_at)
      values (u_mix, 104, 85, 'simulator', now() - interval '2 hours'), (u_mix, 103, 85, 'simulator', now() - interval '1 hour');
    s := pg_temp.manual_belt(u_mix, 105);
    r := r || pg_temp.ck('two simulator lows plus one typed low in a row raise the alert (typed values count like any other)',
      s = 'ok' and pg_temp.open_alerts(u_mix, 'fhr_out_of_range') = 1, s);

    s := pg_temp.manual_vit(u_temp, 'temperature_c', '38.4');
    r := r || pg_temp.ck('one typed fever reading raises no alert yet (limit is 2 in a row)', pg_temp.open_alerts(u_temp, 'fever') = 0, s);
    s := pg_temp.manual_vit(u_temp, 'temperature_c', '38.6');
    r := r || pg_temp.ck('the second typed fever reading raises one open fever alert', s = 'ok' and pg_temp.open_alerts(u_temp, 'fever') = 1, s);

    ---------------------------------------------------------------
    -- 6. What the guard must NOT touch
    ---------------------------------------------------------------
    s := pg_temp.x(format($q$insert into public.belt_readings (patient_id, device_id, fetal_hr_bpm, signal_quality, confidence, source, measured_at, client_id)
                             values (%L, null, 140, 90, 90, 'device', now() - interval '2 days', gen_random_uuid())$q$, u_off), u_off);
    r := r || pg_temp.ck('an old device reading sent after an offline period is still accepted (not a typed entry)', s = 'ok', s);
    s := pg_temp.x(format($q$insert into public.belt_readings (patient_id, signal_quality, signal_lost, source) values (%L, 5, true, 'simulator')$q$, u_off), u_off);
    r := r || pg_temp.ck('a non-typed signal-lost reading is still accepted', s = 'ok', s);
    s := null;
    begin
      insert into public.maternal_vitals (patient_id, device_id, heart_rate_bpm, source, measured_at)
        values (u_off, d_a, 99, 'manual', now() - interval '3 days');
      insert into public.belt_readings (patient_id, device_id, fetal_hr_bpm, signal_quality, source, measured_at)
        values (u_off, d_a, 99, 90, 'manual', now() - interval '3 days');
      s := 'ok';
    exception when others then
      s := 'ERR ' || sqlstate || ' ' || sqlerrm;
    end;
    r := r || pg_temp.ck('the SQL Editor and the demo seed (owner role) can still insert back-dated typed rows with a device', s = 'ok', s);
    r := r || pg_temp.ck('nobody can call the guard function directly',
      pg_temp.x('select public.guard_manual_reading()', u_a) like 'ERR 42501 permission denied for function%'
      and pg_temp.x('select public.guard_manual_reading()', null, 'anon') like 'ERR 42501 permission denied for function%');

    -- Abort the block so every fake row above is rolled back. The report in r is kept.
    raise exception 'nl_rollback' using errcode = 'NL999';
  exception
    when sqlstate 'NL999' then
      null;
  end;

  ---------------------------------------------------------------
  -- After the rollback: the limits stored right now (information only)
  ---------------------------------------------------------------
  select string_agg(alert_type || ' ' || coalesce(min_value::text, '-') || ' to ' || coalesce(max_value::text, '-')
                    || case when enabled then '' else ' (disabled)' end
                    || case when is_confirmed then ' (confirmed)' else ' (not confirmed)' end,
                    '; ' order by alert_type)
    into live
  from public.alert_thresholds
  where alert_type in ('fhr_out_of_range', 'low_spo2', 'fever');
  r := r || ('INFO|the shaded bands on the Monitor charts should match these stored limits right now: ' || coalesce(live, 'none') || '|')::text;

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')::text
    into pass_n, fail_n from unnest(r) e;
  return array['SUMMARY|' || pass_n || ' PASS, ' || fail_n || ' FAIL|' ||
               case when fail_n = '0' then 'Monitor tab database rules hold' else 'send me every FAIL row' end] || r;
end
$fn$;

-- ---------------------------------------------------------------------
-- The report: SUMMARY first, then FAIL, then INFO, then PASS
-- ---------------------------------------------------------------------
select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_monitor_tests()) with ordinality as x(e, o)
order by 1;
