-- =====================================================================
-- 014_phase3_review_tests.sql
-- NurtureLink step 3.6 (Phase 3 review): proves that migration 014 does what it
-- says, and that it does not break the rules that were already in place.
--
--   * Reading cap: at most 600 rows per patient per table in the last hour for an
--     API request (belt_readings and maternal_vitals counted separately); the 601st
--     row is refused with too_many_readings; a 601-row single statement stores
--     nothing; typed rows count; back-dated measured_at does not help; rows older
--     than an hour do not count; another patient is unaffected; the SQL Editor
--     (database owner) is not limited; the alert rule still works under the cap.
--   * Devices: at most 5 per patient (too_many_devices); hardware_id at most 100
--     characters on insert and update; other patients unaffected; the owner is
--     not limited by the count.
--   * Alert limits: signed-in users (patient, provider, admin) have no UPDATE on
--     alert_thresholds, on the table or on any column; providers still read all 4;
--     patients read none; the owner can still change them.
--   * JSON size: an API insert into alerts or audit_log with details over 2000
--     bytes is refused (details_too_large), exactly 2000 passes; the owner is not
--     limited; the SOS rate limit still holds.
--   * Nothing else moved: still exactly 14 client functions, anon still has
--     nothing, the three new trigger functions cannot be run from the API.
--
-- ALL NUMBERS TESTED HERE (600 an hour, 5 devices, 100 characters, 2000 bytes) ARE
-- DRAFT DEFAULTS chosen by the project owner on 2026-11-02.
--
-- HOW IT WORKS: like 013_patient_profile_tests.sql. Clearly fake users (emails end
-- in ".invalid") are created inside ONE block that is deliberately aborted at its
-- end, so everything is rolled back (the report survives). Each test switches to
-- the role "authenticated" or "anon" with a fake user's id in request.jwt.claims,
-- like a real API request. Real data is never changed.
--
-- NOT PROVEN BY THIS FILE:
--   - two requests at the very same moment (one session only). The caps take a
--     per-patient advisory lock, the same method as the SOS limit.
--   - how the live API behaves with a very large request body (limits in front of
--     the database are not visible from SQL).
--   - the app screens: this file changes no screen.
--
-- HOW TO RUN: run 014_phase3_review_hardening.sql first. Paste this WHOLE file
-- into a new SQL Editor tab and click Run (if asked about "destructive
-- operations", click Run: it only creates temporary functions; the fake data is
-- rolled back). Result: one table, SUMMARY first, then FAIL, INFO, PASS.
-- WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and every FAIL row (or the
-- error text if the whole file stops with an error).
--
-- DEPENDS ON: 000 to 014. READ-ONLY for your real data.
-- SAFE TO RE-RUN: yes, any number of times. HOW TO UNDO: nothing to undo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers (temporary: they disappear when the session ends)
-- ---------------------------------------------------------------------
-- Run a statement as a role and fake user. 'ok' or 'ERR <sqlstate> <message>'.
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

-- Run a query that returns ONE integer as a role and fake user. -1 on any error.
create or replace function pg_temp.q(p_sql text, p_uid uuid default null, p_role text default 'authenticated')
returns integer
language plpgsql
as $fn$
declare
  v integer;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
    reset role;
    return v;
  exception when others then
    reset role;
    return -1;
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

-- Statement texts used several times.
create or replace function pg_temp.belt_rows(p_patient uuid, p_count integer, p_source text default 'device', p_age text default '1 second')
returns text
language sql
as $fn$
  select format('insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at) select %L, 140, %L, now() - (g || %L)::interval from generate_series(1, %s) g',
                p_patient, p_source, ' ' || split_part(p_age, ' ', 2), p_count)
$fn$;

create or replace function pg_temp.vital_rows(p_patient uuid, p_count integer)
returns text
language sql
as $fn$
  select format('insert into public.maternal_vitals (patient_id, heart_rate_bpm, source, measured_at) select %L, 80, %L, now() - (g || %L)::interval from generate_series(1, %s) g',
                p_patient, 'device', ' seconds', p_count)
