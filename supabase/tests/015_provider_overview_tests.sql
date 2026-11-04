-- =====================================================================
-- 015_provider_overview_tests.sql
-- NurtureLink step 4.1: proves that migration 015 (provider_overview() and
-- status_fresh_hours()) does what it says, shows only a provider's own assigned
-- patients, and agrees with the patient Home status (my_home_status(), 009).
--
--   * As built: both functions exist with the intended rights (helper is SECURITY
--     DEFINER, overview is SECURITY INVOKER, both with a fixed search_path, anon and
--     PUBLIC cannot run them, signed-in users can); exactly 16 client functions;
--     the overview returns exactly the nine intended columns (no date of birth, no
--     email, no details, no readings).
--   * Who sees what (fake providers and patients): provider 1 sees only its patients
--     1 to 5; provider 2 sees only 6 to 9; patient 10 (no provider) appears for
--     nobody, and its open alerts and SOS stay invisible to every provider; a provider
--     with no patients gets no rows; an admin gets no rows; a patient (also one who
--     was wrongly entered as somebody's "provider") gets no rows and sees nothing of
--     anybody else; anon is refused.
--   * Content: label code, display name (trimmed, blank = none), status for each rule,
--     open alert count (acknowledged alerts do not count), SOS flag and time (SOS
--     appears for patient 8 under provider 2 only), last check time, sort order.
--   * Missed check (DRAFT rule): exactly N hours old is not missed, N hours and one
--     second is missed, no readings is missed, a signal-lost check, a typed check and a
--     simulator check all count as a check, vitals alone do not, an open alert does not
--     hide the flag.
--   * Agreement with Home: the same status and the same "recent" answer as
--     my_home_status() for every fixture patient, and (when the demo accounts exist)
--     for demo patients 01 to 09; changing status_fresh_hours moves both functions
--     together; the helper and my_home_status() clamp bad settings the same way.
--   * Demo accounts (only if they exist): provider01 sees only patients 01 to 05,
--     provider02 only 06 to 09, patient10 neither; if patient08 has an open SOS it
--     shows under provider02 only.
--
-- LIMITS AND DRAFTS TESTED: the freshness window (14 hours), the status limits and the
-- sort order are DRAFT defaults pending the medical officer. To make the test
-- repeatable it sets the window to 14 and the four alert limits to the documented
-- defaults INSIDE the block that is rolled back, so your real settings are not changed.
--
-- HOW IT WORKS: like 014_phase3_review_tests.sql. Clearly fake users (emails end in
-- ".invalid") are created inside ONE block that is deliberately aborted at its end, so
-- everything is rolled back (the report survives). Each test switches to the role
-- "authenticated" or "anon" with a fake user's id in request.jwt.claims, like a real
-- API request. Real data is read only (the demo section only calls functions).
--
-- NOT PROVEN BY THIS FILE:
--   - Realtime delivery (who receives an alert event, how fast): a SQL file cannot
--     prove it. What it does prove is the row rule (alerts_select) Realtime applies to
--     every event: a provider can read only alerts of assigned patients, a patient
--     with no provider reaches no provider. Delivery needs the live two-device check.
--   - the audit row the app writes when the Overview opens (written by the app).
--   - the screens, and two requests at the very same moment.
--
-- HOW TO RUN: run 015_provider_overview.sql first. Paste this WHOLE file into a new SQL
-- Editor tab and click Run (if asked about "destructive operations", click Run: it only
-- creates temporary functions; the fake data is rolled back). Result: one table, SUMMARY
-- first, then FAIL, INFO, PASS.
-- WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and every FAIL row (or the error
-- text if the whole file stops with an error).
--
-- DEPENDS ON: 000 to 015. READ-ONLY for your real data.
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

-- Run a query that returns ONE jsonb value as a role and fake user.
-- On any error it returns {"error": "<sqlstate> <message>"}.
create or replace function pg_temp.j(p_sql text, p_uid uuid default null, p_role text default 'authenticated')
returns jsonb
language plpgsql
as $fn$
declare
  v jsonb;
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
    return jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
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

-- provider_overview() as the given user: a jsonb array, one object per row, in the
-- order the function returned them (the key "ordinality" is the position).
create or replace function pg_temp.ov(p_uid uuid, p_role text default 'authenticated')
returns jsonb
language sql
as $fn$
  select pg_temp.j(
    'select coalesce(jsonb_agg(to_jsonb(o) order by o.ordinality), ''[]''::jsonb) from public.provider_overview() with ordinality as o',
    p_uid, p_role)
$fn$;

-- The object for one patient in an overview result (null if absent).
create or replace function pg_temp.row_of(p_ov jsonb, p_pid uuid)
returns jsonb
language sql
as $fn$
  select e
  from jsonb_array_elements(case when jsonb_typeof(p_ov) = 'array' then p_ov else '[]'::jsonb end) e
  where e ->> 'patient_id' = p_pid::text
  limit 1
$fn$;

-- The patient ids in an overview result, sorted, comma separated ('' for none).
create or replace function pg_temp.ids(p_ov jsonb)
returns text
language sql
as $fn$
  select coalesce(string_agg(e ->> 'patient_id', ',' order by e ->> 'patient_id'), '')
  from jsonb_array_elements(case when jsonb_typeof(p_ov) = 'array' then p_ov else '[]'::jsonb end) e
$fn$;

-- The patient ids in the order the function returned them.
create or replace function pg_temp.order_of(p_ov jsonb)
returns text
language sql
as $fn$
  select coalesce(string_agg(e ->> 'patient_id', ',' order by (e ->> 'ordinality')::integer), '')
  from jsonb_array_elements(case when jsonb_typeof(p_ov) = 'array' then p_ov else '[]'::jsonb end) e
$fn$;

-- A list of ids sorted the same way as ids().
create or replace function pg_temp.sorted(p_ids uuid[])
returns text
language sql
as $fn$
  select coalesce(string_agg(u::text, ',' order by u::text), '') from unnest(p_ids) u
$fn$;

-- True if the overview result is a real array (not an error object).
create or replace function pg_temp.is_list(p_ov jsonb)
returns boolean
language sql
as $fn$
  select jsonb_typeof(p_ov) = 'array'
$fn$;

-- True if the overview result is an array with no rows (an error object is NOT empty).
create or replace function pg_temp.is_empty(p_ov jsonb)
returns boolean
language sql
as $fn$
  select case when jsonb_typeof(p_ov) = 'array' then jsonb_array_length(p_ov) = 0 else false end
$fn$;

-- One belt reading by the database owner.
create or replace function pg_temp.belt(p_patient uuid, p_age interval, p_fhr integer default 140,
                                       p_lost boolean default false, p_source text default 'device')
returns void
language sql
as $fn$
  insert into public.belt_readings (patient_id, fetal_hr_bpm, signal_lost, source, measured_at)
  values (p_patient, case when p_lost then null else p_fhr end, p_lost, p_source, now() - p_age)
$fn$;

-- ---------------------------------------------------------------------
-- The tests
-- ---------------------------------------------------------------------
create or replace function pg_temp.nl_015_tests()
returns text[]
language plpgsql
as $fn$
declare
  r  text[] := '{}';
  -- patients 1 to 10 (1 to 5 -> provider 1, 6 to 9 -> provider 2, 10 -> nobody)
  q1 uuid := gen_random_uuid();
  q2 uuid := gen_random_uuid();
  q3 uuid := gen_random_uuid();
  q4 uuid := gen_random_uuid();
  q5 uuid := gen_random_uuid();
  q6 uuid := gen_random_uuid();
  q7 uuid := gen_random_uuid();
  q8 uuid := gen_random_uuid();
  q9 uuid := gen_random_uuid();
  q10 uuid := gen_random_uuid();
  m1 uuid := gen_random_uuid();   -- patient entered as "assigned_provider" = q1 (a patient account)
  -- patients for provider 4: the missed-check edges and the vitals rules
  b1 uuid := gen_random_uuid();   -- belt exactly N hours old
  b2 uuid := gen_random_uuid();   -- belt N hours and 1 second old
  b3 uuid := gen_random_uuid();   -- belt N hours minus 1 second old
  b4 uuid := gen_random_uuid();   -- only a typed (manual) check, 1 hour ago
  b5 uuid := gen_random_uuid();   -- only a simulator check, 1 hour ago
  b6 uuid := gen_random_uuid();   -- recent vitals but no belt check at all
  d1 uuid := gen_random_uuid();   -- belt 13 hours old (the window-change test)
  e1 uuid := gen_random_uuid();   -- recent belt, recent low SpO2
  f1 uuid := gen_random_uuid();   -- recent belt, recent fever
  g1 uuid := gen_random_uuid();   -- recent belt, low SpO2 but 20 hours old (outside the window)
  p1 uuid := gen_random_uuid();   -- provider 1
  p2 uuid := gen_random_uuid();   -- provider 2
  p3 uuid := gen_random_uuid();   -- provider with no patients
  p4 uuid := gen_random_uuid();   -- provider 4
  ad uuid := gen_random_uuid();   -- admin account
  ov1 jsonb;
  ov2 jsonb;
  ov3 jsonb;
  ov4 jsonb;
  ova jsonb;
  ovq jsonb;
  w   jsonb;
  hs  jsonb;
  rw  jsonb;
  pid uuid;
  n   integer;
  v_n integer;
  bad text;
  cnt integer;
  want integer;
  fid oid;
  tmp uuid;
  val text;
  d_p1 uuid;
  d_p2 uuid;
  d_pat uuid[] := array_fill(null::uuid, array[10]);
  dov1 jsonb;
  dov2 jsonb;
  i integer;
  pass_n integer;
  fail_n text;
begin
  begin   -- everything in this block is rolled back at the end

    ---------------------------------------------------------------
    -- Fake users and rows (created as the database owner)
    ---------------------------------------------------------------
    insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
    select u, 'nl-015-' || u || '@nurturelink-test.invalid', now(), '{}'::jsonb
    from unnest(array[q1, q2, q3, q4, q5, q6, q7, q8, q9, q10, m1, b1, b2, b3, b4, b5, b6, d1, e1, f1, g1,
                      p1, p2, p3, p4, ad]) u;
    update public.profiles set role = 'provider' where id in (p1, p2, p3, p4);
    update public.profiles set role = 'admin' where id = ad;

    insert into public.pregnancy_profiles (patient_id, assigned_provider_id) values
      (q1, p1), (q2, p1), (q3, p1), (q4, p1), (q5, p1),
      (q6, p2), (q7, p2), (q8, p2), (q9, p2),
      (q10, null),
      (m1, q1),
      (b1, p4), (b2, p4), (b3, p4), (b4, p4), (b5, p4), (b6, p4), (d1, p4), (e1, p4), (f1, p4), (g1, p4);

    -- Known settings for a repeatable test (rolled back with everything else).
    update public.app_settings set value = '14' where key = 'status_fresh_hours';
    update public.alert_thresholds set min_value = 110, max_value = 160, sustained_count = 3, enabled = true where alert_type = 'fhr_out_of_range';
    update public.alert_thresholds set min_value = 95, sustained_count = 2, enabled = true where alert_type = 'low_spo2';
    update public.alert_thresholds set max_value = 37.9, sustained_count = 2, enabled = true where alert_type = 'fever';
    update public.alert_thresholds set sustained_count = 3, enabled = true where alert_type = 'signal_loss';

    -- Display names: q2 has a name with spaces around it, q9 a blank one, the rest none.
    update public.profiles set display_name = '  Fixture Name Two  ' where id = q2;
    update public.profiles set display_name = '   ' where id = q9;

    v_n := public.status_fresh_hours();

    -- Provider 1's patients
    perform pg_temp.belt(q1, interval '1 hour');                                  -- ok
    perform pg_temp.belt(q2, interval '1 hour');                                  -- attention: open warning alert
    insert into public.alerts (patient_id, alert_type, severity) values (q2, 'fever', 'warning');
    -- q3: no readings, no alerts                                                 -- no_recent_data, never checked
    perform pg_temp.belt(q4, interval '30 hours');                                -- stale, but an open critical alert
    insert into public.alerts (patient_id, alert_type, severity) values (q4, 'fhr_out_of_range', 'critical');
    perform pg_temp.belt(q5, interval '1 hour', 220);                             -- attention: heart rate outside the limits (one reading: no alert yet)

    -- Provider 2's patients
    perform pg_temp.belt(q6, interval '3 hours');                                 -- urgent: open critical alert (not an SOS)
    insert into public.alerts (patient_id, alert_type, severity) values (q6, 'fhr_out_of_range', 'critical');
    perform pg_temp.belt(q7, interval '1 hour', null, true);                      -- attention: signal lost (one: no alert yet)
    perform pg_temp.belt(q8, interval '5 hours');                                 -- urgent: SOS open (plus a warning alert)
    insert into public.alerts (patient_id, alert_type, severity) values (q8, 'sos', 'critical'), (q8, 'signal_loss', 'warning');
    perform pg_temp.belt(q9, interval '2 hours');                                 -- ok: only an acknowledged alert
    insert into public.alerts (patient_id, alert_type, severity, status, acknowledged_by, acknowledged_at)
      values (q9, 'fever', 'warning', 'acknowledged', p2, now());

    -- Patient 10: no provider, open critical alert and an SOS: must reach nobody
    insert into public.alerts (patient_id, alert_type, severity) values (q10, 'fhr_out_of_range', 'critical'), (q10, 'sos', 'critical');
    perform pg_temp.belt(q10, interval '1 hour');

    -- m1: assigned to a PATIENT account (q1), which must never make q1 a provider
    perform pg_temp.belt(m1, interval '1 hour');

    -- Provider 4's patients: edges of the missed-check rule and the vitals rules
    perform pg_temp.belt(b1, make_interval(hours => v_n));                        -- exactly N hours
    perform pg_temp.belt(b2, make_interval(hours => v_n) + interval '1 second');  -- N hours and 1 second
    perform pg_temp.belt(b3, make_interval(hours => v_n) - interval '1 second');  -- N hours minus 1 second
    perform pg_temp.belt(b4, interval '1 hour', 140, false, 'manual');
    perform pg_temp.belt(b5, interval '1 hour', 140, false, 'simulator');
    insert into public.maternal_vitals (patient_id, heart_rate_bpm, source, measured_at) values (b6, 80, 'device', now() - interval '1 hour');
    perform pg_temp.belt(d1, interval '13 hours');
    perform pg_temp.belt(e1, interval '1 hour');
    insert into public.maternal_vitals (patient_id, spo2_percent, source, measured_at) values (e1, 90, 'device', now() - interval '30 minutes');
    perform pg_temp.belt(f1, interval '1 hour');
    insert into public.maternal_vitals (patient_id, temperature_c, source, measured_at) values (f1, 38.5, 'device', now() - interval '30 minutes');
    perform pg_temp.belt(g1, interval '1 hour');
    insert into public.maternal_vitals (patient_id, spo2_percent, source, measured_at) values (g1, 90, 'device', now() - interval '20 hours');

    ov1 := pg_temp.ov(p1);
    ov2 := pg_temp.ov(p2);
    ov3 := pg_temp.ov(p3);
    ov4 := pg_temp.ov(p4);
    ova := pg_temp.ov(ad);

    ---------------------------------------------------------------
    -- 0. The migration as built
    ---------------------------------------------------------------
    fid := to_regprocedure('public.status_fresh_hours()');
    r := r || pg_temp.ck('public.status_fresh_hours() exists, is SECURITY DEFINER with a fixed search_path and no arguments; anon and PUBLIC cannot run it, signed-in users can',
      fid is not null
      and exists (select 1 from pg_proc p where p.oid = fid and p.prosecdef and p.pronargs = 0
                  and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%'))
      and not has_function_privilege('anon', fid, 'EXECUTE')
      and not has_function_privilege('public', fid, 'EXECUTE')
      and has_function_privilege('authenticated', fid, 'EXECUTE'));

    fid := to_regprocedure('public.provider_overview()');
    r := r || pg_temp.ck('public.provider_overview() exists, is SECURITY INVOKER with a fixed search_path and no arguments; anon and PUBLIC cannot run it, signed-in users can',
      fid is not null
      and exists (select 1 from pg_proc p where p.oid = fid and not p.prosecdef and p.pronargs = 0
                  and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%'))
      and not has_function_privilege('anon', fid, 'EXECUTE')
      and not has_function_privilege('public', fid, 'EXECUTE')
      and has_function_privilege('authenticated', fid, 'EXECUTE'));

    val := (select string_agg(u.n, ',' order by u.ord)
            from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as u(n, m, ord)
            where p.oid = fid and u.m = 't');
    r := r || pg_temp.ck('provider_overview() returns exactly the nine intended columns (no date of birth, no email, no details, no reading values)',
      val = 'patient_id,label_code,display_name,status,last_check_at,open_alert_count,sos_open,sos_since,missed_check', val);

    r := r || pg_temp.ck('signed-in users can execute exactly 16 functions in public (the 14 from step 3.6 plus provider_overview and status_fresh_hours)',
      (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname <> 'rls_auto_enable'
          and has_function_privilege('authenticated', p.oid, 'EXECUTE')) = 16);

    r := r || pg_temp.ck('anon cannot call provider_overview() or status_fresh_hours() (permission denied)',
      pg_temp.x('select * from public.provider_overview()', null, 'anon') like 'ERR 42501 permission denied for function%'
      and pg_temp.x('select public.status_fresh_hours()', null, 'anon') like 'ERR 42501 permission denied for function%',
      pg_temp.x('select * from public.provider_overview()', null, 'anon'));

    r := r || pg_temp.ck('the setting row status_fresh_hours exists (run 009 first) and the helper answers 14 for a signed-in user',
      exists (select 1 from public.app_settings where key = 'status_fresh_hours')
      and pg_temp.j('select to_jsonb(public.status_fresh_hours())', q1) = to_jsonb(14));

    ---------------------------------------------------------------
    -- 1. Who sees which patients
    ---------------------------------------------------------------
    r := r || pg_temp.ck('provider 1 sees exactly patients 1 to 5',
      pg_temp.ids(ov1) = pg_temp.sorted(array[q1, q2, q3, q4, q5]), left(ov1::text, 300));
    r := r || pg_temp.ck('provider 2 sees exactly patients 6 to 9',
      pg_temp.ids(ov2) = pg_temp.sorted(array[q6, q7, q8, q9]), left(ov2::text, 300));
    r := r || pg_temp.ck('provider 4 sees exactly its own 10 patients (b1 to b6, d1, e1, f1, g1)',
      pg_temp.ids(ov4) = pg_temp.sorted(array[b1, b2, b3, b4, b5, b6, d1, e1, f1, g1]), left(ov4::text, 300));
    r := r || pg_temp.ck('patient 10 (no provider) appears for no provider',
      pg_temp.row_of(ov1, q10) is null and pg_temp.row_of(ov2, q10) is null
      and pg_temp.row_of(ov3, q10) is null and pg_temp.row_of(ov4, q10) is null);
    r := r || pg_temp.ck('provider 1 never sees provider 2''s patients and the other way round',
      pg_temp.row_of(ov1, q6) is null and pg_temp.row_of(ov1, q8) is null
      and pg_temp.row_of(ov2, q1) is null and pg_temp.row_of(ov2, q4) is null);
    r := r || pg_temp.ck('a provider with no assigned patients gets an empty list (not an error)',
      pg_temp.is_empty(ov3), ov3::text);
    r := r || pg_temp.ck('an admin account gets an empty list',
      pg_temp.is_empty(ova), ova::text);

    for pid in select unnest(array[q1, q6, q10, b1]) loop
      ovq := pg_temp.ov(pid);
      r := r || pg_temp.ck('a patient calling provider_overview() gets no rows (patient ' || left(pid::text, 6) || ')',
        pg_temp.is_empty(ovq), left(ovq::text, 200));
    end loop;

    ovq := pg_temp.ov(q1);
    r := r || pg_temp.ck('a patient cannot see another patient''s status through it (patient 1 gets nothing about patients 2, 6, 8 or 10)',
      pg_temp.row_of(ovq, q2) is null and pg_temp.row_of(ovq, q6) is null
      and pg_temp.row_of(ovq, q8) is null and pg_temp.row_of(ovq, q10) is null);

    ovq := pg_temp.ov(m1);
    r := r || pg_temp.ck('a patient entered as someone''s "provider" by mistake (patient 1 is the assigned_provider_id of m1) still gets no rows: the role check holds',
      pg_temp.is_empty(pg_temp.ov(q1)) and pg_temp.is_empty(ovq),
      left(pg_temp.ov(q1)::text, 200));

    r := r || pg_temp.ck('alerts of patient 10 (open critical alert and SOS) are invisible to every provider, also by a direct read',
      pg_temp.j('select to_jsonb(count(*)) from public.alerts where patient_id = ' || quote_literal(q10), p1) = to_jsonb(0)
      and pg_temp.j('select to_jsonb(count(*)) from public.alerts where patient_id = ' || quote_literal(q10), p2) = to_jsonb(0)
      and pg_temp.j('select to_jsonb(count(*)) from public.alerts where patient_id = ' || quote_literal(q10), p3) = to_jsonb(0)
      and pg_temp.j('select to_jsonb(count(*)) from public.alerts where patient_id = ' || quote_literal(q10), p4) = to_jsonb(0));

    r := r || pg_temp.ck('what the Realtime row rule allows matches: provider 1 can read alerts of patient 4 but not of patient 8; provider 2 the opposite',
      pg_temp.j('select to_jsonb(count(*)) from public.alerts where patient_id = ' || quote_literal(q4), p1) = to_jsonb(1)
      and pg_temp.j('select to_jsonb(count(*)) from public.alerts where patient_id = ' || quote_literal(q8), p1) = to_jsonb(0)
      and pg_temp.j('select to_jsonb(count(*)) from public.alerts where patient_id = ' || quote_literal(q8), p2) = to_jsonb(2)
      and pg_temp.j('select to_jsonb(count(*)) from public.alerts where patient_id = ' || quote_literal(q4), p2) = to_jsonb(0));

    ---------------------------------------------------------------
    -- 2. What each row contains
    ---------------------------------------------------------------
    rw := pg_temp.row_of(ov1, q1);
    r := r || pg_temp.ck('label_code is the first 6 characters of the id in upper case',
      rw ->> 'label_code' = upper(left(q1::text, 6)) and (rw ->> 'label_code') ~ '^[0-9A-F]{6}$', rw::text);
    r := r || pg_temp.ck('a row holds only the nine columns plus the position (no date of birth, email or details keys)',
      (select string_agg(k, ',' order by k) from jsonb_object_keys(rw) k)
        = 'display_name,label_code,last_check_at,missed_check,open_alert_count,ordinality,patient_id,sos_open,sos_since,status', rw::text);
    r := r || pg_temp.ck('patient 1: stable, check present, no alerts, not missed, no name',
      rw ->> 'status' = 'ok' and (rw ->> 'missed_check')::boolean = false and (rw ->> 'open_alert_count')::integer = 0
      and (rw ->> 'sos_open')::boolean = false and rw ->> 'sos_since' is null
      and rw ->> 'last_check_at' is not null and rw ->> 'display_name' is null, rw::text);

    rw := pg_temp.row_of(ov1, q2);
    r := r || pg_temp.ck('a display name is trimmed (spaces around it removed)', rw ->> 'display_name' = 'Fixture Name Two', rw::text);
    r := r || pg_temp.ck('patient 2: open warning alert gives attention with 1 open alert, not an SOS',
      rw ->> 'status' = 'attention' and (rw ->> 'open_alert_count')::integer = 1 and (rw ->> 'sos_open')::boolean = false, rw::text);

    rw := pg_temp.row_of(ov1, q3);
    r := r || pg_temp.ck('patient 3: no readings at all is "no_recent_data" (never ok), missed, and last_check_at is empty ("No check yet")',
      rw ->> 'status' = 'no_recent_data' and (rw ->> 'missed_check')::boolean = true and rw ->> 'last_check_at' is null, rw::text);

    rw := pg_temp.row_of(ov1, q4);
    r := r || pg_temp.ck('patient 4: an open critical alert beats stale data (urgent), and the missed flag still shows',
      rw ->> 'status' = 'urgent' and (rw ->> 'missed_check')::boolean = true and (rw ->> 'open_alert_count')::integer = 1
      and (rw ->> 'sos_open')::boolean = false, rw::text);

    rw := pg_temp.row_of(ov1, q5);
    r := r || pg_temp.ck('patient 5: a recent heart rate outside the limits gives attention (the limits come from alert_thresholds)',
      rw ->> 'status' = 'attention' and (rw ->> 'missed_check')::boolean = false and (rw ->> 'open_alert_count')::integer = 0, rw::text);

    rw := pg_temp.row_of(ov2, q6);
    r := r || pg_temp.ck('patient 6: urgent from an open critical alert that is not an SOS',
      rw ->> 'status' = 'urgent' and (rw ->> 'sos_open')::boolean = false, rw::text);

    rw := pg_temp.row_of(ov2, q7);
    r := r || pg_temp.ck('patient 7: a recent signal-lost check gives attention, and it counts as a check (not missed)',
      rw ->> 'status' = 'attention' and (rw ->> 'missed_check')::boolean = false, rw::text);

    rw := pg_temp.row_of(ov2, q8);
    r := r || pg_temp.ck('patient 8: SOS is open under provider 2, with the SOS time, urgent, and 2 open alerts counted (SOS included)',
      (rw ->> 'sos_open')::boolean = true and rw ->> 'sos_since' is not null and rw ->> 'status' = 'urgent'
      and (rw ->> 'open_alert_count')::integer = 2, rw::text);
    r := r || pg_temp.ck('patient 8''s SOS appears under provider 2 only (provider 1, 3, 4 and the admin have no row for patient 8)',
      pg_temp.row_of(ov1, q8) is null and pg_temp.row_of(ov3, q8) is null and pg_temp.row_of(ov4, q8) is null and pg_temp.row_of(ova, q8) is null);
    r := r || pg_temp.ck('only patient 8 has an SOS among the fixture patients visible to providers',
      not exists (select 1 from jsonb_array_elements(ov1 || ov2 || ov4) e where (e ->> 'sos_open')::boolean and e ->> 'patient_id' <> q8::text));

    rw := pg_temp.row_of(ov2, q9);
    r := r || pg_temp.ck('patient 9: an acknowledged alert does not count (stable, 0 open alerts); a blank display name is treated as no name',
      rw ->> 'status' = 'ok' and (rw ->> 'open_alert_count')::integer = 0 and rw ->> 'display_name' is null, rw::text);

    r := r || pg_temp.ck('the list is sorted by priority for provider 1: urgent, then attention (more open alerts first), then no recent data, then stable',
      pg_temp.order_of(ov1) = array_to_string(array[q4, q2, q5, q3, q1], ','), pg_temp.order_of(ov1));
    r := r || pg_temp.ck('the list is sorted for provider 2: the open SOS first, then urgent, then attention, then stable',
      pg_temp.order_of(ov2) = array_to_string(array[q8, q6, q7, q9], ','), pg_temp.order_of(ov2));

    rw := pg_temp.row_of(ov4, e1);
    r := r || pg_temp.ck('a recent low SpO2 gives attention', rw ->> 'status' = 'attention', rw::text);
    rw := pg_temp.row_of(ov4, f1);
    r := r || pg_temp.ck('a recent fever gives attention', rw ->> 'status' = 'attention', rw::text);
    rw := pg_temp.row_of(ov4, g1);
    r := r || pg_temp.ck('a low SpO2 older than the window is ignored (stable), exactly as in my_home_status()', rw ->> 'status' = 'ok', rw::text);

    ---------------------------------------------------------------
    -- 3. Missed check: the edges of the DRAFT rule (window N = status_fresh_hours)
    ---------------------------------------------------------------
    rw := pg_temp.row_of(ov4, b1);
    r := r || pg_temp.ck('a check exactly N hours old is NOT missed (inclusive edge) and the status is stable',
      (rw ->> 'missed_check')::boolean = false and rw ->> 'status' = 'ok', 'N=' || v_n || ' ' || rw::text);
    rw := pg_temp.row_of(ov4, b2);
    r := r || pg_temp.ck('a check N hours and 1 second old IS missed and the status is "no_recent_data"',
      (rw ->> 'missed_check')::boolean = true and rw ->> 'status' = 'no_recent_data', rw::text);
    rw := pg_temp.row_of(ov4, b3);
    r := r || pg_temp.ck('a check N hours minus 1 second old is not missed',
      (rw ->> 'missed_check')::boolean = false, rw::text);
    r := r || pg_temp.ck('a typed (manual) check counts as a check',
      (pg_temp.row_of(ov4, b4) ->> 'missed_check')::boolean = false, pg_temp.row_of(ov4, b4)::text);
    r := r || pg_temp.ck('a simulator check counts as a check',
      (pg_temp.row_of(ov4, b5) ->> 'missed_check')::boolean = false, pg_temp.row_of(ov4, b5)::text);
    rw := pg_temp.row_of(ov4, b6);
    r := r || pg_temp.ck('recent vitals without any belt check do not count: missed, no check yet, "no_recent_data"',
      (rw ->> 'missed_check')::boolean = true and rw ->> 'last_check_at' is null and rw ->> 'status' = 'no_recent_data', rw::text);
    r := r || pg_temp.ck('the missed flag is judged by when the check was MEASURED, not when it was saved (patient 4: saved just now, measured 30 hours ago)',
      (pg_temp.row_of(ov1, q4) ->> 'missed_check')::boolean = true);

    ---------------------------------------------------------------
    -- 4. Agreement with the patient Home status (my_home_status, 009)
    ---------------------------------------------------------------
    bad := '';
    cnt := 0;
    for pid in select unnest(array[q1, q2, q3, q4, q5, q6, q7, q8, q9, b1, b2, b3, b4, b5, b6, d1, e1, f1, g1]) loop
      hs := pg_temp.j('select public.my_home_status()', pid);
      rw := coalesce(pg_temp.row_of(ov1, pid), pg_temp.row_of(ov2, pid), pg_temp.row_of(ov4, pid));
      cnt := cnt + 1;
      if hs ->> 'status' is distinct from rw ->> 'status'
         or (hs ->> 'fresh_belt')::boolean is distinct from not (rw ->> 'missed_check')::boolean then
        bad := bad || left(pid::text, 6) || ' home=' || coalesce(hs ->> 'status', 'null') || '/' || coalesce(hs ->> 'fresh_belt', 'null')
               || ' overview=' || coalesce(rw ->> 'status', 'null') || '/' || coalesce(rw ->> 'missed_check', 'null') || '; ';
      end if;
    end loop;
    r := r || pg_temp.ck('provider_overview() and my_home_status() give the same status and the same "recent check" answer for all ' || cnt || ' fixture patients',
      bad = '' and cnt = 19, bad);

    -- Both functions move together when the setting changes (inside the rolled-back block).
    update public.app_settings set value = '12' where key = 'status_fresh_hours';
    ov4 := pg_temp.ov(p4);
    hs := pg_temp.j('select public.my_home_status()', d1);
    rw := pg_temp.row_of(ov4, d1);
    r := r || pg_temp.ck('with the window set to 12 hours, a check 13 hours old is missed and "no_recent_data" in BOTH functions, and my_home_status reports 12',
      pg_temp.j('select to_jsonb(public.status_fresh_hours())', q1) = to_jsonb(12)
      and (hs ->> 'fresh_hours')::integer = 12 and hs ->> 'status' = 'no_recent_data'
      and rw ->> 'status' = 'no_recent_data' and (rw ->> 'missed_check')::boolean = true,
      hs::text || ' / ' || coalesce(rw::text, 'null'));
    update public.app_settings set value = '14' where key = 'status_fresh_hours';
    ov4 := pg_temp.ov(p4);
    hs := pg_temp.j('select public.my_home_status()', d1);
    rw := pg_temp.row_of(ov4, d1);
    r := r || pg_temp.ck('with the window back at 14 hours, the same check is recent and stable in BOTH functions',
      (hs ->> 'fresh_hours')::integer = 14 and hs ->> 'status' = 'ok'
      and rw ->> 'status' = 'ok' and (rw ->> 'missed_check')::boolean = false,
      hs::text || ' / ' || coalesce(rw::text, 'null'));

    -- Bad settings are clamped the same way in the helper and in my_home_status().
    bad := '';
    for val in select unnest(array['0', '169', 'abc', '1000', '', ' 7', '1.5', '-3', '5', '168', '1']) loop
      update public.app_settings set value = val where key = 'status_fresh_hours';
      w := pg_temp.j('select to_jsonb(public.status_fresh_hours())', q1);
      n := case when jsonb_typeof(w) = 'number' then (w #>> '{}')::integer end;
      hs := pg_temp.j('select public.my_home_status()', q1);
      -- The expected value is worked out BEFORE the IF: PL/pgSQL ends an IF condition at the
      -- first THEN it sees, so a CASE ... THEN inside the condition cannot be used.
      want := case when val in ('5', '168', '1') then val::integer else 14 end;
      if n is distinct from (hs ->> 'fresh_hours')::integer or n is distinct from want then
        bad := bad || '[' || val || '] helper=' || coalesce(n::text, 'null') || ' home=' || coalesce(hs ->> 'fresh_hours', 'null') || '; ';
      end if;
    end loop;
    r := r || pg_temp.ck('bad or odd setting values (0, 169, abc, 1000, blank, " 7", 1.5, -3) fall back to 14 and 1, 5 and 168 are used, identically in status_fresh_hours() and my_home_status()',
      bad = '', bad);

    delete from public.app_settings where key = 'status_fresh_hours';
    r := r || pg_temp.ck('with the setting row missing, both functions use 14',
      pg_temp.j('select to_jsonb(public.status_fresh_hours())', q1) = to_jsonb(14)
      and (pg_temp.j('select public.my_home_status()', q1) ->> 'fresh_hours')::integer = 14);
    insert into public.app_settings (key, value, description)
      values ('status_fresh_hours', '14', 'restored inside the test block');

    ---------------------------------------------------------------
    -- 5. Demo accounts (only if they all exist; read-only, functions only)
    ---------------------------------------------------------------
    select u.id into d_p1 from auth.users u where u.email = 'provider01@example.test';
    select u.id into d_p2 from auth.users u where u.email = 'provider02@example.test';
    for i in 1..10 loop
      tmp := null;
      select u.id into tmp from auth.users u where u.email = 'patient' || lpad(i::text, 2, '0') || '@example.test';
      d_pat[i] := tmp;
    end loop;

    if d_p1 is not null and d_p2 is not null and not exists (select 1 from unnest(d_pat) x where x is null) then
      dov1 := pg_temp.ov(d_p1);
      dov2 := pg_temp.ov(d_p2);
      r := r || pg_temp.ck('demo: provider01 sees only patients 01 to 05',
        pg_temp.ids(dov1) = pg_temp.sorted(d_pat[1:5]), left(dov1::text, 300));
      r := r || pg_temp.ck('demo: provider02 sees only patients 06 to 09',
        pg_temp.ids(dov2) = pg_temp.sorted(d_pat[6:9]), left(dov2::text, 300));
      r := r || pg_temp.ck('demo: patient10 appears for neither provider',
        pg_temp.row_of(dov1, d_pat[10]) is null and pg_temp.row_of(dov2, d_pat[10]) is null);

      select count(*)::integer into n from public.alerts where patient_id = d_pat[8] and alert_type = 'sos' and status = 'open';
      if n > 0 then
        r := r || pg_temp.ck('demo: patient08''s open SOS shows under provider02 and never under provider01',
          (pg_temp.row_of(dov2, d_pat[8]) ->> 'sos_open')::boolean = true and pg_temp.row_of(dov1, d_pat[8]) is null,
          coalesce(pg_temp.row_of(dov2, d_pat[8])::text, 'no row'));
      else
        r := r || ('INFO|demo: patient08 has no OPEN SOS right now (it was acknowledged or the seed was re-run), so the demo SOS check was skipped; the fixture SOS checks above still ran|')::text;
      end if;

      bad := '';
      cnt := 0;
      for i in 1..9 loop
        hs := pg_temp.j('select public.my_home_status()', d_pat[i]);
        rw := coalesce(pg_temp.row_of(dov1, d_pat[i]), pg_temp.row_of(dov2, d_pat[i]));
        cnt := cnt + 1;
        if hs ->> 'status' is distinct from rw ->> 'status'
           or (hs ->> 'fresh_belt')::boolean is distinct from not (rw ->> 'missed_check')::boolean then
          bad := bad || 'patient' || lpad(i::text, 2, '0') || ' home=' || coalesce(hs ->> 'status', 'null')
                 || ' overview=' || coalesce(rw ->> 'status', 'null') || '; ';
        end if;
      end loop;
      r := r || pg_temp.ck('demo: provider_overview() and my_home_status() agree for demo patients 01 to 09 (' || cnt || ' compared)',
        bad = '' and cnt = 9, bad);
    else
      r := r || ('INFO|the demo accounts (provider01, provider02, patient01 to patient10 at example.test) were not all found, so the demo checks were skipped; the fixture checks above still ran|')::text;
    end if;

    -- Abort the block so every fake row and every setting change above is rolled back.
    -- The report in r is kept.
    raise exception 'nl_rollback' using errcode = 'NL999';
  exception
    when sqlstate 'NL999' then
      null;
  end;

  r := r || ('INFO|the freshness window (14 hours), the status limits, the missed-check rule and the sort order (position of "no recent data") are DRAFT defaults pending the medical officer; the missed-check rule is replaced by wear schedules in step 4.5|')::text;
  r := r || ('INFO|Realtime delivery cannot be proven in SQL: this file proves who may READ alerts (the row rule Realtime applies to every event); the live two-device check proves delivery|')::text;
  r := r || ('INFO|the overview_viewed audit row is written by the app and is a trace, not a guarantee: a modified client can skip it|')::text;
  r := r || ('INFO|one session only: two requests at the very same moment are not tested; the function only reads|')::text;

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')::text
    into pass_n, fail_n from unnest(r) e;
  return array['SUMMARY|' || pass_n || ' PASS, ' || fail_n || ' FAIL|' ||
               case when fail_n = '0' then 'step 4.1 provider overview holds' else 'send me every FAIL row' end] || r;
end
$fn$;

-- ---------------------------------------------------------------------
-- The report: SUMMARY first, then FAIL, then INFO, then PASS
-- ---------------------------------------------------------------------
select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_015_tests()) with ordinality as x(e, o)
order by 1;
