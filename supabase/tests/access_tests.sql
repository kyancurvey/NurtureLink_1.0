-- =====================================================================
-- access_tests.sql
-- NurtureLink: proves that the grants (004) and the row rules (005) do what
-- they should. Run in the Supabase SQL Editor AFTER 004 and 005.
--
-- WHAT IT DOES
--   Creates clearly fake users (a patient A, B, C, D; providers P1, P2; an admin),
--   fake data for them, and then, for each test, switches the session to the
--   role "anon" or "authenticated" with that fake user's id in
--   request.jwt.claims, exactly like a real API request, and tries things.
--   Every result is PASS or FAIL.
--
-- NOTHING IS SAVED. All fake users and data are created inside one block that
-- is deliberately aborted at its end, which rolls everything back (the same
-- effect as BEGIN ... ROLLBACK, but the report survives, because the editor
-- only shows the result of the last statement). Real data is never read or
-- changed, and the fake emails end in ".invalid".
--
-- HOW TO RUN: paste this WHOLE file into a new SQL Editor tab (nothing
-- highlighted) and click Run. If a pop-up warns about a "potential issue" or
-- "destructive operations", click Run this query: the file only creates
-- temporary functions, and the fake test data is rolled back.
-- The result is one table:
--     n | status  | test                        | detail
--   status SUMMARY is the first row ("x PASS, y FAIL"), then every FAIL, then
--   INFO lines, then all PASS rows.
--
-- WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and every FAIL row
-- (test and detail columns), as text or an export. Nothing else.
--
-- DEPENDS ON: 000 to 005 and 008 already run (the reading-time checks need 008).
-- READ-ONLY for your real data.
-- SAFE TO RE-RUN: yes, any number of times.
-- HOW TO UNDO: nothing to undo; the helper functions live only in this session.
--
-- NOTE ON WORDING: anon has no grants, so anon gets "permission denied".
-- A patient reading a provider-only table is NOT "permission denied" (the
-- same database role is used by providers); the rows are simply invisible,
-- so those tests expect 0 rows or a row-level-security error.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers (temporary: they disappear when the session ends)
-- ---------------------------------------------------------------------

-- Run one statement as a role and fake user. Returns 'ok' or 'ERR <sqlstate> <message>'.
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

-- Run one query that returns a single integer, as a role and fake user. -1 on any error.
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

-- Turn a condition into one report line.
create or replace function pg_temp.ck(p_name text, p_ok boolean, p_detail text default '')
returns text
language sql
as $fn$
  select case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end || '|' || p_name || '|' ||
         case when coalesce(p_ok, false) then '' else coalesce(p_detail, '') end
$fn$;

-- ---------------------------------------------------------------------
-- The tests
-- ---------------------------------------------------------------------
create or replace function pg_temp.nl_access_tests()
returns text[]
language plpgsql
as $fn$
declare
  r        text[] := '{}';
  a  uuid := gen_random_uuid();   -- patient A, assigned to P1
  b  uuid := gen_random_uuid();   -- patient B, assigned to P2
  c  uuid := gen_random_uuid();   -- patient C, assigned to nobody
  d  uuid := gen_random_uuid();   -- patient D, will redeem an invite
  p1 uuid := gen_random_uuid();   -- provider 1
  p2 uuid := gen_random_uuid();   -- provider 2
  ad uuid := gen_random_uuid();   -- admin
  dev_a uuid := gen_random_uuid();
  dev_b uuid := gen_random_uuid();
  appt_a uuid := gen_random_uuid();
  appt_b uuid := gen_random_uuid();
  note_a uuid := gen_random_uuid();
  note_b uuid := gen_random_uuid();
  doc_pub uuid := gen_random_uuid();
  doc_pub2 uuid := gen_random_uuid();
  doc_draft uuid := gen_random_uuid();
  belt_b uuid := gen_random_uuid();
  t record;
  m text;
  s text;
  n integer;
  pairs text[] := array['profiles.id', 'pregnancy_profiles.patient_id', 'devices.patient_id',
    'belt_readings.patient_id', 'maternal_vitals.patient_id', 'alerts.patient_id', 'appointments.patient_id',
    'consult_notes.patient_id', 'validation_pairs.patient_id', 'deletion_requests.patient_id',
    'consent_records.user_id'];
  tbl text;
  col text;