$fn$;

-- ---------------------------------------------------------------------
-- The tests
-- ---------------------------------------------------------------------
create or replace function pg_temp.nl_014_tests()
returns text[]
language plpgsql
as $fn$
declare
  r  text[] := '{}';
  pa uuid := gen_random_uuid();   -- patient A: belt cap, assigned to P1
  pb uuid := gen_random_uuid();   -- patient B: independent patient, devices belt + band
  pc uuid := gen_random_uuid();   -- patient C: vitals cap
  pd uuid := gen_random_uuid();   -- patient D: 601 rows in one statement
  pf uuid := gen_random_uuid();   -- patient F: filled by the owner, then tries the API
  pg uuid := gen_random_uuid();   -- patient G: aged rows
  ph uuid := gen_random_uuid();   -- patient H: 59 minute boundary
  pi uuid := gen_random_uuid();   -- patient I: details tests, assigned to P1
  pj uuid := gen_random_uuid();   -- patient J: device count
  pk uuid := gen_random_uuid();   -- patient K: hardware_id length
  pm uuid := gen_random_uuid();   -- patient M: alert path under the cap
  pn uuid := gen_random_uuid();   -- patient N: SOS rate limit
  pe uuid := gen_random_uuid();   -- patient E: a SOS with exactly 2000 bytes
  p1 uuid := gen_random_uuid();   -- provider 1 (assigned to A and I)
  p2 uuid := gen_random_uuid();   -- provider 2 (assigned to nobody)
  ad uuid := gen_random_uuid();   -- admin account
  s  text;
  s2 text;
  n  integer;
  n2 integer;
  sig text;
  fid oid;
  big text;
  pass_n integer;
  fail_n text;
