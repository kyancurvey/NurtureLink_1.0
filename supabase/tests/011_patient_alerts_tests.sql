-- =====================================================================
-- 011_patient_alerts_tests.sql
-- NurtureLink step 3.3: proves that migration 011 does what it should and
-- nothing more.
--   * mark_alert_seen(): a patient marks their OWN alert as seen, ONCE. The
--     time is the server's. The same call on another patient's alert, a
--     missing alert or an already-seen alert returns false and changes
--     nothing (the first time is kept). anon cannot run it. A provider cannot
--     use it for a patient.
--   * A patient cannot change severity, alert_type, details, patient_id,
--     status, acknowledgement, action_taken or resolved_at, and cannot write
--     seen_by_patient_at directly. No patient UPDATE policy exists.
--   * A provider cannot write seen_by_patient_at, but can read it.
--   * "Seen" is cosmetic: status, the acknowledgement, the Home status and
--     the provider's unacknowledged count do not change.
--   * A patient with no provider (like patient10) is invisible to EVERY
--     provider; a patient sees only their own alerts (this is what Realtime
--     delivers, because Realtime applies the same select policy).
--   * anon gets "permission denied".
--   * Realtime publishes ONLY alerts, with the default REPLICA IDENTITY.
--
-- HOW IT WORKS: like 010_monitor_tests.sql. Clearly fake users (emails end in
-- ".invalid") and fake alerts are created inside ONE block that is
-- deliberately aborted at its end, so everything is rolled back (the report
-- survives). For each test the session switches to the role "authenticated"
-- or "anon" with a fake user's id in request.jwt.claims, like a real API
-- request. Real data is never changed.
--
-- NOT PROVEN HERE: that Realtime really delivers an event to the right phone
-- (a SQL file cannot open a Realtime connection). Do the two-device check in
-- the Manual Steps.
--
-- HOW TO RUN: run 011_patient_alerts.sql first. Paste this WHOLE file into a
-- new SQL Editor tab and click Run (if asked about "destructive operations",
-- click Run: the file only creates temporary functions; the fake data is
-- rolled back). Result: one table, SUMMARY first, then FAIL, INFO, PASS.
-- Expected: "N PASS, 0 FAIL".
-- WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and every FAIL row.
--
-- DEPENDS ON: 000 to 011. READ-ONLY for your real data.
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

-- Call mark_alert_seen() as a signed-in user (p_uid null = signed in with no
-- user id) or as anon. Returns 'true', 'false' or 'ERR <sqlstate> <message>'.
create or replace function pg_temp.mark(p_uid uuid, p_alert uuid, p_role text default 'authenticated')
returns text
language plpgsql
as $fn$
declare
  v boolean;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    v := public.mark_alert_seen(p_alert);
  exception when others then
    reset role;
    return 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
  reset role;
  return v::text;
end
$fn$;

-- The Home status word of a patient (my_home_status), read as that patient.
create or replace function pg_temp.home(p_uid uuid)
returns text
language plpgsql
as $fn$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  begin
    v := public.my_home_status();
  exception when others then
    reset role;
    return 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
  reset role;
  return v ->> 'status';
end
$fn$;

-- ---------------------------------------------------------------------
-- The tests
-- ---------------------------------------------------------------------
create or replace function pg_temp.nl_alert_tests()
returns text[]
language plpgsql
as $fn$
declare
  r   text[] := '{}';
  pa  uuid := gen_random_uuid();   -- patient A, assigned to provider P1
  pb  uuid := gen_random_uuid();   -- patient B, assigned to provider P1
  pc  uuid := gen_random_uuid();   -- patient with NO provider (like patient10)
  pd  uuid := gen_random_uuid();   -- patient D, assigned to provider P2
  p1  uuid := gen_random_uuid();   -- provider 1
  p2  uuid := gen_random_uuid();   -- provider 2
  a_fhr  uuid;   -- A: open critical heart-rate alert
  a_ack  uuid;   -- A: acknowledged low SpO2 alert (handled)
  a_sos  uuid;   -- A: open SOS
  a_new  uuid;   -- A: a fresh, unseen alert added during the test
  b_fhr  uuid;   -- B: open heart-rate alert
  c_fhr  uuid;   -- C: open heart-rate alert (no provider)
  d_fhr  uuid;   -- D: open heart-rate alert
  snap   jsonb;
  snap2  jsonb;
  t1     timestamptz;
  s      text;
  fn_exists boolean;
  home_before text;
  home_after  text;
  open_before integer;
  open_after  integer;
  pass_n integer;
  fail_n text;