begin
  begin   -- everything in this block is rolled back at the end

    ---------------------------------------------------------------
    -- Fake users (the signup trigger creates their profiles as 'patient')
    ---------------------------------------------------------------
    insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
    select u, 'nl-test-' || u || '@nurturelink-test.invalid', now(), '{}'::jsonb
    from unnest(array[a, b, c, d, p1, p2, ad]) u;

    update public.profiles set role = 'provider' where id in (p1, p2);
    update public.profiles set role = 'admin' where id = ad;

    ---------------------------------------------------------------
    -- Fake data (inserted by the owner, which bypasses RLS)
    ---------------------------------------------------------------
    insert into public.pregnancy_profiles (patient_id, assigned_provider_id, due_date) values
      (a, p1, current_date + 100), (b, p2, current_date + 100), (c, null, current_date + 100);
    insert into public.devices (id, patient_id, kind) values (dev_a, a, 'belt'), (dev_b, b, 'belt');
    insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at) values (a, 140, 'simulator', now() - interval '10 days');
    insert into public.belt_readings (id, patient_id, fetal_hr_bpm, source, measured_at) values (belt_b, b, 140, 'simulator', now() - interval '10 days');
    insert into public.maternal_vitals (patient_id, spo2_percent, source, measured_at) values
      (a, 98, 'simulator', now() - interval '10 days'), (b, 98, 'simulator', now() - interval '10 days');
    insert into public.alerts (patient_id, alert_type, severity) values (a, 'low_spo2', 'warning'), (b, 'fever', 'warning');
    insert into public.appointments (id, patient_id, provider_id, starts_at, status) values
      (appt_a, a, p1, now() + interval '1 day', 'scheduled'), (appt_b, b, p2, now() + interval '1 day', 'scheduled');
    insert into public.consult_notes (id, patient_id, author_id, body, language) values
      (note_a, a, p1, 'fake note A', 'en'), (note_b, b, p2, 'fake note B', 'en');
    insert into public.validation_pairs (session_id, patient_id, recorded_by, doppler_fhr_bpm) values
      (gen_random_uuid(), a, p1, 140), (gen_random_uuid(), b, p2, 140);
    insert into public.consent_documents (id, doc_type, version, language, title, body, is_published) values
      -- Versions 901 and 902 on purpose: the real seed (006) uses version 1, and the
      -- unique key (doc_type, version, language) would clash with it.
      (doc_pub,   'terms_of_use',   901, 'en', 'DRAFT test', 'DRAFT, pending ethics/legal review', true),
      (doc_pub2,  'privacy_notice', 901, 'en', 'DRAFT test', 'DRAFT, pending ethics/legal review', true),
      (doc_draft, 'terms_of_use',   902, 'en', 'DRAFT test', 'DRAFT, pending ethics/legal review', false);
    insert into public.consent_records (user_id, document_id) values (a, doc_pub), (b, doc_pub);
    insert into public.deletion_requests (patient_id) values (b);
    insert into public.audit_log (actor_id, patient_id, action) values (p1, a, 'seed_row');
    insert into public.provider_invites (code, email, expires_at) values
      ('NLTESTINVITE00001', null, now() + interval '1 day'),
      ('NLTESTBOUNDCODE01', 'someone-else@nurturelink-test.invalid', now() + interval '1 day');
    update public.alert_thresholds set is_confirmed = true where alert_type = 'fhr_out_of_range';

    ---------------------------------------------------------------
    -- 1. anon: nothing at all
    ---------------------------------------------------------------
    for t in select tablename from pg_tables where schemaname = 'public' order by 1
    loop
      r := r || pg_temp.ck('anon has no privilege of any kind on ' || t.tablename,
        not has_any_column_privilege('anon', format('public.%I', t.tablename), 'SELECT,INSERT,UPDATE,REFERENCES')
        and not has_table_privilege('anon', format('public.%I', t.tablename), 'DELETE,TRUNCATE,TRIGGER')
        and pg_temp.x(format('select * from public.%I', t.tablename), null, 'anon') like 'ERR 42501 permission denied%'
        and pg_temp.x(format('insert into public.%I default values', t.tablename), null, 'anon') like 'ERR 42501 permission denied%'
        and pg_temp.x(format('delete from public.%I', t.tablename), null, 'anon') like 'ERR 42501 permission denied%');
    end loop;

    for t in
      select p.oid, p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig, p.proname
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.prosecdef and p.proname <> 'rls_auto_enable'
        and not exists (select 1 from pg_depend dd where dd.objid = p.oid and dd.deptype = 'e')
      order by 2
    loop
      r := r || pg_temp.ck('anon cannot execute SECURITY DEFINER function ' || t.sig,
        not has_function_privilege('anon', t.oid, 'EXECUTE'));   -- also false if PUBLIC had it
    end loop;
    r := r || pg_temp.ck('anon call is_provider() is permission denied', pg_temp.x('select public.is_provider()', null, 'anon') like 'ERR 42501 permission denied for function%');
    r := r || pg_temp.ck('anon call is_admin() is permission denied', pg_temp.x('select public.is_admin()', null, 'anon') like 'ERR 42501 permission denied for function%');
    r := r || pg_temp.ck('anon call is_assigned_provider() is permission denied', pg_temp.x(format('select public.is_assigned_provider(%L)', a), null, 'anon') like 'ERR 42501 permission denied for function%');
    r := r || pg_temp.ck('anon call redeem_provider_invite() is permission denied', pg_temp.x($q$select public.redeem_provider_invite('X')$q$, null, 'anon') like 'ERR 42501 permission denied for function%');
    r := r || pg_temp.ck('anon call set_my_language() is permission denied', pg_temp.x($q$select public.set_my_language('en')$q$, null, 'anon') like 'ERR 42501 permission denied for function%');

    for m in select unnest(array['handle_new_user()', 'create_alerts_from_reading()', 'guard_profile_role()',
                                 'set_updated_at()', 'guard_threshold_update()', 'nl_enable_rls_on_new_tables()',
                                 'guard_reading_time()'])
    loop
      r := r || pg_temp.ck('anon and signed-in users cannot call internal function ' || m,
        pg_temp.x('select public.' || m, null, 'anon') like 'ERR 42501%'
        and pg_temp.x('select public.' || m, a) like 'ERR 42501%');
    end loop;

    ---------------------------------------------------------------
    -- 2. Patient A: own data works (grants are not too tight)
    ---------------------------------------------------------------
    r := r || pg_temp.ck('A reads own profile', pg_temp.q(format('select count(*)::int from public.profiles where id = %L', a), a) = 1);
    r := r || pg_temp.ck('A sees only their own profile in total', pg_temp.q('select count(*)::int from public.profiles', a) = 1);
    r := r || pg_temp.ck('A cannot read the profile of their own provider', pg_temp.q(format('select count(*)::int from public.profiles where id = %L', p1), a) = 0);
    r := r || pg_temp.ck('A updates own language and display name',
      pg_temp.q(format($q$with u as (update public.profiles set language = 'fil', display_name = 'Test A' where id = %L returning 1) select count(*)::int from u$q$, a), a) = 1);
    r := r || pg_temp.ck('A cannot edit another profile (0 rows changed)',
      pg_temp.q(format($q$with u as (update public.profiles set display_name = 'hacked' where id = %L returning 1) select count(*)::int from u$q$, b), a) = 0);
    r := r || pg_temp.ck('set_my_language works for A', pg_temp.x($q$select public.set_my_language('en')$q$, a) = 'ok');
    r := r || pg_temp.ck('set_my_language rejects an unknown language', pg_temp.x($q$select public.set_my_language('xx')$q$, a) like 'ERR%invalid_language%');
    r := r || pg_temp.ck('A is not a provider and not an admin',
      pg_temp.q('select (public.is_provider() or public.is_admin())::int', a) = 0);

    -- role and other protected profile columns
    r := r || pg_temp.ck('A cannot change own role to admin', pg_temp.x(format($q$update public.profiles set role = 'admin' where id = %L$q$, a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot change own role to provider', pg_temp.x(format($q$update public.profiles set role = 'provider' where id = %L$q$, a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot change own date of birth', pg_temp.x(format($q$update public.profiles set date_of_birth = date '1990-01-01' where id = %L$q$, a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot insert a profile (admin) for themselves or anyone', pg_temp.x($q$insert into public.profiles (id, role) values (gen_random_uuid(), 'admin')$q$, a) like 'ERR 42501%');
    r := r || pg_temp.ck('A cannot delete a profile', pg_temp.x(format('delete from public.profiles where id = %L', a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A role is still patient', (select role from public.profiles where id = a) = 'patient');
    r := r || pg_temp.ck('A cannot read auth.users', pg_temp.x('select * from auth.users', a) like 'ERR 42501%');
    r := r || pg_temp.ck('A cannot use a wrong invite code', pg_temp.x($q$select public.redeem_provider_invite('NOTACODE0000000000')$q$, a) like 'ERR%invalid_invite%');
    r := r || pg_temp.ck('A cannot use an invite tied to another email', pg_temp.x($q$select public.redeem_provider_invite('NLTESTBOUNDCODE01')$q$, a) like 'ERR%invalid_invite%');
    r := r || pg_temp.ck('A is still a patient after the failed invite attempts', (select role from public.profiles where id = a) = 'patient');

    -- pregnancy_profiles
    r := r || pg_temp.ck('A reads own pregnancy profile', pg_temp.q(format('select count(*)::int from public.pregnancy_profiles where patient_id = %L', a), a) = 1);
    r := r || pg_temp.ck('A updates own pregnancy details',
      pg_temp.q(format($q$with u as (update public.pregnancy_profiles set due_date = current_date + 90, conditions = array['test'] where patient_id = %L returning 1) select count(*)::int from u$q$, a), a) = 1);
    r := r || pg_temp.ck('A cannot choose their own provider (assigned_provider_id not writable)',
      pg_temp.x(format('update public.pregnancy_profiles set assigned_provider_id = %L where patient_id = %L', p2, a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot create a pregnancy profile for someone else',
      pg_temp.x(format('insert into public.pregnancy_profiles (patient_id) values (%L)', d), a) like 'ERR 42501%');
    r := r || pg_temp.ck('C (no provider) creates own pregnancy profile only without a provider',
      pg_temp.x(format('insert into public.pregnancy_profiles (patient_id, assigned_provider_id) values (%L, %L)', d, p1), d) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('insert into public.pregnancy_profiles (patient_id, due_date) values (%L, current_date + 50)', d), d) = 'ok');

    -- devices
    r := r || pg_temp.ck('A pairs own device and updates it',
      pg_temp.x(format($q$insert into public.devices (patient_id, kind, label) values (%L, 'band', 'my band')$q$, a), a) = 'ok'
      and pg_temp.q(format($q$with u as (update public.devices set battery_percent = 80 where id = %L returning 1) select count(*)::int from u$q$, dev_a), a) = 1);
    r := r || pg_temp.ck('A cannot add a device for B', pg_temp.x(format($q$insert into public.devices (patient_id, kind) values (%L, 'belt')$q$, b), a) like 'ERR 42501%');
    r := r || pg_temp.ck('A cannot edit B device', pg_temp.q(format($q$with u as (update public.devices set battery_percent = 1 where id = %L returning 1) select count(*)::int from u$q$, dev_b), a) = 0);
    r := r || pg_temp.ck('A cannot delete a device', pg_temp.x(format('delete from public.devices where id = %L', dev_a), a) like 'ERR 42501 permission denied%');

    -- readings: append only, own only
    r := r || pg_temp.ck('A adds own belt reading with own device',
      pg_temp.x(format($q$insert into public.belt_readings (patient_id, device_id, fetal_hr_bpm, source, measured_at) values (%L, %L, 140, 'device', now() - interval '9 days')$q$, a, dev_a), a) = 'ok');
    r := r || pg_temp.ck('A adds own vitals', pg_temp.x(format($q$insert into public.maternal_vitals (patient_id, spo2_percent, temperature_c, source, measured_at) values (%L, 98, 36.8, 'device', now() - interval '9 days')$q$, a), a) = 'ok');
    r := r || pg_temp.ck('A cannot add a belt reading for B', pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 140, 'device')$q$, b), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot add vitals for B', pg_temp.x(format($q$insert into public.maternal_vitals (patient_id, spo2_percent, source) values (%L, 98, 'device')$q$, b), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot attach a reading to B device', pg_temp.x(format($q$insert into public.belt_readings (patient_id, device_id, fetal_hr_bpm, source) values (%L, %L, 140, 'device')$q$, a, dev_b), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot change or delete recorded readings',
      pg_temp.x(format('update public.belt_readings set fetal_hr_bpm = 150 where patient_id = %L', a), a) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('delete from public.belt_readings where patient_id = %L', a), a) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.maternal_vitals set spo2_percent = 99 where patient_id = %L', a), a) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('delete from public.maternal_vitals where patient_id = %L', a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot set the server-controlled created_at of a reading',
      pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source, created_at) values (%L, 140, 'device', now() - interval '5 years')$q$, a), a) like 'ERR 42501 permission denied%');
    -- 008: readings may be old (offline sync) but never from the future
    r := r || pg_temp.ck('A cannot store a reading dated in the future (a wrong phone clock cannot hide later alerts)',
      pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at) values (%L, 140, 'device', now() + interval '1 hour')$q$, a), a) like 'ERR P0001 reading_time_in_future%'
      and pg_temp.x(format($q$insert into public.maternal_vitals (patient_id, spo2_percent, source, measured_at) values (%L, 98, 'device', now() + interval '1 hour')$q$, a), a) like 'ERR P0001 reading_time_in_future%');
    -- (uses patient C so A's newest readings stay the ones the alert test below relies on)
    r := r || pg_temp.ck('a reading dated one minute ahead (a slightly fast phone clock) is accepted',
      pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at) values (%L, 140, 'device', now() + interval '1 minute')$q$, c), c) = 'ok'
      and pg_temp.x(format($q$insert into public.maternal_vitals (patient_id, spo2_percent, source, measured_at) values (%L, 98, 'device', now() + interval '1 minute')$q$, c), c) = 'ok');
    r := r || pg_temp.ck('A reads own readings and vitals',
      pg_temp.q(format('select count(*)::int from public.belt_readings where patient_id = %L', a), a) >= 2
      and pg_temp.q(format('select count(*)::int from public.maternal_vitals where patient_id = %L', a), a) >= 2);

    -- alerts: system-made; patient may only raise SOS
    r := r || pg_temp.ck('A reads own alerts', pg_temp.q(format('select count(*)::int from public.alerts where patient_id = %L', a), a) = 1);
    r := r || pg_temp.ck('A can raise an SOS for themselves', pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'critical')$q$, a), a) = 'ok');
    r := r || pg_temp.ck('A cannot raise an SOS for B', pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'critical')$q$, b), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot fake a clinical alert', pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'fhr_out_of_range', 'critical')$q$, a), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot pre-acknowledge an alert on insert', pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity, status) values (%L, 'sos', 'critical', 'resolved')$q$, a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot acknowledge or resolve an alert (0 rows changed)',
      pg_temp.q(format($q$with u as (update public.alerts set status = 'resolved' where patient_id = %L returning 1) select count(*)::int from u$q$, a), a) = 0);
    r := r || pg_temp.ck('A cannot lower an alert severity', pg_temp.x(format($q$update public.alerts set severity = 'info' where patient_id = %L$q$, a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot delete alerts', pg_temp.x(format('delete from public.alerts where patient_id = %L', a), a) like 'ERR 42501 permission denied%');

    -- end to end: A's own bad readings create an alert (only for A), visible to P1 only
    for n in 1..3 loop
      s := pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source, measured_at) values (%L, 190, 'device', now() - interval '1 day' + %s * interval '1 minute')$q$, a, n), a);
    end loop;
    r := r || pg_temp.ck('3 high readings sent by A create ONE open critical fhr alert for A',
      (select count(*) from public.alerts where patient_id = a and alert_type = 'fhr_out_of_range' and status = 'open' and severity = 'critical') = 1);
    r := r || pg_temp.ck('...A can read it', pg_temp.q(format($q$select count(*)::int from public.alerts where patient_id = %L and alert_type = 'fhr_out_of_range'$q$, a), a) = 1);
    r := r || pg_temp.ck('...B cannot read it', pg_temp.q(format($q$select count(*)::int from public.alerts where patient_id = %L$q$, a), b) = 0);
    r := r || pg_temp.ck('...assigned provider P1 can read it', pg_temp.q(format($q$select count(*)::int from public.alerts where patient_id = %L and alert_type = 'fhr_out_of_range'$q$, a), p1) = 1);
    r := r || pg_temp.ck('...unassigned provider P2 cannot read it', pg_temp.q(format($q$select count(*)::int from public.alerts where patient_id = %L$q$, a), p2) = 0);
    r := r || pg_temp.ck('...and B was not given an alert by A actions', (select count(*) from public.alerts where patient_id = b) = 1);

    -- appointments
    r := r || pg_temp.ck('A reads own appointments', pg_temp.q(format('select count(*)::int from public.appointments where patient_id = %L', a), a) = 1);
    r := r || pg_temp.ck('A requests an appointment with own provider',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at) values (%L, %L, now() + interval '3 days')$q$, a, p1), a) = 'ok');
    r := r || pg_temp.ck('A cannot request one with another provider',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at) values (%L, %L, now() + interval '3 days')$q$, a, p2), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot create an already scheduled or completed appointment',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '3 days', 'scheduled')$q$, a, p1), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot confirm or complete own appointment',
      pg_temp.x(format($q$update public.appointments set status = 'completed' where id = %L$q$, appt_a), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cancels own scheduled appointment',
      pg_temp.q(format($q$with u as (update public.appointments set status = 'cancelled' where id = %L returning 1) select count(*)::int from u$q$, appt_a), a) = 1);
    r := r || pg_temp.ck('A cannot reopen a cancelled appointment (0 rows changed)',
      pg_temp.q(format($q$with u as (update public.appointments set status = 'requested' where id = %L returning 1) select count(*)::int from u$q$, appt_a), a) = 0);
    r := r || pg_temp.ck('A cannot touch B appointment (0 rows changed)',
      pg_temp.q(format($q$with u as (update public.appointments set status = 'cancelled' where id = %L returning 1) select count(*)::int from u$q$, appt_b), a) = 0);

    -- provider-only tables are invisible or closed to a patient
    r := r || pg_temp.ck('A sees no consult notes (0 rows, even their own file)', pg_temp.q('select count(*)::int from public.consult_notes', a) = 0);
    r := r || pg_temp.ck('A cannot write a consult note', pg_temp.x(format($q$insert into public.consult_notes (patient_id, author_id, body, language) values (%L, %L, 'x', 'en')$q$, a, a), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot edit a consult note (0 rows changed)', pg_temp.q(format($q$with u as (update public.consult_notes set body = 'x' where id = %L returning 1) select count(*)::int from u$q$, note_a), a) = 0);
    r := r || pg_temp.ck('A sees no validation pairs', pg_temp.q('select count(*)::int from public.validation_pairs', a) = 0);
    r := r || pg_temp.ck('A cannot write a validation pair', pg_temp.x(format($q$insert into public.validation_pairs (session_id, patient_id, recorded_by, doppler_fhr_bpm) values (gen_random_uuid(), %L, %L, 140)$q$, a, a), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A sees no alert thresholds', pg_temp.q('select count(*)::int from public.alert_thresholds', a) = 0);
    r := r || pg_temp.ck('A cannot change an alert threshold (0 rows, value unchanged)',
      pg_temp.q($q$with u as (update public.alert_thresholds set min_value = 0 where alert_type = 'fhr_out_of_range' returning 1) select count(*)::int from u$q$, a) = 0
      and (select min_value from public.alert_thresholds where alert_type = 'fhr_out_of_range') = 110);
    r := r || pg_temp.ck('A cannot read the audit log (permission denied)', pg_temp.x('select * from public.audit_log', a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot write the audit log', pg_temp.x(format($q$insert into public.audit_log (actor_id, patient_id, action) values (%L, %L, 'fake')$q$, a, a), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot touch provider_invites (permission denied)',
      pg_temp.x('select * from public.provider_invites', a) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$insert into public.provider_invites (code, expires_at) values ('AAAAAAAAAAAAAAAA', now() + interval '1 day')$q$, a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot touch app_settings (permission denied)',
      pg_temp.x('select * from public.app_settings', a) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$update public.app_settings set value = 'on' where key = 'demo_mode'$q$, a) like 'ERR 42501 permission denied%');

    -- consent
    r := r || pg_temp.ck('A reads published consent documents but not drafts',
      pg_temp.q(format('select count(*)::int from public.consent_documents where id = %L', doc_pub), a) = 1
      and pg_temp.q(format('select count(*)::int from public.consent_documents where id = %L', doc_draft), a) = 0);
    r := r || pg_temp.ck('A cannot write consent documents (permission denied)',
      pg_temp.x($q$insert into public.consent_documents (doc_type, version, language, title, body) values ('terms_of_use', 9, 'en', 'x', 'x')$q$, a) like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$update public.consent_documents set body = 'x' where id = %L$q$, doc_pub), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A accepts a published document', pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L)', a, doc_pub2), a) = 'ok');
    r := r || pg_temp.ck('A cannot accept an unpublished draft', pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L)', a, doc_draft), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot record consent for B', pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L)', b, doc_pub2), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot back-date accepted_at', pg_temp.x(format($q$insert into public.consent_records (user_id, document_id, accepted_at) values (%L, %L, now() - interval '1 year')$q$, a, doc_pub), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A reads only own consent records', pg_temp.q('select count(*)::int from public.consent_records', a) = 2);
    r := r || pg_temp.ck('A withdraws consent once (only withdrawn_at changes)',
      pg_temp.q(format($q$with u as (update public.consent_records set withdrawn_at = now() where user_id = %L and document_id = %L returning 1) select count(*)::int from u$q$, a, doc_pub), a) = 1
      and pg_temp.q(format($q$with u as (update public.consent_records set withdrawn_at = now() where user_id = %L and document_id = %L returning 1) select count(*)::int from u$q$, a, doc_pub), a) = 0);
    s := pg_temp.x(format('update public.consent_records set withdrawn_at = null where user_id = %L and document_id = %L', a, doc_pub), a);   -- tries to undo the withdrawal
    r := r || pg_temp.ck('A cannot undo a withdrawal or edit other consent columns',
      (select count(*) from public.consent_records where user_id = a and document_id = doc_pub and withdrawn_at is not null) = 1
      and pg_temp.x(format($q$update public.consent_records set accepted_at = now() where user_id = %L$q$, a), a) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.consent_records set document_id = %L where user_id = %L', doc_pub2, a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('A cannot edit B consent (0 rows changed)',
      pg_temp.q(format($q$with u as (update public.consent_records set withdrawn_at = now() where user_id = %L returning 1) select count(*)::int from u$q$, b), a) = 0);

    -- deletion requests
    r := r || pg_temp.ck('A files a deletion request for themselves', pg_temp.x(format('insert into public.deletion_requests (patient_id) values (%L)', a), a) = 'ok');
    r := r || pg_temp.ck('A cannot file one for B', pg_temp.x(format('insert into public.deletion_requests (patient_id) values (%L)', c), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A reads only own deletion request', pg_temp.q('select count(*)::int from public.deletion_requests', a) = 1);
    r := r || pg_temp.ck('A cannot mark a deletion request completed',
      pg_temp.x(format($q$update public.deletion_requests set status = 'completed' where patient_id = %L$q$, a), a) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('delete from public.deletion_requests where patient_id = %L', a), a) like 'ERR 42501 permission denied%');

    ---------------------------------------------------------------
    -- 3. Patients cannot read each other (every patient-data table)
    ---------------------------------------------------------------
    foreach m in array pairs loop
      tbl := split_part(m, '.', 1);
      col := split_part(m, '.', 2);
      r := r || pg_temp.ck('patients are isolated from each other in ' || tbl,
        pg_temp.q(format('select count(*)::int from public.%I where %I in (%L, %L)', tbl, col, b, c), a) = 0      -- A sees nothing of B or C
        and pg_temp.q(format('select count(*)::int from public.%I where %I in (%L, %L)', tbl, col, a, b), c) = 0   -- C sees nothing of A or B
        and pg_temp.q(format('select count(*)::int from public.%I where %I = %L', tbl, col, a), b) = 0              -- B sees nothing of A
        and (tbl in ('consult_notes', 'validation_pairs')                                                          -- (those two are provider-only for patients too)
             or pg_temp.q(format('select count(*)::int from public.%I where %I = %L', tbl, col, a), a) >= 1),      -- ...and A does see their own
        'A/B/C isolation or own-row check failed on ' || tbl);
    end loop;

    ---------------------------------------------------------------
    -- 4. Provider P1 (assigned to A)
    ---------------------------------------------------------------
    foreach m in array pairs loop
      tbl := split_part(m, '.', 1);
      col := split_part(m, '.', 2);
      r := r || pg_temp.ck('assigned provider reads own patient and nobody else in ' || tbl,
        pg_temp.q(format('select count(*)::int from public.%I where %I in (%L, %L, %L)', tbl, col, b, c, d), p1) = 0   -- not B, C, D
        and pg_temp.q(format('select count(*)::int from public.%I where %I = %L', tbl, col, a), p2) = 0                 -- unassigned provider sees not A
        and (tbl in ('consent_records', 'deletion_requests')                                                           -- providers do not read these two at all
             and pg_temp.q(format('select count(*)::int from public.%I where %I = %L', tbl, col, a), p1) = 0
             or tbl not in ('consent_records', 'deletion_requests')
                and pg_temp.q(format('select count(*)::int from public.%I where %I = %L', tbl, col, a), p1) >= 1),
        'provider isolation or assigned-read check failed on ' || tbl);
    end loop;
    r := r || pg_temp.ck('P1 sees exactly two profiles: own and A', pg_temp.q('select count(*)::int from public.profiles', p1) = 2);
    r := r || pg_temp.ck('P1 role is provider', pg_temp.q('select public.is_provider()::int', p1) = 1 and pg_temp.q('select public.is_assigned_provider(' || quote_literal(a) || ')::int', p1) = 1
                                                and pg_temp.q('select public.is_assigned_provider(' || quote_literal(b) || ')::int', p1) = 0);
    r := r || pg_temp.ck('P1 cannot read audit log, invites or settings (permission denied)',
      pg_temp.x('select * from public.audit_log', p1) like 'ERR 42501 permission denied%'
      and pg_temp.x('select * from public.provider_invites', p1) like 'ERR 42501 permission denied%'
      and pg_temp.x('select * from public.app_settings', p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('P1 cannot change own role or A role',
      pg_temp.x(format($q$update public.profiles set role = 'admin' where id = %L$q$, p1), p1) like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$update public.profiles set role = 'provider' where id = %L$q$, a), p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('P1 cannot edit A profile (0 rows changed)',
      pg_temp.q(format($q$with u as (update public.profiles set display_name = 'x' where id = %L returning 1) select count(*)::int from u$q$, a), p1) = 0);
    r := r || pg_temp.ck('P1 cannot assign themselves to a patient',
      pg_temp.x(format('update public.pregnancy_profiles set assigned_provider_id = %L where patient_id = %L', p1, c), p1) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('insert into public.pregnancy_profiles (patient_id, assigned_provider_id) values (%L, %L)', p1, p1), p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('P1 still cannot see C after trying', pg_temp.q(format('select count(*)::int from public.pregnancy_profiles where patient_id = %L', c), p1) = 0);
    r := r || pg_temp.ck('P1 cannot write readings or vitals of A',
      pg_temp.x(format($q$insert into public.belt_readings (patient_id, fetal_hr_bpm, source) values (%L, 140, 'device')$q$, a), p1) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format('update public.belt_readings set fetal_hr_bpm = 1 where patient_id = %L', a), p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('P1 cannot change A pregnancy details', pg_temp.q(format($q$with u as (update public.pregnancy_profiles set due_date = current_date where patient_id = %L returning 1) select count(*)::int from u$q$, a), p1) = 0);

    -- alerts
    r := r || pg_temp.ck('P1 acknowledges A alert and records the action',
      pg_temp.q(format($q$with u as (update public.alerts set status = 'acknowledged', acknowledged_by = %L, acknowledged_at = now(), action_taken = 'call' where patient_id = %L and alert_type = 'low_spo2' returning 1) select count(*)::int from u$q$, p1, a), p1) = 1);
    r := r || pg_temp.ck('P1 cannot acknowledge B alert (0 rows changed)',
      pg_temp.q(format($q$with u as (update public.alerts set status = 'acknowledged', acknowledged_by = %L where patient_id = %L returning 1) select count(*)::int from u$q$, p1, b), p1) = 0);
    r := r || pg_temp.ck('P1 cannot sign an acknowledgement as P2', pg_temp.x(format($q$update public.alerts set acknowledged_by = %L where patient_id = %L$q$, p2, a), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('P1 cannot change alert type, severity or patient',
      pg_temp.x(format($q$update public.alerts set severity = 'info' where patient_id = %L$q$, a), p1) like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$update public.alerts set patient_id = %L where patient_id = %L$q$, b, a), p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('P1 can add an alert for A but not for B',
      pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'warning')$q$, a), p1) = 'ok'
      and pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'warning')$q$, b), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('P1 cannot delete alerts', pg_temp.x(format('delete from public.alerts where patient_id = %L', a), p1) like 'ERR 42501 permission denied%');

    -- consult notes
    r := r || pg_temp.ck('P1 reads A note and writes a new one as themselves',
      pg_temp.q(format('select count(*)::int from public.consult_notes where id = %L', note_a), p1) = 1
      and pg_temp.x(format($q$insert into public.consult_notes (patient_id, author_id, body, language) values (%L, %L, 'new note', 'fil')$q$, a, p1), p1) = 'ok');
    r := r || pg_temp.ck('P1 cannot write a note for B or in P2 name',
      pg_temp.x(format($q$insert into public.consult_notes (patient_id, author_id, body, language) values (%L, %L, 'x', 'en')$q$, b, p1), p1) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format($q$insert into public.consult_notes (patient_id, author_id, body, language) values (%L, %L, 'x', 'en')$q$, a, p2), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('P1 cannot link a note to B appointment',
      pg_temp.x(format($q$insert into public.consult_notes (patient_id, author_id, appointment_id, body, language) values (%L, %L, %L, 'x', 'en')$q$, a, p1, appt_b), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('P1 edits own note, not B note',
      pg_temp.q(format($q$with u as (update public.consult_notes set body = 'edited' where id = %L returning 1) select count(*)::int from u$q$, note_a), p1) = 1
      and pg_temp.q(format($q$with u as (update public.consult_notes set body = 'edited' where id = %L returning 1) select count(*)::int from u$q$, note_b), p1) = 0);
    r := r || pg_temp.ck('P1 cannot delete notes or change who wrote one',
      pg_temp.x(format('delete from public.consult_notes where id = %L', note_a), p1) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.consult_notes set author_id = %L where id = %L', p2, note_a), p1) like 'ERR 42501 permission denied%');

    -- appointments
    r := r || pg_temp.ck('P1 schedules an appointment for A, not for B',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '5 days', 'scheduled')$q$, a, p1), p1) = 'ok'
      and pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '5 days', 'scheduled')$q$, b, p1), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('P1 confirms and completes A appointment, not B',
      pg_temp.q(format($q$with u as (update public.appointments set status = 'completed' where patient_id = %L returning 1) select count(*)::int from u$q$, a), p1) >= 1
      and pg_temp.q(format($q$with u as (update public.appointments set status = 'completed' where id = %L returning 1) select count(*)::int from u$q$, appt_b), p1) = 0);

    -- validation pairs
    r := r || pg_temp.ck('P1 adds a validation pair for A as themselves',
      pg_temp.x(format($q$insert into public.validation_pairs (session_id, patient_id, recorded_by, doppler_fhr_bpm, belt_fhr_bpm) values (gen_random_uuid(), %L, %L, 140, 138)$q$, a, p1), p1) = 'ok');
    r := r || pg_temp.ck('P1 cannot add a pair for B or as P2 or linked to B reading',
      pg_temp.x(format($q$insert into public.validation_pairs (session_id, patient_id, recorded_by, doppler_fhr_bpm) values (gen_random_uuid(), %L, %L, 140)$q$, b, p1), p1) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format($q$insert into public.validation_pairs (session_id, patient_id, recorded_by, doppler_fhr_bpm) values (gen_random_uuid(), %L, %L, 140)$q$, a, p2), p1) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format($q$insert into public.validation_pairs (session_id, patient_id, recorded_by, doppler_fhr_bpm, belt_reading_id) values (gen_random_uuid(), %L, %L, 140, %L)$q$, a, p1, belt_b), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('P1 gives the OB sign-off as themselves',
      pg_temp.q(format($q$with u as (update public.validation_pairs set ob_signoff_by = %L, ob_signoff_at = now() where patient_id = %L returning 1) select count(*)::int from u$q$, p1, a), p1) >= 1);
    r := r || pg_temp.ck('P1 cannot ALSO give the pediatrician sign-off, nor sign as P2',
      pg_temp.x(format($q$update public.validation_pairs set pediatrician_signoff_by = %L where patient_id = %L$q$, p1, a), p1) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format($q$update public.validation_pairs set pediatrician_signoff_by = %L where patient_id = %L$q$, p2, a), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('P1 cannot delete validation pairs', pg_temp.x(format('delete from public.validation_pairs where patient_id = %L', a), p1) like 'ERR 42501 permission denied%');

    -- alert thresholds: editable by providers, but guarded
    r := r || pg_temp.ck('P1 reads the 4 alert thresholds', pg_temp.q('select count(*)::int from public.alert_thresholds', p1) = 4);
    r := r || pg_temp.ck('P1 edits a threshold limit',
      pg_temp.q($q$with u as (update public.alert_thresholds set min_value = 105 where alert_type = 'fhr_out_of_range' returning 1) select count(*)::int from u$q$, p1) = 1);
    r := r || pg_temp.ck('...which resets the medical-officer confirmation',
      (select is_confirmed from public.alert_thresholds where alert_type = 'fhr_out_of_range') = false);
    r := r || pg_temp.ck('...records who changed it', (select updated_by from public.alert_thresholds where alert_type = 'fhr_out_of_range') = p1);
    r := r || pg_temp.ck('...and writes an audit log entry with old and new values',
      exists (select 1 from public.audit_log where actor_id = p1 and action = 'alert_threshold_updated'
              and details #>> '{old,min}' = '110' and details #>> '{new,min}' = '105'));
    r := r || pg_temp.ck('P1 cannot confirm thresholds, rename a threshold, insert or delete one',
      pg_temp.x($q$update public.alert_thresholds set is_confirmed = true where alert_type = 'fever'$q$, p1) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$update public.alert_thresholds set alert_type = 'low_spo2' where alert_type = 'fever'$q$, p1) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$delete from public.alert_thresholds where alert_type = 'fever'$q$, p1) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$insert into public.alert_thresholds (alert_type, severity) values ('fever', 'info')$q$, p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a notes-only edit does not reset confirmation',
      (select is_confirmed from public.alert_thresholds where alert_type = 'fever') = false  -- seed is false already; check the guard does not break notes edits
      and pg_temp.q($q$with u as (update public.alert_thresholds set notes = 'n' where alert_type = 'fever' returning 1) select count(*)::int from u$q$, p1) = 1);

    -- audit log: insert only
    r := r || pg_temp.ck('P1 writes an audit entry about A',
      pg_temp.x(format($q$insert into public.audit_log (actor_id, patient_id, action) values (%L, %L, 'view_patient')$q$, p1, a), p1) = 'ok');
    r := r || pg_temp.ck('P1 cannot write an audit entry in another name, or about B',
      pg_temp.x(format($q$insert into public.audit_log (actor_id, patient_id, action) values (%L, %L, 'view_patient')$q$, p2, a), p1) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format($q$insert into public.audit_log (actor_id, patient_id, action) values (%L, %L, 'view_patient')$q$, p1, b), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('P1 cannot read, change or delete the audit log',
      pg_temp.x('select * from public.audit_log', p1) like 'ERR 42501 permission denied%'
      and pg_temp.x($q$update public.audit_log set action = 'x'$q$, p1) like 'ERR 42501 permission denied%'
      and pg_temp.x('delete from public.audit_log', p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('P1 reads published consent documents only', pg_temp.q(format('select count(*)::int from public.consent_documents where id in (%L, %L)', doc_pub, doc_draft), p1) = 1);
    r := r || pg_temp.ck('P1 cannot redeem an invite (already a provider)', pg_temp.x($q$select public.redeem_provider_invite('NLTESTINVITE00001')$q$, p1) like 'ERR%not_eligible%');

    ---------------------------------------------------------------
    -- 5. Admin account
    ---------------------------------------------------------------
    r := r || pg_temp.ck('admin is recognised', pg_temp.q('select public.is_admin()::int', ad) = 1 and pg_temp.q('select public.is_provider()::int', ad) = 0);
    r := r || pg_temp.ck('admin reads all deletion requests (the 2 test ones, plus any real ones)',
      pg_temp.q(format('select count(*)::int from public.deletion_requests where patient_id in (%L, %L)', a, b), ad) = 2
      and pg_temp.q('select count(*)::int from public.deletion_requests', ad) >= 2);
    r := r || pg_temp.ck('admin sees draft consent documents', pg_temp.q(format('select count(*)::int from public.consent_documents where id = %L', doc_draft), ad) = 1);
    r := r || pg_temp.ck('admin account does not get patient data in the app',
      pg_temp.q('select count(*)::int from public.belt_readings', ad) = 0
      and pg_temp.q('select count(*)::int from public.profiles', ad) = 1
      and pg_temp.q('select count(*)::int from public.consult_notes', ad) = 0);
    r := r || pg_temp.ck('admin account cannot write consent documents or read the audit log from the client',
      pg_temp.x($q$insert into public.consent_documents (doc_type, version, language, title, body) values ('terms_of_use', 9, 'en', 'x', 'x')$q$, ad) like 'ERR 42501 permission denied%'
      and pg_temp.x('select * from public.audit_log', ad) like 'ERR 42501 permission denied%'
      and pg_temp.x('select * from public.provider_invites', ad) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('admin cannot change a role from the client',
      pg_temp.x(format($q$update public.profiles set role = 'provider' where id = %L$q$, a), ad) like 'ERR 42501 permission denied%');

    ---------------------------------------------------------------
    -- 6. Invite flow end to end
    ---------------------------------------------------------------
    s := pg_temp.x($q$select public.redeem_provider_invite('nltestinvite00001')$q$, d);   -- lower case on purpose: codes are case-insensitive
    r := r || pg_temp.ck('D redeems a valid code and becomes a provider',
      s = 'ok' and (select role from public.profiles where id = d) = 'provider', s);
    r := r || pg_temp.ck('the used code cannot be used again by another patient', pg_temp.x($q$select public.redeem_provider_invite('NLTESTINVITE00001')$q$, c) like 'ERR%invalid_invite%');
    r := r || pg_temp.ck('a new provider still sees no patients until assigned', pg_temp.q('select count(*)::int from public.pregnancy_profiles where patient_id <> ' || quote_literal(d), d) = 0);

    ---------------------------------------------------------------
    -- 7. Structure of the whole database
    ---------------------------------------------------------------
    r := r || pg_temp.ck('RLS is enabled on every table in public',
      not exists (select 1 from pg_class cl join pg_namespace ns on ns.oid = cl.relnamespace
                  where ns.nspname = 'public' and cl.relkind in ('r', 'p') and not cl.relrowsecurity),
      (select string_agg(cl.relname, ', ') from pg_class cl join pg_namespace ns on ns.oid = cl.relnamespace
        where ns.nspname = 'public' and cl.relkind in ('r', 'p') and not cl.relrowsecurity));
    r := r || pg_temp.ck('every table in public has at least one policy',
      not exists (select 1 from pg_tables tt where tt.schemaname = 'public'
                  and not exists (select 1 from pg_policies pp where pp.schemaname = 'public' and pp.tablename = tt.tablename)),
      (select string_agg(tt.tablename, ', ') from pg_tables tt where tt.schemaname = 'public'
        and not exists (select 1 from pg_policies pp where pp.schemaname = 'public' and pp.tablename = tt.tablename)));
    r := r || pg_temp.ck('no policy applies to anon or PUBLIC',
      not exists (select 1 from pg_policies pp where pp.schemaname = 'public' and (pp.roles && array['anon', 'public']::name[])));
    r := r || pg_temp.ck('no view or materialized view in public can bypass RLS (none exist, or all are security_invoker)',
      not exists (select 1 from pg_class cl join pg_namespace ns on ns.oid = cl.relnamespace
                  where ns.nspname = 'public' and cl.relkind in ('v', 'm')
                    and not coalesce('security_invoker=true' = any (cl.reloptions), false)));
    r := r || pg_temp.ck('authenticated has no table-level write privilege and no DELETE anywhere (writes are column-level)',
      not exists (select 1 from pg_class cl join pg_namespace ns on ns.oid = cl.relnamespace
                  where ns.nspname = 'public' and cl.relkind in ('r', 'p')
                    and has_table_privilege('authenticated', cl.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')));
    r := r || pg_temp.ck('authenticated has no sequence privileges',
      not exists (select 1 from pg_class cl join pg_namespace ns on ns.oid = cl.relnamespace
                  where ns.nspname = 'public' and cl.relkind = 'S'
                    and (has_sequence_privilege('authenticated', cl.oid, 'USAGE,SELECT,UPDATE')
                         or has_sequence_privilege('anon', cl.oid, 'USAGE,SELECT,UPDATE'))));
    r := r || pg_temp.ck('nobody can create objects in the public schema',
      not has_schema_privilege('anon', 'public', 'CREATE') and not has_schema_privilege('authenticated', 'public', 'CREATE'));
    r := r || pg_temp.ck('protected columns are not writable by clients',
      not has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.profiles', 'role', 'INSERT')
      and not has_column_privilege('authenticated', 'public.profiles', 'date_of_birth', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.pregnancy_profiles', 'assigned_provider_id', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.pregnancy_profiles', 'assigned_provider_id', 'INSERT')
      and not has_column_privilege('authenticated', 'public.alert_thresholds', 'is_confirmed', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.alerts', 'severity', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.consent_records', 'accepted_at', 'INSERT')
      and not has_column_privilege('authenticated', 'public.belt_readings', 'created_at', 'INSERT'));
    r := r || pg_temp.ck('signed-in users can execute exactly the 5 client functions',
      (select coalesce(string_agg(p.proname, ',' order by p.proname), '') from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
        where ns.nspname = 'public' and p.proname <> 'rls_auto_enable' and has_function_privilege('authenticated', p.oid, 'EXECUTE')
          and not exists (select 1 from pg_depend dd where dd.objid = p.oid and dd.deptype = 'e'))
      = 'is_admin,is_assigned_provider,is_provider,redeem_provider_invite,set_my_language',
      (select string_agg(p.proname, ',' order by p.proname) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
        where ns.nspname = 'public' and p.proname <> 'rls_auto_enable' and has_function_privilege('authenticated', p.oid, 'EXECUTE')));
    r := r || pg_temp.ck('every SECURITY DEFINER function in public has a fixed search_path',
      not exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                  where ns.nspname = 'public' and p.prosecdef and p.proname <> 'rls_auto_enable'
                    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%')),
      (select string_agg(p.proname, ', ') from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
        where ns.nspname = 'public' and p.prosecdef and p.proname <> 'rls_auto_enable'
          and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%')));
    r := r || pg_temp.ck('Realtime does not publish any sensitive table',
      not exists (select 1 from pg_publication_tables pt where pt.schemaname = 'public'
                  and pt.tablename in ('audit_log', 'validation_pairs', 'consult_notes', 'provider_invites', 'app_settings',
                                       'deletion_requests', 'consent_records', 'consent_documents', 'alert_thresholds',
                                       'profiles', 'pregnancy_profiles')),
      (select string_agg(pt.tablename, ', ') from pg_publication_tables pt where pt.schemaname = 'public'));

    -- information only
    r := r || ('INFO|Realtime currently publishes these public tables (none is expected until Phase 3): ' ||
              coalesce((select string_agg(pt.tablename, ', ') from pg_publication_tables pt where pt.schemaname = 'public'), '(none)') || '|')::text;
    r := r || ('INFO|Supabase-managed function rls_auto_enable(): anon can execute = ' ||
              coalesce((select has_function_privilege('anon', p.oid, 'EXECUTE')::text from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                        where ns.nspname = 'public' and p.proname = 'rls_auto_enable'), '(not present)') ||
              ' (not ours; left alone on purpose, excluded from the function checks above)|')::text;

    -- Abort the block so every fake row above is rolled back. The report in r is kept.
    raise exception 'nl_rollback' using errcode = 'NL999';
  exception
    when sqlstate 'NL999' then
      null;
  end;

  -- summary line first
  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')
    into n, tbl from unnest(r) e;  -- tbl is reused as a throwaway text variable
  return array['SUMMARY|' || n || ' PASS, ' || tbl || ' FAIL|' || case when tbl = '0' then 'all access rules hold' else 'send me every FAIL row' end] || r;
end
$fn$;

-- ---------------------------------------------------------------------
-- The report: SUMMARY first, then FAIL, then INFO, then PASS
-- ---------------------------------------------------------------------
select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_access_tests()) with ordinality as x(e, o)
order by 1;