begin
  begin   -- everything in this block is rolled back at the end

    ---------------------------------------------------------------
    -- Fake users and rows (created as the database owner)
    ---------------------------------------------------------------
    insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
    select u, 'nl-014-' || u || '@nurturelink-test.invalid', now(), '{}'::jsonb
    from unnest(array[pa, pb, pc, pd, pf, pg, ph, pi, pj, pk, pm, pn, pe, p1, p2, ad]) u;
    update public.profiles set role = 'provider' where id in (p1, p2);
    update public.profiles set role = 'admin' where id = ad;
    insert into public.pregnancy_profiles (patient_id, assigned_provider_id) values (pa, p1), (pi, p1);

    ---------------------------------------------------------------
    -- 0. The migration as built
    ---------------------------------------------------------------
    foreach sig in array array['public.guard_reading_rate()', 'public.guard_device_limits()', 'public.guard_details_size()'] loop
      fid := to_regprocedure(sig);
      r := r || pg_temp.ck(sig || ' exists, is SECURITY INVOKER with a fixed search_path, and nobody can run it from the API (anon, PUBLIC, signed-in)',
        fid is not null
        and exists (select 1 from pg_proc p where p.oid = fid and not p.prosecdef
                    and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%'))
        and not has_function_privilege('anon', fid, 'EXECUTE')
        and not has_function_privilege('public', fid, 'EXECUTE')
        and not has_function_privilege('authenticated', fid, 'EXECUTE'));
    end loop;
    r := r || pg_temp.ck('the 5 new triggers exist and are enabled',
      (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
        where c.relnamespace = 'public'::regnamespace and not t.tgisinternal and t.tgenabled = 'O'
          and t.tgname in ('belt_readings_guard_rate', 'maternal_vitals_guard_rate', 'devices_guard_limits',
                           'alerts_guard_details', 'audit_log_guard_details')) = 5);
    r := r || pg_temp.ck('the hardware_id length constraint exists',
      exists (select 1 from pg_constraint where conname = 'devices_hardware_id_length' and conrelid = 'public.devices'::regclass));
    r := r || pg_temp.ck('signed-in users can execute exactly 14 functions in public (014 added no client function)',
      (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname <> 'rls_auto_enable'
          and has_function_privilege('authenticated', p.oid, 'EXECUTE')) = 14);   -- rls_auto_enable() is Supabase's own (see access_tests INFO)
    r := r || pg_temp.ck('anon can execute no function in public and has no privilege on alert_thresholds, belt_readings, maternal_vitals, devices, alerts or audit_log',
      not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname <> 'rls_auto_enable' and has_function_privilege('anon', p.oid, 'EXECUTE'))
      and not exists (select 1 from unnest(array['alert_thresholds','belt_readings','maternal_vitals','devices','alerts','audit_log']) t
                      where has_table_privilege('anon', 'public.' || t, 'SELECT,INSERT,UPDATE,DELETE')));
    r := r || pg_temp.ck('alert_thresholds: signed-in users can SELECT but have no UPDATE on the table or on any column, and no UPDATE policy exists',
      has_table_privilege('authenticated', 'public.alert_thresholds', 'SELECT')
      and not has_table_privilege('authenticated', 'public.alert_thresholds', 'INSERT,UPDATE,DELETE,TRUNCATE')
      and not exists (select 1 from pg_attribute a
                      where a.attrelid = 'public.alert_thresholds'::regclass and a.attnum > 0 and not a.attisdropped
                        and (has_column_privilege('authenticated', 'public.alert_thresholds', a.attnum, 'UPDATE')
                             or has_column_privilege('authenticated', 'public.alert_thresholds', a.attnum, 'INSERT')))
      and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'alert_thresholds' and cmd in ('UPDATE', 'ALL', 'INSERT', 'DELETE'))
      and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'alert_thresholds' and cmd = 'SELECT'));

    ---------------------------------------------------------------
    -- 1. Reading cap: belt_readings
    ---------------------------------------------------------------
    s := pg_temp.x(pg_temp.belt_rows(pa, 600), pa);
    n := (select count(*)::int from public.belt_readings where patient_id = pa);
    r := r || pg_temp.ck('A inserts 600 belt readings in one request: all accepted', s = 'ok' and n = 600, s || ' rows=' || n);

    s := pg_temp.x(pg_temp.belt_rows(pa, 1), pa);
    n := (select count(*)::int from public.belt_readings where patient_id = pa);
    r := r || pg_temp.ck('the 601st belt reading within the hour is refused with too_many_readings and not stored',
      s like 'ERR P0001 too_many_readings' and n = 600, s || ' rows=' || n);

    s := pg_temp.x(format('insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at) values (%L, 140, %L, now() - interval %L)', pa, 'device', '30 days'), pa);
    r := r || pg_temp.ck('a back-dated measured_at does not dodge the cap (it counts by server time)', s like 'ERR P0001 too_many_readings', s);

    s := pg_temp.x(format('insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 140, %L)', pa, 'manual'), pa);
    r := r || pg_temp.ck('a typed (manual) reading is also refused once the cap is reached', s like 'ERR P0001 too_many_readings', s);

    s := pg_temp.x(format('insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 140, %L)', pb, 'device'), pa);
    r := r || pg_temp.ck('A still cannot insert for B (row-level security, as before): the cap never takes B''s lock or count',
      s like 'ERR 42501 new row violates row-level security policy%', s);

    s := pg_temp.x(pg_temp.belt_rows(pb, 5), pb);
    n := (select count(*)::int from public.belt_readings where patient_id = pb);
    r := r || pg_temp.ck('B is not affected by A being at the cap', s = 'ok' and n = 5, s || ' rows=' || n);

    s := pg_temp.x(pg_temp.vital_rows(pa, 1), pa);
    r := r || pg_temp.ck('A being at the belt cap does not block A''s vitals (the tables are counted separately)', s = 'ok', s);

    -- one statement of 601 rows stores nothing
    s := pg_temp.x(pg_temp.belt_rows(pd, 601), pd);
    n := (select count(*)::int from public.belt_readings where patient_id = pd);
    r := r || pg_temp.ck('601 readings in ONE statement: refused and none stored (all or nothing)', s like 'ERR P0001 too_many_readings' and n = 0, s || ' rows=' || n);

    -- the owner (SQL Editor, seed) is not limited, and its rows count for the API
    insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at)
      select pf, 140, 'device', now() - (g || ' seconds')::interval from generate_series(1, 700) g;
    n := (select count(*)::int from public.belt_readings where patient_id = pf);
    r := r || pg_temp.ck('the database owner can insert 700 readings for a patient (the cap is for API requests only)', n = 700, 'rows=' || n);
    s := pg_temp.x(format('insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 140, %L)', pf, 'manual'), pf);
    r := r || pg_temp.ck('...and then the patient''s own API request is refused (those rows are within the hour)', s like 'ERR P0001 too_many_readings', s);

    -- rows older than the window do not count
    insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at, created_at)
      select pg, 140, 'device', now() - (g || ' seconds')::interval, now() - interval '2 hours' from generate_series(1, 650) g;
    s := pg_temp.x(pg_temp.belt_rows(pg, 3), pg);
    n := (select count(*)::int from public.belt_readings where patient_id = pg and created_at > now() - interval '1 hour');
    r := r || pg_temp.ck('650 readings created 2 hours ago do not count: the patient can add new ones', s = 'ok' and n = 3, s || ' recent=' || n);

    insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at, created_at)
      select ph, 140, 'device', now() - (g || ' seconds')::interval, now() - interval '59 minutes' from generate_series(1, 600) g;
    s := pg_temp.x(pg_temp.belt_rows(ph, 1), ph);
    r := r || pg_temp.ck('600 readings created 59 minutes ago still count (the window is a full hour)', s like 'ERR P0001 too_many_readings', s);

    ---------------------------------------------------------------
    -- 1b. Reading cap: maternal_vitals
    ---------------------------------------------------------------
    s := pg_temp.x(pg_temp.vital_rows(pc, 600), pc);
    n := (select count(*)::int from public.maternal_vitals where patient_id = pc);
    r := r || pg_temp.ck('C inserts 600 vitals rows: all accepted', s = 'ok' and n = 600, s || ' rows=' || n);
    s := pg_temp.x(pg_temp.vital_rows(pc, 1), pc);
    n := (select count(*)::int from public.maternal_vitals where patient_id = pc);
    r := r || pg_temp.ck('the 601st vitals row within the hour is refused with too_many_readings', s like 'ERR P0001 too_many_readings' and n = 600, s || ' rows=' || n);
    s := pg_temp.x(format('insert into public.maternal_vitals (patient_id, heart_rate_bpm, source) values (%L, 80, %L)', pc, 'manual'), pc);
    r := r || pg_temp.ck('a typed vitals row is refused too', s like 'ERR P0001 too_many_readings', s);

    -- the alert rule still works well under the cap
    s := pg_temp.x(format('insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 171, %L)', pm, 'device'), pm);
    s := s || pg_temp.x(format('insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 172, %L)', pm, 'device'), pm);
    s := s || pg_temp.x(format('insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 173, %L)', pm, 'device'), pm);
    n := (select count(*)::int from public.alerts where patient_id = pm and alert_type = 'fhr_out_of_range' and status = 'open');
    r := r || pg_temp.ck('three out of range heart rates in a row still create the alert for the patient (the alert path is not blocked)', s = 'okokok' and n = 1, s || ' alerts=' || n);

    ---------------------------------------------------------------
    -- 2. Devices
    ---------------------------------------------------------------
    s := '';
    for n in 1..5 loop
      s := s || pg_temp.x(format('insert into public.devices (patient_id, kind, label) values (%L, %L, %L)', pj, case when n % 2 = 1 then 'belt' else 'band' end, 'dev ' || n), pj);
    end loop;
    n := (select count(*)::int from public.devices where patient_id = pj);
    r := r || pg_temp.ck('J registers 5 devices: all accepted', s = 'okokokokok' and n = 5, s || ' rows=' || n);
    s := pg_temp.x(format('insert into public.devices (patient_id, kind) values (%L, %L)', pj, 'belt'), pj);
    n := (select count(*)::int from public.devices where patient_id = pj);
    r := r || pg_temp.ck('the 6th device is refused with too_many_devices and not stored', s like 'ERR P0001 too_many_devices' and n = 5, s || ' rows=' || n);
    s := pg_temp.x(format('insert into public.devices (patient_id, kind) select %L, %L from generate_series(1, 50)', pb, 'belt'), pb);
    n := (select count(*)::int from public.devices where patient_id = pb);
    r := r || pg_temp.ck('50 devices in one statement: refused and none stored', s like 'ERR P0001 too_many_devices' and n = 0, s || ' rows=' || n);
    s := pg_temp.x(format('insert into public.devices (patient_id, kind, label) values (%L, %L, %L), (%L, %L, %L)', pb, 'belt', 'my belt', pb, 'band', 'my band'), pb);
    n := (select count(*)::int from public.devices where patient_id = pb);
    r := r || pg_temp.ck('B (another patient) can still register a belt and a band', s = 'ok' and n = 2, s || ' rows=' || n);
    s := pg_temp.x(format('update public.devices set battery_percent = 50, label = %L where patient_id = %L', 'renamed', pj), pj);
    r := r || pg_temp.ck('J can still edit existing devices at the cap (updates are not counted)', s = 'ok', s);
    insert into public.devices (patient_id, kind) values (pj, 'belt');
    n := (select count(*)::int from public.devices where patient_id = pj);
    r := r || pg_temp.ck('the database owner is not limited by the count (6 rows)', n = 6, 'rows=' || n);
    s := pg_temp.x(format('insert into public.devices (patient_id, kind) values (%L, %L)', pb, 'belt'), pj);
    r := r || pg_temp.ck('J cannot insert a device for B (row-level security)', s like 'ERR 42501 new row violates row-level security policy%', s);

    s := pg_temp.x(format('insert into public.devices (patient_id, kind, hardware_id) values (%L, %L, %L)', pk, 'belt', repeat('h', 100)), pk);
    r := r || pg_temp.ck('a hardware_id of exactly 100 characters is accepted', s = 'ok', s);
    s := pg_temp.x(format('insert into public.devices (patient_id, kind, hardware_id) values (%L, %L, %L)', pk, 'band', repeat('h', 101)), pk);
    r := r || pg_temp.ck('a hardware_id of 101 characters is refused on insert (check violation)', s like 'ERR 23514%devices_hardware_id_length%', s);
    s := pg_temp.x(format('update public.devices set hardware_id = %L where patient_id = %L', repeat('h', 101), pk), pk);
    r := r || pg_temp.ck('...and on update', s like 'ERR 23514%devices_hardware_id_length%', s);
    s := pg_temp.x(format('insert into public.devices (patient_id, kind, hardware_id) values (%L, %L, %L)', pk, 'band', repeat('h', 1000000)), pk);
    n := (select count(*)::int from public.devices where patient_id = pk);
    r := r || pg_temp.ck('a 1 MB hardware_id is refused and nothing is stored', s like 'ERR 23514%' and n = 1, s || ' rows=' || n);

    ---------------------------------------------------------------
    -- 3. Alert limits are admin-only
    ---------------------------------------------------------------
    n := pg_temp.q('select count(*)::int from public.alert_thresholds', p1);
    r := r || pg_temp.ck('a provider still reads all 4 alert limits', n = 4, 'rows=' || n);
    n := pg_temp.q('select count(*)::int from public.alert_thresholds', pa);
    r := r || pg_temp.ck('a patient reads none of them', n = 0, 'rows=' || n);
    r := r || pg_temp.ck('a provider cannot edit any limit column (permission denied), even on an assigned patient''s alert type',
      pg_temp.x($q$update public.alert_thresholds set enabled = false$q$, p1) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$update public.alert_thresholds set sustained_count = 32767 where alert_type = 'fhr_out_of_range'$q$, p1) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$update public.alert_thresholds set min_value = -1000, max_value = 100000 where alert_type = 'fhr_out_of_range'$q$, p1) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$update public.alert_thresholds set severity = 'info' where alert_type = 'fhr_out_of_range'$q$, p1) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$update public.alert_thresholds set notes = 'x' where alert_type = 'fhr_out_of_range'$q$, p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('an UNASSIGNED provider, a patient and an admin account cannot edit them either',
      pg_temp.x($q$update public.alert_thresholds set enabled = false$q$, p2) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$update public.alert_thresholds set enabled = false$q$, pa) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$update public.alert_thresholds set enabled = false$q$, ad) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('nobody can insert or delete a limit row from the API',
      pg_temp.x($q$delete from public.alert_thresholds$q$, p1) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$insert into public.alert_thresholds (alert_type, severity) values ('fever', 'info')$q$, p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('all 4 limits are still enabled and unchanged after those attempts',
      (select count(*) from public.alert_thresholds where enabled and sustained_count <= 3) = 4
      and (select min_value from public.alert_thresholds where alert_type = 'fhr_out_of_range') = 110
      and (select max_value from public.alert_thresholds where alert_type = 'fhr_out_of_range') = 160);

    -- the owner can still change a limit (ADMIN_SQL snippet 6)
    update public.alert_thresholds set is_confirmed = true where alert_type = 'fever';
    update public.alert_thresholds set max_value = 38.4 where alert_type = 'fever';
    r := r || pg_temp.ck('the database owner can still edit a limit (this is the admin path)',
      (select max_value from public.alert_thresholds where alert_type = 'fever') = 38.4);
    r := r || pg_temp.ck('NOTE: an owner edit does NOT clear is_confirmed by itself (the guard trigger acts only for API roles), so the admin must clear it by hand: documented in ADMIN_SQL snippet 6',
      (select is_confirmed from public.alert_thresholds where alert_type = 'fever') = true);

    ---------------------------------------------------------------
    -- 4. JSON size cap
    ---------------------------------------------------------------
    -- find the length of the string that makes the stored text exactly 2000 bytes
    n := 2000 - (octet_length(jsonb_build_object('x', 'a')::text) - 1);
    r := r || pg_temp.ck('(helper) a details value built with ' || n || ' characters is exactly 2000 bytes as text',
      octet_length(jsonb_build_object('x', repeat('a', n))::text) = 2000);

    s := pg_temp.x(format('insert into public.alerts (patient_id, alert_type, severity) values (%L, %L, %L)', pi, 'sos', 'critical'), pi);
    r := r || pg_temp.ck('a normal SOS (the app sends no details) is accepted', s = 'ok', s);

    s := pg_temp.x(format('insert into public.alerts (patient_id, alert_type, severity, details) values (%L, %L, %L, jsonb_build_object(%L, repeat(%L, %s)))', pe, 'sos', 'critical', 'x', 'a', n), pe);
    r := r || pg_temp.ck('an SOS whose details are exactly 2000 bytes is accepted', s = 'ok', s);

    s := pg_temp.x(format('insert into public.alerts (patient_id, alert_type, severity, details) values (%L, %L, %L, jsonb_build_object(%L, repeat(%L, %s)))', pn, 'sos', 'critical', 'x', 'a', n + 1), pn);
    n2 := (select count(*)::int from public.alerts where patient_id = pn);
    r := r || pg_temp.ck('one byte more (2001) is refused with details_too_large and not stored', s like 'ERR P0001 details_too_large' and n2 = 0, s || ' rows=' || n2);

    big := (select string_agg(md5(g::text), '') from generate_series(1, 30000) g);   -- about 960 KB of random-looking text
    s := pg_temp.x(format('insert into public.alerts (patient_id, alert_type, severity, details) values (%L, %L, %L, jsonb_build_object(%L, %L))', pn, 'sos', 'critical', 'x', big), pn);
    n2 := (select count(*)::int from public.alerts where patient_id = pn);
    r := r || pg_temp.ck('a SOS with about 960 KB of details is refused and not stored', s like 'ERR P0001 details_too_large' and n2 = 0, left(s, 80) || ' rows=' || n2);

    s := pg_temp.x(format('insert into public.alerts (patient_id, alert_type, severity) values (%L, %L, %L)', pn, 'sos', 'critical'), pn);
    s2 := pg_temp.x(format('insert into public.alerts (patient_id, alert_type, severity) values (%L, %L, %L)', pn, 'sos', 'critical'), pn);
    r := r || pg_temp.ck('the SOS rate limit still holds (a second SOS within 5 minutes is refused)', s = 'ok' and s2 like 'ERR P0001 sos_rate_limited', s || ' / ' || s2);

    s := pg_temp.x(format('insert into public.alerts (patient_id, alert_type, severity, details) values (%L, %L, %L, jsonb_build_object(%L, repeat(%L, 3000)))', pi, 'fever', 'warning', 'x', 'a'), p1);
    r := r || pg_temp.ck('an assigned provider adding an alert with 3000 bytes of details is refused', s like 'ERR P0001 details_too_large', s);
    s := pg_temp.x(format('insert into public.alerts (patient_id, alert_type, severity, details) values (%L, %L, %L, jsonb_build_object(%L, %s))', pi, 'fever', 'warning', 'value', 38.5), p1);
    r := r || pg_temp.ck('...but a normal provider alert (small details) is accepted', s = 'ok', s);

    s := pg_temp.x(format('insert into public.audit_log (actor_id, patient_id, action, details) values (%L, %L, %L, jsonb_build_object(%L, repeat(%L, 3000)))', p1, pi, 'patient_record_opened', 'x', 'a'), p1);
    r := r || pg_temp.ck('a provider audit_log entry with 3000 bytes of details is refused', s like 'ERR P0001 details_too_large', s);
    s := pg_temp.x(format('insert into public.audit_log (actor_id, patient_id, action) values (%L, %L, %L)', p1, pi, 'patient_record_opened'), p1);
    r := r || pg_temp.ck('...a normal audit_log entry (no details) is accepted, as the app writes it', s = 'ok', s);

    insert into public.alerts (patient_id, alert_type, severity, details) values (pi, 'signal_loss', 'warning', jsonb_build_object('x', repeat('a', 3000)));
    insert into public.audit_log (actor_id, action, details) values (p1, 'test_big_owner_row', jsonb_build_object('x', repeat('a', 3000)));
    r := r || pg_temp.ck('the database owner is not limited by the size cap (alerts and audit_log)',
      exists (select 1 from public.alerts where patient_id = pi and octet_length(details::text) > 2000)
      and exists (select 1 from public.audit_log where action = 'test_big_owner_row'));

    -- Abort the block so every fake row above is rolled back. The report in r is kept.
    raise exception 'nl_rollback' using errcode = 'NL999';
  exception
    when sqlstate 'NL999' then
      null;
  end;

  r := r || ('INFO|all numbers tested here (600 readings an hour, 5 devices, 100 characters, 2000 bytes) are draft defaults chosen by the project owner on 2026-11-02|')::text;
  r := r || ('INFO|two requests at the very same moment are not provable in one session; the caps take a per-patient advisory lock, the same method as the SOS limit|')::text;
  r := r || ('INFO|limits in front of the database (request body size) are not visible from SQL|')::text;
  r := r || ('INFO|a patient whose app was offline for over an hour and then sends more than 600 readings in that hour gets too_many_readings: Phase 5 must send backlogs in batches or the cap must be revisited|')::text;

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')::text
    into pass_n, fail_n from unnest(r) e;
  return array['SUMMARY|' || pass_n || ' PASS, ' || fail_n || ' FAIL|' ||
               case when fail_n = '0' then 'step 3.6 hardening holds' else 'send me every FAIL row' end] || r;
end
$fn$;

-- ---------------------------------------------------------------------
-- The report: SUMMARY first, then FAIL, then INFO, then PASS
-- ---------------------------------------------------------------------
select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_014_tests()) with ordinality as x(e, o)
order by 1;