begin
  fn_exists := to_regprocedure('public.mark_alert_seen(uuid)') is not null;
  r := r || pg_temp.ck('migration 011 has been run (mark_alert_seen(uuid) exists)', fn_exists,
    'run supabase/migrations/011_patient_alerts.sql first');
  if not fn_exists then
    return array['SUMMARY|0 PASS, 1 FAIL|run supabase/migrations/011_patient_alerts.sql first'] || r;
  end if;

  begin   -- everything in this block is rolled back at the end

    ---------------------------------------------------------------
    -- Fake users, assignments and alerts
    ---------------------------------------------------------------
    insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
    select u, 'nl-alerts-' || u || '@nurturelink-test.invalid', now(), '{}'::jsonb
    from unnest(array[pa, pb, pc, pd, p1, p2]) u;
    update public.profiles set role = 'provider' where id in (p1, p2);
    insert into public.pregnancy_profiles (patient_id, assigned_provider_id, due_date) values
      (pa, p1, current_date + 100), (pb, p1, current_date + 100),
      (pc, null, current_date + 100), (pd, p2, current_date + 100);

    insert into public.alerts (patient_id, alert_type, severity, details)
      values (pa, 'fhr_out_of_range', 'critical', '{"value":172,"min":110,"max":160,"readings":3}') returning id into a_fhr;
    insert into public.alerts (patient_id, alert_type, severity, details, status, acknowledged_by, acknowledged_at, action_taken)
      values (pa, 'low_spo2', 'warning', '{"value":93,"min":95,"readings":2}', 'acknowledged', p1, now(), 'call') returning id into a_ack;
    insert into public.alerts (patient_id, alert_type, severity, details)
      values (pa, 'sos', 'critical', '{}') returning id into a_sos;
    insert into public.alerts (patient_id, alert_type, severity, details)
      values (pb, 'fhr_out_of_range', 'critical', '{"value":105,"min":110,"max":160,"readings":3}') returning id into b_fhr;
    insert into public.alerts (patient_id, alert_type, severity, details)
      values (pc, 'fhr_out_of_range', 'critical', '{"value":170,"min":110,"max":160,"readings":3}') returning id into c_fhr;
    insert into public.alerts (patient_id, alert_type, severity, details)
      values (pd, 'fhr_out_of_range', 'critical', '{"value":171,"min":110,"max":160,"readings":3}') returning id into d_fhr;

    ---------------------------------------------------------------
    -- 1. The column and the function as built
    ---------------------------------------------------------------
    r := r || pg_temp.ck('alerts.seen_by_patient_at exists, is timestamptz and may be empty',
      exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'alerts'
              and column_name = 'seen_by_patient_at' and data_type = 'timestamp with time zone' and is_nullable = 'YES'));
    r := r || pg_temp.ck('a new alert starts as not seen',
      not exists (select 1 from public.alerts where id in (a_fhr, a_ack, a_sos, b_fhr, c_fhr, d_fhr) and seen_by_patient_at is not null));
    r := r || pg_temp.ck('mark_alert_seen is SECURITY DEFINER, has a fixed search_path, takes one argument and returns boolean',
      exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'mark_alert_seen' and p.prosecdef and p.pronargs = 1
                and p.prorettype = 'boolean'::regtype
                and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')));
    r := r || pg_temp.ck('EXECUTE is not open to PUBLIC; anon cannot execute; signed-in users can',
      not exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where p.oid = 'public.mark_alert_seen(uuid)'::regprocedure and a.grantee = 0)
      and not has_function_privilege('anon', 'public.mark_alert_seen(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.mark_alert_seen(uuid)', 'execute'));
    r := r || pg_temp.ck('anon calling mark_alert_seen gets permission denied',
      pg_temp.mark(null, a_fhr, 'anon') like 'ERR 42501 permission denied for function%');
    r := r || pg_temp.ck('signed in with no user id gets not_signed_in',
      pg_temp.mark(null, a_fhr) = 'ERR P0001 not_signed_in');

    ---------------------------------------------------------------
    -- 2. No patient UPDATE route exists
    ---------------------------------------------------------------
    r := r || pg_temp.ck('the only UPDATE policy on alerts is the provider one (no patient UPDATE policy)',
      (select count(*) from pg_policies where schemaname = 'public' and tablename = 'alerts' and cmd in ('UPDATE', 'ALL')) = 1
      and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'alerts'
                  and cmd = 'UPDATE' and policyname = 'alerts_update_provider'),
      (select string_agg(policyname || ' (' || cmd || ')', ', ') from pg_policies where schemaname = 'public' and tablename = 'alerts'));
    r := r || pg_temp.ck('nobody has an UPDATE or INSERT grant on seen_by_patient_at (anon, authenticated)',
      not has_column_privilege('authenticated', 'public.alerts', 'seen_by_patient_at', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.alerts', 'seen_by_patient_at', 'INSERT')
      and not has_column_privilege('anon', 'public.alerts', 'seen_by_patient_at', 'UPDATE'));
    r := r || pg_temp.ck('no role has a DELETE grant on alerts',
      not has_table_privilege('authenticated', 'public.alerts', 'DELETE') and not has_table_privilege('anon', 'public.alerts', 'DELETE'));

    ---------------------------------------------------------------
    -- 3. A patient cannot change anything on an alert directly
    ---------------------------------------------------------------
    select to_jsonb(a) into snap from public.alerts a where a.id = a_fhr;

    r := r || pg_temp.ck('a patient cannot write seen_by_patient_at directly (permission denied)',
      pg_temp.x(format('update public.alerts set seen_by_patient_at = now() where id = %L', a_fhr), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient cannot change severity, alert_type, details or patient_id (permission denied)',
      pg_temp.x(format($q$update public.alerts set severity = 'info' where id = %L$q$, a_fhr), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$update public.alerts set alert_type = 'fever' where id = %L$q$, a_fhr), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$update public.alerts set details = '{}' where id = %L$q$, a_fhr), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.alerts set patient_id = %L where id = %L', pb, a_fhr), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient setting status = resolved on their OWN open alert changes 0 rows',
      pg_temp.cnt(format($q$with u as (update public.alerts set status = 'resolved' where id = %L returning 1) select count(*)::int from u$q$, a_fhr), pa) = 0);
    r := r || pg_temp.ck('a patient setting status = acknowledged on their own alert changes 0 rows',
      pg_temp.cnt(format($q$with u as (update public.alerts set status = 'acknowledged' where id = %L returning 1) select count(*)::int from u$q$, a_fhr), pa) = 0);
    r := r || pg_temp.ck('a patient cannot set acknowledged_by, acknowledged_at, action_taken or resolved_at (0 rows changed)',
      pg_temp.cnt(format('with u as (update public.alerts set acknowledged_by = %L where id = %L returning 1) select count(*)::int from u', pa, a_fhr), pa) = 0
      and pg_temp.cnt(format('with u as (update public.alerts set acknowledged_at = now() where id = %L returning 1) select count(*)::int from u', a_fhr), pa) = 0
      and pg_temp.cnt(format($q$with u as (update public.alerts set action_taken = 'call' where id = %L returning 1) select count(*)::int from u$q$, a_fhr), pa) = 0
      and pg_temp.cnt(format('with u as (update public.alerts set resolved_at = now() where id = %L returning 1) select count(*)::int from u', a_fhr), pa) = 0);
    r := r || pg_temp.ck('a patient cannot combine seen with status in one update (permission denied)',
      pg_temp.x(format($q$update public.alerts set seen_by_patient_at = now(), status = 'resolved' where id = %L$q$, a_fhr), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient cannot delete an alert (permission denied)',
      pg_temp.x(format('delete from public.alerts where id = %L', a_fhr), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient cannot insert an alert that is already marked seen, or a clinical alert (only their own SOS)',
      pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity, seen_by_patient_at) values (%L, 'sos', 'critical', now())$q$, pa), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'fever', 'info')$q$, pa), pa) like 'ERR 42501 new row violates row-level security%');
    select to_jsonb(a) into snap2 from public.alerts a where a.id = a_fhr;
    r := r || pg_temp.ck('after all those attempts the alert row is exactly as it was', snap = snap2, snap::text || ' vs ' || snap2::text);

    ---------------------------------------------------------------
    -- 4. mark_alert_seen: own alert, once
    ---------------------------------------------------------------
    home_before := pg_temp.home(pa);
    select count(*) into open_before from public.alerts where patient_id = pa and status = 'open' and acknowledged_by is null;
    snap := (select to_jsonb(a) - 'seen_by_patient_at' from public.alerts a where a.id = a_fhr);

    s := pg_temp.mark(pa, a_fhr);
    r := r || pg_temp.ck('a patient marks their own alert as seen: true', s = 'true', s);
    r := r || pg_temp.ck('the time is set by the server (within a few seconds of now())',
      exists (select 1 from public.alerts where id = a_fhr and abs(extract(epoch from (seen_by_patient_at - now()))) < 5));
    r := r || pg_temp.ck('only seen_by_patient_at changed: every other column of the alert is the same',
      snap = (select to_jsonb(a) - 'seen_by_patient_at' from public.alerts a where a.id = a_fhr));
    r := r || pg_temp.ck('the alert is still open and not acknowledged',
      exists (select 1 from public.alerts where id = a_fhr and status = 'open' and acknowledged_by is null
              and acknowledged_at is null and action_taken is null and resolved_at is null));

    -- now() is the same all through this test, so move the stored time to a known
    -- old value (as the database owner) to prove that a second call keeps it.
    update public.alerts set seen_by_patient_at = now() - interval '1 hour' where id = a_fhr;
    select seen_by_patient_at into t1 from public.alerts where id = a_fhr;
    s := pg_temp.mark(pa, a_fhr);
    r := r || pg_temp.ck('calling it a second time returns false', s = 'false', s);
    r := r || pg_temp.ck('and keeps the first time',
      (select seen_by_patient_at from public.alerts where id = a_fhr) = t1);

    home_after := pg_temp.home(pa);
    select count(*) into open_after from public.alerts where patient_id = pa and status = 'open' and acknowledged_by is null;
    r := r || pg_temp.ck('"seen" does not change the Home status', home_before is not distinct from home_after and home_before = 'urgent',
      coalesce(home_before, '-') || ' -> ' || coalesce(home_after, '-'));
    r := r || pg_temp.ck('"seen" does not change the provider queue (open, unacknowledged alerts of the patient)',
      open_before = open_after and open_after = 2, open_before::text || ' -> ' || open_after::text);

    -- A handled (acknowledged) alert and an SOS can be marked too; status stays.
    s := pg_temp.mark(pa, a_ack);
    r := r || pg_temp.ck('an acknowledged (handled) alert can be marked as seen and stays acknowledged',
      s = 'true' and exists (select 1 from public.alerts where id = a_ack and status = 'acknowledged'
                             and acknowledged_by = p1 and action_taken = 'call' and seen_by_patient_at is not null), s);
    s := pg_temp.mark(pa, a_sos);
    r := r || pg_temp.ck('an SOS can be marked as seen and stays open',
      s = 'true' and exists (select 1 from public.alerts where id = a_sos and status = 'open' and seen_by_patient_at is not null), s);

    ---------------------------------------------------------------
    -- 5. Not for anyone else's alert, not for a missing alert
    ---------------------------------------------------------------
    s := pg_temp.mark(pb, d_fhr);
    r := r || pg_temp.ck('patient B cannot mark patient D''s alert (false, nothing changed)',
      s = 'false' and exists (select 1 from public.alerts where id = d_fhr and seen_by_patient_at is null), s);
    -- A fresh, unseen alert of A to test against B
    insert into public.alerts (patient_id, alert_type, severity, details)
      values (pa, 'signal_loss', 'warning', '{"readings":3}') returning id into a_new;
    s := pg_temp.mark(pb, a_new);
    r := r || pg_temp.ck('patient B cannot mark patient A''s unseen alert (false, nothing changed)',
      s = 'false' and exists (select 1 from public.alerts where id = a_new and seen_by_patient_at is null), s);
    s := pg_temp.mark(pc, a_new);
    r := r || pg_temp.ck('a patient with no provider cannot mark patient A''s alert either', s = 'false'
      and exists (select 1 from public.alerts where id = a_new and seen_by_patient_at is null), s);
    r := r || pg_temp.ck('a missing alert id returns false (same answer as someone else''s alert)',
      pg_temp.mark(pa, gen_random_uuid()) = 'false');
    r := r || pg_temp.ck('a null alert id returns false', pg_temp.mark(pa, null) = 'false');
    s := pg_temp.mark(pa, a_new);
    r := r || pg_temp.ck('the owner can still mark that alert (true), so the false above was about ownership',
      s = 'true' and exists (select 1 from public.alerts where id = a_new and seen_by_patient_at is not null), s);

    ---------------------------------------------------------------
    -- 6. Providers: no write, but they can read it
    ---------------------------------------------------------------
    s := pg_temp.mark(p1, b_fhr);
    r := r || pg_temp.ck('an assigned provider cannot use mark_alert_seen for a patient (false, nothing changed)',
      s = 'false' and exists (select 1 from public.alerts where id = b_fhr and seen_by_patient_at is null), s);
    r := r || pg_temp.ck('a provider cannot write seen_by_patient_at directly (permission denied)',
      pg_temp.x(format('update public.alerts set seen_by_patient_at = now() where id = %L', b_fhr), p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a provider cannot insert an alert with seen_by_patient_at (permission denied)',
      pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity, seen_by_patient_at) values (%L, 'fever', 'info', now())$q$, pb), p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('the assigned provider can read when the patient marked it (the column is readable)',
      pg_temp.cnt(format('select count(*)::int from public.alerts where id = %L and seen_by_patient_at is not null', a_fhr), p1) = 1);
    r := r || pg_temp.ck('a provider can still acknowledge an assigned patient''s alert (no existing right was removed)',
      pg_temp.cnt(format($q$with u as (update public.alerts set status = 'acknowledged', acknowledged_by = %L, acknowledged_at = now(), action_taken = 'call' where id = %L returning 1) select count(*)::int from u$q$, p1, b_fhr), p1) = 1);
    r := r || pg_temp.ck('and after that the patient can still mark it as seen (true)', pg_temp.mark(pb, b_fhr) = 'true');

    ---------------------------------------------------------------
    -- 7. Who can see which alert (this is also what Realtime delivers)
    ---------------------------------------------------------------
    r := r || pg_temp.ck('patient A sees only their own alerts (4 rows incl. the new one), none of B, C or D',
      pg_temp.cnt(format('select count(*)::int from public.alerts where patient_id = %L', pa), pa) = 4
      and pg_temp.cnt('select count(*)::int from public.alerts', pa) = 4);
    r := r || pg_temp.ck('patient B cannot see patient A''s alerts (0 rows)',
      pg_temp.cnt(format('select count(*)::int from public.alerts where patient_id = %L', pa), pb) = 0);
    r := r || pg_temp.ck('the patient with no provider sees only their own alert',
      pg_temp.cnt('select count(*)::int from public.alerts', pc) = 1
      and pg_temp.cnt(format('select count(*)::int from public.alerts where id = %L', c_fhr), pc) = 1);
    r := r || pg_temp.ck('the unassigned patient''s alert is invisible to provider 1 (0 rows)',
      pg_temp.cnt(format('select count(*)::int from public.alerts where patient_id = %L', pc), p1) = 0);
    r := r || pg_temp.ck('the unassigned patient''s alert is invisible to provider 2 (0 rows)',
      pg_temp.cnt(format('select count(*)::int from public.alerts where patient_id = %L', pc), p2) = 0);
    r := r || pg_temp.ck('provider 1 sees A and B only (5 alerts), provider 2 sees D only (1 alert)',
      pg_temp.cnt('select count(*)::int from public.alerts', p1) = 5
      and pg_temp.cnt('select count(*)::int from public.alerts', p2) = 1);
    r := r || pg_temp.ck('provider 2 cannot see A''s alerts (0 rows)',
      pg_temp.cnt(format('select count(*)::int from public.alerts where patient_id = %L', pa), p2) = 0);
    r := r || pg_temp.ck('marking C''s alert as seen leaves it invisible to both providers',
      pg_temp.mark(pc, c_fhr) = 'true'
      and pg_temp.cnt(format('select count(*)::int from public.alerts where id = %L', c_fhr), p1) = 0
      and pg_temp.cnt(format('select count(*)::int from public.alerts where id = %L', c_fhr), p2) = 0);

    ---------------------------------------------------------------
    -- 8. anon gets nothing
    ---------------------------------------------------------------
    r := r || pg_temp.ck('anon cannot read alerts (permission denied)',
      pg_temp.x('select count(*) from public.alerts', null, 'anon') like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('anon cannot update or insert alerts (permission denied)',
      pg_temp.x(format('update public.alerts set seen_by_patient_at = now() where id = %L', a_fhr), null, 'anon') like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$insert into public.alerts (patient_id, alert_type, severity) values (%L, 'sos', 'critical')$q$, pa), null, 'anon') like 'ERR 42501 permission denied%');

    ---------------------------------------------------------------
    -- 9. Realtime
    ---------------------------------------------------------------
    r := r || pg_temp.ck('Realtime publishes alerts',
      exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'alerts'));
    r := r || pg_temp.ck('Realtime publishes ONLY alerts (belt_readings and maternal_vitals wait for Phase 5)',
      not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename <> 'alerts'),
      (select string_agg(tablename::text, ', ') from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public'));
    r := r || pg_temp.ck('the alerts publication sends inserts and updates (so a new alert and a "seen" change reach the app)',
      exists (select 1 from pg_publication where pubname = 'supabase_realtime' and pubinsert and pubupdate));
    r := r || pg_temp.ck('alerts keeps the default REPLICA IDENTITY (primary key), not FULL',
      (select relreplident from pg_class where oid = 'public.alerts'::regclass) = 'd');
    r := r || pg_temp.ck('signed-in users can SELECT alerts at table level (Realtime needs it), row access is still limited by the policy',
      has_table_privilege('authenticated', 'public.alerts', 'SELECT')
      and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'alerts' and policyname = 'alerts_select' and cmd = 'SELECT'));
    r := r || pg_temp.ck('the publication holds no other sensitive table',
      not exists (select 1 from pg_publication_tables pt where pt.pubname = 'supabase_realtime' and pt.schemaname = 'public'
                  and pt.tablename in ('audit_log', 'validation_pairs', 'consult_notes', 'provider_invites', 'app_settings',
                                       'deletion_requests', 'consent_records', 'consent_documents', 'alert_thresholds',
                                       'profiles', 'pregnancy_profiles')));

    -- Abort the block so every fake row above is rolled back. The report in r is kept.
    raise exception 'nl_rollback' using errcode = 'NL999';
  exception
    when sqlstate 'NL999' then
      null;
  end;

  r := r || ('INFO|Realtime cannot be proven by a SQL file: do the two-device check in the Manual Steps (a new alert for one patient must appear live for that patient only)|')::text;

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')::text
    into pass_n, fail_n from unnest(r) e;
  return array['SUMMARY|' || pass_n || ' PASS, ' || fail_n || ' FAIL|' ||
               case when fail_n = '0' then 'patient alerts database rules hold' else 'send me every FAIL row' end] || r;
end
$fn$;

-- ---------------------------------------------------------------------
-- The report: SUMMARY first, then FAIL, then INFO, then PASS
-- ---------------------------------------------------------------------
select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_alert_tests()) with ordinality as x(e, o)
order by 1;
