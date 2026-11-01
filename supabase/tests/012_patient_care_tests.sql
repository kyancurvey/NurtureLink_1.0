-- =====================================================================
-- 012_patient_care_tests.sql
-- NurtureLink step 3.4: proves that migration 012 closes the appointment
-- gaps and does nothing more.
--
--   * Gaps closed (each one is a test that FAILS on the 005 policies):
--       - a patient cannot change starts_at or duration_minutes, directly, on
--         a requested appointment, a scheduled (confirmed) one, or while
--         cancelling
--       - a patient cannot flip a scheduled visit back to requested, cannot
--         set scheduled or completed, cannot reopen a cancelled one
--       - a patient cannot insert directly: not with their own provider, not
--         with no provider (patient10), not with someone else's provider,
--         not in the past, not 480 minutes long
--       - a patient cannot touch another patient's appointment
--       - no limit on requests, no time limits (now enforced by the functions)
--   * Exactly what a direct patient write does now: INSERT gives 42501 "new
--     row violates row-level security policy" (NOT "permission denied"),
--     UPDATE gives no error and 0 rows, DELETE gives 42501 "permission denied".
--   * request_appointment, cancel_my_appointment, request_reschedule and
--     my_provider_name: owner-only, provider from the assignment, 1 hour / 90
--     day limits (both edges), at most 3 open requests (past, confirmed and
--     cancelled rows do not count), no_provider, not_signed_in, same "false"
--     for someone else's, missing, past and closed appointments.
--   * Providers still can what Phase 4 needs: schedule, confirm, move and
--     complete for ASSIGNED patients only, and see only their patients.
--   * anon gets nothing. appointments is not in the Realtime publication.
--
-- ABOUT THE STATUS WORD "confirmed": there is no such status. The statuses are
-- requested, scheduled, completed and cancelled; "scheduled" means the
-- provider confirmed it. Trying 'confirmed' fails with 23514 (a CHECK
-- constraint), which proves NOTHING about row-level security, so every status
-- test below uses 'scheduled' or 'completed' (valid values), and one test
-- shows the 23514 on purpose.
--
-- HOW IT WORKS: like 011_patient_alerts_tests.sql. Clearly fake users (emails
-- end in ".invalid") and fake appointments are created inside ONE block that
-- is deliberately aborted at its end, so everything is rolled back (the report
-- survives). Each test switches to the role "authenticated" or "anon" with a
-- fake user's id in request.jwt.claims, like a real API request. Real data is
-- never changed.
--
-- OPTIONAL "BEFORE" RUN: you may run this file BEFORE migration 012 to see the
-- gaps. It does not stop early: many rows will FAIL (the function tests and
-- the "gap closed" tests), which proves the tests can detect the gaps. Only
-- the run AFTER 012 counts. (I could not run Postgres here, so I cannot give
-- you the exact number of FAIL rows before 012.)
--
-- NOT PROVEN BY THESE SQL TESTS: simultaneous-request timing. This file runs in
-- ONE database session, so it cannot send two requests at the same moment and
-- cannot show that they cannot both slip under the limit of 3. request_appointment
-- locks the patient's own pregnancy_profiles row (FOR UPDATE) before it counts, so
-- parallel requests are counted one by one; that lock is the reason to trust it,
-- not a passing test. Also not proven here: the real Care screen (front end).
--
-- HOW TO RUN: run 012_patient_care.sql first. Paste this WHOLE file into a new
-- SQL Editor tab and click Run (if asked about "destructive operations",
-- click Run: the file only creates temporary functions; the fake data is
-- rolled back). Result: one table, SUMMARY first, then FAIL, INFO, PASS.
-- Expected after 012: "N PASS, 0 FAIL".
-- WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and every FAIL row.
--
-- DEPENDS ON: 000 to 012. READ-ONLY for your real data.
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

-- Run a query that returns ONE value (as text) as a role and fake user.
-- A null value comes back as '<null>'; an error as 'ERR <sqlstate> <message>'.
create or replace function pg_temp.s(p_sql text, p_uid uuid default null, p_role text default 'authenticated')
returns text
language plpgsql
as $fn$
declare
  v text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
  exception when others then
    reset role;
    return 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
  reset role;
  return coalesce(v, '<null>');
end
$fn$;

create or replace function pg_temp.ck(p_name text, p_ok boolean, p_detail text default '')
returns text
language sql
as $fn$
  select case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end || '|' || p_name || '|' ||
         case when coalesce(p_ok, false) then '' else coalesce(p_detail, '') end
$fn$;

-- Number of rows a signed-in user gets from a "select count(*)::int ..." query
-- (-1 on any error, so "= 0" means: no error AND no rows).
create or replace function pg_temp.cnt(p_sql text, p_uid uuid, p_role text default 'authenticated')
returns integer
language plpgsql
as $fn$
declare
  n integer;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  execute format('set local role %I', p_role);
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

-- text -> uuid, or null when the text is not a uuid (an 'ERR ...' result)
create or replace function pg_temp.asuuid(p_t text)
returns uuid
language sql
as $fn$
  select case when p_t ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p_t::uuid end
$fn$;

-- The four client functions, called as a signed-in user (p_uid null = signed in
-- with no user id) or as anon. Each returns the value as text or 'ERR ...'.
create or replace function pg_temp.req(p_uid uuid, p_ts timestamptz, p_role text default 'authenticated')
returns text
language sql
as $fn$
  select pg_temp.s(format('select public.request_appointment(%L)::text', p_ts), p_uid, p_role)
$fn$;

create or replace function pg_temp.can(p_uid uuid, p_id uuid, p_role text default 'authenticated')
returns text
language sql
as $fn$
  select pg_temp.s(format('select public.cancel_my_appointment(%L)::text', p_id), p_uid, p_role)
$fn$;

create or replace function pg_temp.rs(p_uid uuid, p_id uuid, p_ts timestamptz, p_role text default 'authenticated')
returns text
language sql
as $fn$
  select pg_temp.s(format('select public.request_reschedule(%L, %L)::text', p_id, p_ts), p_uid, p_role)
$fn$;

create or replace function pg_temp.pname(p_uid uuid, p_role text default 'authenticated')
returns text
language sql
as $fn$
  select pg_temp.s('select public.my_provider_name()', p_uid, p_role)
$fn$;

-- The rows with these ids as one json value (updated_at left out, it changes
-- whenever a row is touched). Read as the database owner.
create or replace function pg_temp.snap(p_ids uuid[])
returns jsonb
language sql
as $fn$
  select coalesce(jsonb_agg(to_jsonb(a) - 'updated_at' order by a.id), '[]'::jsonb)
  from public.appointments a where a.id = any (p_ids)
$fn$;

-- ---------------------------------------------------------------------
-- The tests
-- ---------------------------------------------------------------------
create or replace function pg_temp.nl_care_tests()
returns text[]
language plpgsql
as $fn$
declare
  r   text[] := '{}';
  pa  uuid := gen_random_uuid();   -- patient A, assigned to provider P1
  pb  uuid := gen_random_uuid();   -- patient B, assigned to provider P1
  pc  uuid := gen_random_uuid();   -- patient with NO provider (like patient10)
  pd  uuid := gen_random_uuid();   -- patient D, assigned to provider P2
  pe  uuid := gen_random_uuid();   -- patient E, "assigned" to an account that is NOT a provider (pb)
  pf  uuid := gen_random_uuid();   -- patient F, assigned to P1, no appointments (time limits)
  ph  uuid := gen_random_uuid();   -- patient H, assigned to P1 (limit of 3 open requests)
  pk  uuid := gen_random_uuid();   -- patient K, assigned to P1, no appointments (the first plain request test; A already has 4 open fixture rows, over the limit)
  p1  uuid := gen_random_uuid();   -- provider 1 (name with spaces around it)
  p2  uuid := gen_random_uuid();   -- provider 2 (blank name)
  -- A's appointments
  a_req      uuid := gen_random_uuid();  -- future requested: cancelled through the function
  a_req2     uuid := gen_random_uuid();  -- future requested: a provider tries the patient function
  a_req3     uuid := gen_random_uuid();  -- future requested: rescheduled through the function
  a_req4     uuid := gen_random_uuid();  -- future requested: provider confirms, moves, completes (A has 4 open fixture rows on purpose: more than the limit of 3 allows through the function)
  a_sch      uuid := gen_random_uuid();  -- future scheduled: patient cancels it
  a_sch2     uuid := gen_random_uuid();  -- future scheduled: direct attempts (the worst gap)
  a_sch3     uuid := gen_random_uuid();  -- future scheduled: reschedule refused
  a_past_sch uuid := gen_random_uuid();  -- past scheduled
  a_past_req uuid := gen_random_uuid();  -- past requested (never confirmed)
  a_done     uuid := gen_random_uuid();  -- past completed
  a_can      uuid := gen_random_uuid();  -- future cancelled
  -- others
  b_req uuid := gen_random_uuid();       -- B: future requested
  b_sch uuid := gen_random_uuid();       -- B: future scheduled
  c_req uuid := gen_random_uuid();       -- C (no provider): future requested, cancelled by C
  c_req2 uuid := gen_random_uuid();      -- C: future requested, rescheduled by C
  c_req3 uuid := gen_random_uuid();      -- C: future requested, a provider cannot touch it
  d_req uuid := gen_random_uuid();       -- D: future requested (provider P2)
  h_past_req uuid := gen_random_uuid();  -- H: past requested (does not count toward the limit)
  h_sch uuid := gen_random_uuid();       -- H: future scheduled (does not count)
  h_can uuid := gen_random_uuid();       -- H: future cancelled (does not count)
  v_id   uuid;
  v_id2  uuid;
  v_ts   timestamptz;
  snap   jsonb;
  snap2  jsonb;
  all_ids uuid[];
  s      text;
  n      integer;
  n1     integer;
  n2     integer;
  sig    text;
  fid    oid;
  pass_n integer;
  fail_n text;
begin
  begin   -- everything in this block is rolled back at the end

    ---------------------------------------------------------------
    -- Fake users, assignments and appointments
    ---------------------------------------------------------------
    insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
    select u, 'nl-care-' || u || '@nurturelink-test.invalid', now(), '{}'::jsonb
    from unnest(array[pa, pb, pc, pd, pe, pf, ph, pk, p1, p2]) u;
    update public.profiles set role = 'provider' where id in (p1, p2);
    update public.profiles set display_name = '  Test Provider One ' where id = p1;
    update public.profiles set display_name = '   ' where id = p2;
    insert into public.pregnancy_profiles (patient_id, assigned_provider_id, due_date) values
      (pa, p1, current_date + 100), (pb, p1, current_date + 100), (pc, null, current_date + 100),
      (pd, p2, current_date + 100), (pe, pb, current_date + 100), (pf, p1, current_date + 100),
      (ph, p1, current_date + 100), (pk, p1, current_date + 100);

    insert into public.appointments (id, patient_id, provider_id, starts_at, status) values
      (a_req,      pa, p1, now() + interval '10 days', 'requested'),
      (a_req2,     pa, p1, now() + interval '10 days', 'requested'),
      (a_req3,     pa, p1, now() + interval '10 days', 'requested'),
      (a_req4,     pa, p1, now() + interval '10 days', 'requested'),
      (a_sch,      pa, p1, now() + interval '11 days', 'scheduled'),
      (a_sch2,     pa, p1, now() + interval '11 days', 'scheduled'),
      (a_sch3,     pa, p1, now() + interval '11 days', 'scheduled'),
      (a_past_sch, pa, p1, now() - interval '2 days',  'scheduled'),
      (a_past_req, pa, p1, now() - interval '1 day',   'requested'),
      (a_done,     pa, p1, now() - interval '5 days',  'completed'),
      (a_can,      pa, p1, now() + interval '12 days', 'cancelled'),
      (b_req,      pb, p1, now() + interval '10 days', 'requested'),
      (b_sch,      pb, p1, now() + interval '11 days', 'scheduled'),
      (c_req,      pc, null, now() + interval '4 days', 'requested'),
      (c_req2,     pc, null, now() + interval '5 days', 'requested'),
      (c_req3,     pc, null, now() + interval '6 days', 'requested'),
      (d_req,      pd, p2, now() + interval '10 days', 'requested'),
      (h_past_req, ph, p1, now() - interval '1 day',   'requested'),
      (h_sch,      ph, p1, now() + interval '20 days', 'scheduled'),
      (h_can,      ph, p1, now() + interval '3 days',  'cancelled');

    all_ids := array[a_req, a_req2, a_req3, a_req4, a_sch, a_sch2, a_sch3, a_past_sch, a_past_req, a_done, a_can,
                     b_req, b_sch, c_req, c_req2, c_req3, d_req, h_past_req, h_sch, h_can];

    ---------------------------------------------------------------
    -- 0. The migration as built
    ---------------------------------------------------------------
    foreach sig in array array['public.request_appointment(timestamptz)', 'public.cancel_my_appointment(uuid)',
                               'public.request_reschedule(uuid,timestamptz)', 'public.my_provider_name()'] loop
      fid := to_regprocedure(sig);
      r := r || pg_temp.ck(sig || ' exists, is SECURITY DEFINER with a fixed search_path; PUBLIC and anon cannot execute; signed-in users can',
        fid is not null
        and exists (select 1 from pg_proc p where p.oid = fid and p.prosecdef
                    and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%'))
        and not exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                        where p.oid = fid and a.grantee = 0)
        and not has_function_privilege('anon', fid, 'execute')
        and has_function_privilege('authenticated', fid, 'execute'),
        'run supabase/migrations/012_patient_care.sql first');
    end loop;
    fid := to_regprocedure('public.appointment_time_check(timestamptz)');
    r := r || pg_temp.ck('the time-limit helper exists and NOBODY can run it from the API (PUBLIC, anon, signed-in)',
      fid is not null
      and not exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = fid and a.grantee = 0)
      and not has_function_privilege('anon', fid, 'execute')
      and not has_function_privilege('authenticated', fid, 'execute'),
      'run supabase/migrations/012_patient_care.sql first');
    r := r || pg_temp.ck('request_appointment takes ONE argument (the time): the client cannot send a provider; it returns uuid',
      exists (select 1 from pg_proc p where p.proname = 'request_appointment' and p.pronamespace = 'public'::regnamespace
              and p.pronargs = 1 and p.prorettype = 'uuid'::regtype));
    r := r || pg_temp.ck('my_provider_name takes no argument and returns a single text value',
      exists (select 1 from pg_proc p where p.proname = 'my_provider_name' and p.pronamespace = 'public'::regnamespace
              and p.pronargs = 0 and p.prorettype = 'text'::regtype));

    r := r || pg_temp.ck('NO patient policy is left on appointments (insert or update): only the provider ones remain',
      (select count(*) from pg_policies where schemaname = 'public' and tablename = 'appointments' and cmd in ('INSERT', 'ALL')) = 1
      and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'appointments'
                  and cmd = 'INSERT' and policyname = 'appointments_insert_provider')
      and (select count(*) from pg_policies where schemaname = 'public' and tablename = 'appointments' and cmd in ('UPDATE', 'ALL')) = 1
      and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'appointments'
                  and cmd = 'UPDATE' and policyname = 'appointments_update_provider')
      and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'appointments'
                      and policyname in ('appointments_insert_patient', 'appointments_update_patient')),
      (select string_agg(policyname || ' (' || cmd || ')', ', ') from pg_policies where schemaname = 'public' and tablename = 'appointments')
      || '  (if 005_rls.sql was run again after 012, run 012 again)');
    r := r || pg_temp.ck('appointments still has its select policy and no DELETE policy',
      exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'appointments' and policyname = 'appointments_select' and cmd = 'SELECT')
      and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'appointments' and cmd in ('DELETE', 'ALL')));
    r := r || pg_temp.ck('no grant changed: signed-in users keep INSERT and UPDATE on starts_at, duration_minutes and status (providers need them)',
      has_column_privilege('authenticated', 'public.appointments', 'starts_at', 'INSERT')
      and has_column_privilege('authenticated', 'public.appointments', 'duration_minutes', 'INSERT')
      and has_column_privilege('authenticated', 'public.appointments', 'status', 'INSERT')
      and has_column_privilege('authenticated', 'public.appointments', 'starts_at', 'UPDATE')
      and has_column_privilege('authenticated', 'public.appointments', 'duration_minutes', 'UPDATE')
      and has_column_privilege('authenticated', 'public.appointments', 'status', 'UPDATE'));
    r := r || pg_temp.ck('nobody can UPDATE patient_id or provider_id; no role has DELETE; anon has no privilege at all on appointments',
      not has_column_privilege('authenticated', 'public.appointments', 'patient_id', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.appointments', 'provider_id', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.appointments', 'DELETE')
      and not has_table_privilege('anon', 'public.appointments', 'DELETE')
      and not has_table_privilege('anon', 'public.appointments', 'SELECT')
      and not has_table_privilege('anon', 'public.appointments', 'INSERT')
      and not has_table_privilege('anon', 'public.appointments', 'UPDATE'));
    r := r || pg_temp.ck('appointments is NOT in the Realtime publication (the Care screen refetches instead)',
      not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'appointments'));

    -- The word "confirmed" is not a status: it fails on the CHECK constraint (23514).
    begin
      insert into public.appointments (patient_id, provider_id, starts_at, status)
        values (pa, p1, now() + interval '9 days', 'confirmed');
      s := 'inserted';
    exception when others then
      s := sqlstate;
    end;
    r := r || pg_temp.ck('status ''confirmed'' does not exist: it fails with 23514 (CHECK constraint), which proves nothing about RLS',
      s = '23514', s);
    r := r || ('INFO|the real statuses are requested, scheduled (= confirmed by the provider), completed and cancelled; every status test in this file uses scheduled or completed|')::text;

    ---------------------------------------------------------------
    -- 1. DIRECT patient writes (each test FAILS on the 005 policies)
    ---------------------------------------------------------------
    snap := pg_temp.snap(all_ids);
    n1 := (select count(*) from public.appointments where patient_id in (pa, pb, pc, pd, pe, pf, ph));

    -- INSERT: row-level security error, not "permission denied"
    s := pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at) values (%L, %L, now() + interval '3 days')$q$, pa, p1), pa);
    r := r || pg_temp.ck('a patient''s direct INSERT with their OWN provider gives 42501 "new row violates row-level security policy"',
      s like 'ERR 42501 new row violates row-level security%', s);
    r := r || pg_temp.ck('...and it is not a missing-grant error (the answer is not "permission denied")',
      s not like 'ERR 42501 permission denied%', s);
    s := pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at) values (%L, null, now() + interval '3 days')$q$, pa), pa);
    r := r || pg_temp.ck('a patient with a provider cannot insert directly with NO provider either', s like 'ERR 42501 new row violates row-level security%', s);
    s := pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at) values (%L, null, now() + interval '3 days')$q$, pc), pc);
    r := r || pg_temp.ck('patient C (no provider, like patient10) cannot insert directly', s like 'ERR 42501 new row violates row-level security%', s);
    s := pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at) values (%L, %L, now() + interval '3 days')$q$, pa, p2), pa);
    r := r || pg_temp.ck('a patient cannot insert directly with someone else''s provider id', s like 'ERR 42501 new row violates row-level security%', s);
    r := r || pg_temp.ck('a patient cannot insert directly as scheduled or completed (valid statuses, so this is RLS, not a CHECK)',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '3 days', 'scheduled')$q$, pa, p1), pa) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '3 days', 'completed')$q$, pa, p1), pa) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('a patient cannot insert directly with a 480-minute duration, a past time or a time in the year 3000',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, duration_minutes) values (%L, %L, now() + interval '3 days', 480)$q$, pa, p1), pa) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at) values (%L, %L, now() - interval '3 days')$q$, pa, p1), pa) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at) values (%L, %L, timestamptz '3000-01-01 00:00:00+00')$q$, pa, p1), pa) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('a patient cannot insert directly for ANOTHER patient',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at) values (%L, %L, now() + interval '3 days')$q$, pb, p1), pa) like 'ERR 42501 new row violates row-level security%');

    -- UPDATE: no error, 0 rows (pg_temp.cnt gives -1 on an error, so "= 0" means no error AND no row)
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'cancelled' where id = %L returning 1) select count(*)::int from u$q$, a_req), pa);
    r := r || pg_temp.ck('a patient''s direct UPDATE (cancel their own requested row) gives no error and 0 rows: cancelling goes through the function', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'scheduled' where id = %L returning 1) select count(*)::int from u$q$, a_req), pa);
    r := r || pg_temp.ck('a patient cannot set status = scheduled (confirm) on their own requested appointment (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'completed' where id = %L returning 1) select count(*)::int from u$q$, a_req), pa);
    r := r || pg_temp.ck('a patient cannot set status = completed on their own appointment (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'completed' where id = %L returning 1) select count(*)::int from u$q$, a_sch2), pa);
    r := r || pg_temp.ck('a patient cannot set status = completed on their own scheduled (confirmed) appointment (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'requested', starts_at = now() + interval '2 days' where id = %L returning 1) select count(*)::int from u$q$, a_sch2), pa);
    r := r || pg_temp.ck('THE WORST GAP: a patient cannot flip a scheduled (confirmed) visit back to requested AND change its time (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'requested' where id = %L returning 1) select count(*)::int from u$q$, a_sch2), pa);
    r := r || pg_temp.ck('...nor flip it back to requested alone (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set starts_at = now() + interval '20 days' where id = %L returning 1) select count(*)::int from u$q$, a_sch2), pa);
    r := r || pg_temp.ck('a patient cannot change starts_at of a scheduled (confirmed) appointment directly (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set starts_at = now() + interval '20 days' where id = %L returning 1) select count(*)::int from u$q$, a_req), pa);
    r := r || pg_temp.ck('a patient cannot change starts_at of their own REQUESTED appointment directly: rescheduling goes through the function (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set starts_at = now() - interval '20 days' where id = %L returning 1) select count(*)::int from u$q$, a_req), pa);
    r := r || pg_temp.ck('...including a time in the past (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set duration_minutes = 480 where id = %L returning 1) select count(*)::int from u$q$, a_req), pa);
    r := r || pg_temp.ck('a patient cannot change duration_minutes of a requested appointment (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set duration_minutes = 480 where id = %L returning 1) select count(*)::int from u$q$, a_sch2), pa);
    r := r || pg_temp.ck('a patient cannot change duration_minutes of a scheduled appointment (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'cancelled', starts_at = now() + interval '40 days', duration_minutes = 480 where id = %L returning 1) select count(*)::int from u$q$, a_sch2), pa);
    r := r || pg_temp.ck('a patient cannot change the time or duration WHILE cancelling (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'cancelled' where id = %L returning 1) select count(*)::int from u$q$, a_past_sch), pa);
    r := r || pg_temp.ck('a patient cannot cancel a PAST scheduled visit directly (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'requested' where id = %L returning 1) select count(*)::int from u$q$, a_can), pa);
    r := r || pg_temp.ck('a patient cannot reopen a cancelled appointment (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'requested' where id = %L returning 1) select count(*)::int from u$q$, a_done), pa);
    r := r || pg_temp.ck('a patient cannot reopen a completed appointment (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'cancelled' where id in (%L, %L) returning 1) select count(*)::int from u$q$, b_req, b_sch), pa);
    r := r || pg_temp.ck('a patient cannot change another patient''s appointments directly (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set starts_at = now() + interval '30 days' where patient_id = %L returning 1) select count(*)::int from u$q$, pb), pa);
    r := r || pg_temp.ck('...nor move them (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'cancelled' where id = %L returning 1) select count(*)::int from u$q$, c_req), pc);
    r := r || pg_temp.ck('a patient with no provider cannot cancel their own request directly either (0 rows; they use the function)', n = 0, 'rows: ' || n);
    r := r || pg_temp.ck('a patient cannot change patient_id or provider_id (permission denied: no column grant)',
      pg_temp.x(format('update public.appointments set patient_id = %L where id = %L', pb, a_req), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.appointments set provider_id = %L where id = %L', p2, a_req), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient cannot delete an appointment (permission denied)',
      pg_temp.x(format('delete from public.appointments where id = %L', a_req), pa) like 'ERR 42501 permission denied%');

    snap2 := pg_temp.snap(all_ids);
    r := r || pg_temp.ck('after all those direct attempts every fake appointment is exactly as it was', snap = snap2, 'a row changed');
    n2 := (select count(*) from public.appointments where patient_id in (pa, pb, pc, pd, pe, pf, ph));
    r := r || pg_temp.ck('...and no appointment was added', n1 = n2, n1::text || ' -> ' || n2::text);

    ---------------------------------------------------------------
    -- 2. request_appointment
    ---------------------------------------------------------------
    v_ts := now() + interval '2 days';
    s := pg_temp.req(pk, v_ts);
    v_id := pg_temp.asuuid(s);
    r := r || pg_temp.ck('a patient requests an appointment: the function returns the new id', v_id is not null, s);
    r := r || pg_temp.ck('the new row is the patient''s, with THEIR assigned provider, status requested, the requested time and 30 minutes',
      exists (select 1 from public.appointments where id = v_id and patient_id = pk and provider_id = p1
                and status = 'requested' and starts_at = v_ts and duration_minutes = 30));
    r := r || pg_temp.ck('the provider can see it (assigned provider P1 reads it)',
      pg_temp.cnt(format('select count(*)::int from public.appointments where id = %L', v_id), p1) = 1);
    r := r || pg_temp.ck('the patient can read it back',
      pg_temp.cnt(format('select count(*)::int from public.appointments where id = %L', v_id), pk) = 1);
    r := r || pg_temp.ck('another provider (P2) and another patient (B) cannot see it',
      pg_temp.cnt(format('select count(*)::int from public.appointments where id = %L', v_id), p2) = 0
      and pg_temp.cnt(format('select count(*)::int from public.appointments where id = %L', v_id), pb) = 0);
    s := pg_temp.req(pd, now() + interval '2 days');
    v_id2 := pg_temp.asuuid(s);
    r := r || pg_temp.ck('a patient of provider P2 gets P2 on the request, never P1',
      v_id2 is not null and exists (select 1 from public.appointments where id = v_id2 and patient_id = pd and provider_id = p2), s);

    n1 := (select count(*) from public.appointments where patient_id = pc);
    s := pg_temp.req(pc, now() + interval '2 days');
    r := r || pg_temp.ck('patient C with NO provider (like patient10) gets no_provider', s = 'ERR P0001 no_provider', s);
    r := r || pg_temp.ck('...and nothing was created for them', (select count(*) from public.appointments where patient_id = pc) = n1);
    s := pg_temp.req(pe, now() + interval '2 days');
    r := r || pg_temp.ck('a patient whose assigned account is NOT a provider gets no_provider too', s = 'ERR P0001 no_provider', s);
    s := pg_temp.req(p1, now() + interval '2 days');
    r := r || pg_temp.ck('a provider cannot use it to create a request (no_provider, nothing created)',
      s = 'ERR P0001 no_provider' and not exists (select 1 from public.appointments where patient_id = p1), s);
    s := pg_temp.req(null, now() + interval '2 days');
    r := r || pg_temp.ck('signed in with no user id gets not_signed_in', s = 'ERR P0001 not_signed_in', s);
    s := pg_temp.req(null, now() + interval '2 days', 'anon');
    r := r || pg_temp.ck('anon gets permission denied for the function', s like 'ERR 42501 permission denied for function%', s);
    s := pg_temp.req(pa, null);
    r := r || pg_temp.ck('a null time gets appointment_time_invalid', s = 'ERR P0001 appointment_time_invalid', s);

    -- Time limits, with patient F (no other appointments)
    r := r || pg_temp.ck('1 second short of 1 hour ahead gets appointment_too_soon',
      pg_temp.req(pf, now() + interval '1 hour' - interval '1 second') = 'ERR P0001 appointment_too_soon');
    r := r || pg_temp.ck('a time in the past or -infinity gets appointment_too_soon',
      pg_temp.req(pf, now() - interval '1 day') = 'ERR P0001 appointment_too_soon'
      and pg_temp.req(pf, '-infinity'::timestamptz) = 'ERR P0001 appointment_too_soon');
    r := r || pg_temp.ck('1 second past 90 days ahead gets appointment_too_far',
      pg_temp.req(pf, now() + interval '90 days' + interval '1 second') = 'ERR P0001 appointment_too_far');
    r := r || pg_temp.ck('the year 3000 or infinity gets appointment_too_far',
      pg_temp.req(pf, timestamptz '3000-01-01 00:00:00+00') = 'ERR P0001 appointment_too_far'
      and pg_temp.req(pf, 'infinity'::timestamptz) = 'ERR P0001 appointment_too_far');
    r := r || pg_temp.ck('none of those rejected requests created a row', (select count(*) from public.appointments where patient_id = pf) = 0);
    r := r || pg_temp.ck('exactly 1 hour ahead is allowed (lower edge)', pg_temp.asuuid(pg_temp.req(pf, now() + interval '1 hour')) is not null);
    r := r || pg_temp.ck('exactly 90 days ahead is allowed (upper edge)', pg_temp.asuuid(pg_temp.req(pf, now() + interval '90 days')) is not null);

    -- At most 3 OPEN requests, with patient H (also has a past requested, a future scheduled and a cancelled row)
    v_id := pg_temp.asuuid(pg_temp.req(ph, now() + interval '3 days'));
    r := r || pg_temp.ck('request 1 of 3 works (a past requested, a scheduled and a cancelled row do not count)', v_id is not null);
    r := r || pg_temp.ck('request 2 of 3 works', pg_temp.asuuid(pg_temp.req(ph, now() + interval '4 days')) is not null);
    r := r || pg_temp.ck('request 3 of 3 works', pg_temp.asuuid(pg_temp.req(ph, now() + interval '5 days')) is not null);
    s := pg_temp.req(ph, now() + interval '6 days');
    r := r || pg_temp.ck('the 4th open request gets too_many_open_requests', s = 'ERR P0001 too_many_open_requests', s);
    r := r || pg_temp.ck('...and exactly 3 future requested rows exist for that patient',
      (select count(*) from public.appointments where patient_id = ph and status = 'requested' and starts_at > now()) = 3);
    r := r || pg_temp.ck('a bad time is still reported as a time error, before the limit',
      pg_temp.req(ph, now() + interval '30 minutes') = 'ERR P0001 appointment_too_soon');
    r := r || pg_temp.ck('the limit is per patient: patient D (2 open) can still make a third',
      pg_temp.asuuid(pg_temp.req(pd, now() + interval '7 days')) is not null);
    s := pg_temp.can(ph, v_id);
    r := r || pg_temp.ck('cancelling one open request frees a place', s = 'true', s);
    r := r || pg_temp.ck('...so one more request works', pg_temp.asuuid(pg_temp.req(ph, now() + interval '6 days')) is not null);
    r := r || pg_temp.ck('...and then the limit holds again', pg_temp.req(ph, now() + interval '8 days') = 'ERR P0001 too_many_open_requests');

    ---------------------------------------------------------------
    -- 3. cancel_my_appointment
    ---------------------------------------------------------------
    snap := pg_temp.snap(array[a_req]);
    s := pg_temp.can(pa, a_req);
    r := r || pg_temp.ck('a patient cancels their own future requested appointment: true', s = 'true', s);
    r := r || pg_temp.ck('only status changed to cancelled (time, duration, provider, patient are the same)',
      exists (select 1 from public.appointments where id = a_req and status = 'cancelled')
      and (select (to_jsonb(a) - 'updated_at' - 'status') from public.appointments a where a.id = a_req)
        = ((snap -> 0) - 'status'));
    r := r || pg_temp.ck('the assigned provider sees it as cancelled',
      pg_temp.cnt(format($q$select count(*)::int from public.appointments where id = %L and status = 'cancelled'$q$, a_req), p1) = 1);
    s := pg_temp.can(pa, a_req);
    r := r || pg_temp.ck('cancelling it again returns false', s = 'false', s);

    s := pg_temp.can(pa, a_sch);
    r := r || pg_temp.ck('a patient can cancel their own FUTURE scheduled (confirmed) visit: true, status cancelled',
      s = 'true' and exists (select 1 from public.appointments where id = a_sch and status = 'cancelled'), s);

    snap := pg_temp.snap(array[a_past_sch, a_past_req, a_done, a_can, b_req, b_sch, d_req]);
    r := r || pg_temp.ck('cancelling a PAST scheduled visit returns false', pg_temp.can(pa, a_past_sch) = 'false');
    r := r || pg_temp.ck('cancelling a PAST requested row returns false', pg_temp.can(pa, a_past_req) = 'false');
    r := r || pg_temp.ck('cancelling a completed appointment returns false', pg_temp.can(pa, a_done) = 'false');
    r := r || pg_temp.ck('cancelling an already cancelled appointment returns false', pg_temp.can(pa, a_can) = 'false');
    r := r || pg_temp.ck('patient A cannot cancel patient B''s requested or scheduled appointment (false)',
      pg_temp.can(pa, b_req) = 'false' and pg_temp.can(pa, b_sch) = 'false');
    r := r || pg_temp.ck('patient A cannot cancel patient D''s appointment (false)', pg_temp.can(pa, d_req) = 'false');
    r := r || pg_temp.ck('a missing id and a null id return false (same answer as someone else''s)',
      pg_temp.can(pa, gen_random_uuid()) = 'false' and pg_temp.can(pa, null) = 'false');
    r := r || pg_temp.ck('after all those false answers the rows are exactly as they were',
      snap = pg_temp.snap(array[a_past_sch, a_past_req, a_done, a_can, b_req, b_sch, d_req]));

    s := pg_temp.can(pc, c_req);
    r := r || pg_temp.ck('a patient with no provider can cancel their own request (the demo row for patient10 can be cancelled by them)',
      s = 'true' and exists (select 1 from public.appointments where id = c_req and status = 'cancelled' and provider_id is null), s);
    s := pg_temp.can(p1, a_req2);
    r := r || pg_temp.ck('a provider cannot use the patient function on a patient''s appointment (false, unchanged)',
      s = 'false' and exists (select 1 from public.appointments where id = a_req2 and status = 'requested'), s);
    r := r || pg_temp.ck('cancel: no user id gets not_signed_in; anon gets permission denied',
      pg_temp.can(null, a_req2) = 'ERR P0001 not_signed_in'
      and pg_temp.can(null, a_req2, 'anon') like 'ERR 42501 permission denied for function%');

    ---------------------------------------------------------------
    -- 4. request_reschedule
    ---------------------------------------------------------------
    v_ts := now() + interval '5 days';
    s := pg_temp.rs(pa, a_req3, v_ts);
    r := r || pg_temp.ck('a patient moves their own future requested appointment: true', s = 'true', s);
    r := r || pg_temp.ck('the time changed; it is still requested; same provider, patient and duration; same row',
      exists (select 1 from public.appointments where id = a_req3 and starts_at = v_ts and status = 'requested'
                and provider_id = p1 and patient_id = pa and duration_minutes = 30));
    r := r || pg_temp.ck('a time under 1 hour away gets appointment_too_soon and changes nothing',
      pg_temp.rs(pa, a_req3, now() + interval '30 minutes') = 'ERR P0001 appointment_too_soon'
      and (select starts_at from public.appointments where id = a_req3) = v_ts);
    r := r || pg_temp.ck('a time more than 90 days away gets appointment_too_far and changes nothing',
      pg_temp.rs(pa, a_req3, now() + interval '91 days') = 'ERR P0001 appointment_too_far'
      and (select starts_at from public.appointments where id = a_req3) = v_ts);
    r := r || pg_temp.ck('a null time gets appointment_time_invalid',
      pg_temp.rs(pa, a_req3, null) = 'ERR P0001 appointment_time_invalid');
    r := r || pg_temp.ck('the 1 hour and 90 day edges are allowed when rescheduling',
      pg_temp.rs(pa, a_req3, now() + interval '1 hour') = 'true' and pg_temp.rs(pa, a_req3, now() + interval '90 days') = 'true');

    snap := pg_temp.snap(array[a_sch3, a_past_req, a_done, a_can, b_req, b_sch, d_req]);
    v_ts := (select starts_at from public.appointments where id = a_sch3);
    s := pg_temp.rs(pa, a_sch3, now() + interval '15 days');
    r := r || pg_temp.ck('IT CANNOT MOVE A SCHEDULED (CONFIRMED) APPOINTMENT: false, time and status unchanged',
      s = 'false' and exists (select 1 from public.appointments where id = a_sch3 and status = 'scheduled' and starts_at = v_ts), s);
    r := r || pg_temp.ck('it cannot move a past requested, a completed or a cancelled appointment (false)',
      pg_temp.rs(pa, a_past_req, now() + interval '15 days') = 'false'
      and pg_temp.rs(pa, a_done, now() + interval '15 days') = 'false'
      and pg_temp.rs(pa, a_can, now() + interval '15 days') = 'false');
    r := r || pg_temp.ck('patient A cannot move patient B''s requested or scheduled appointment, or patient D''s (false)',
      pg_temp.rs(pa, b_req, now() + interval '15 days') = 'false'
      and pg_temp.rs(pa, b_sch, now() + interval '15 days') = 'false'
      and pg_temp.rs(pa, d_req, now() + interval '15 days') = 'false');
    r := r || pg_temp.ck('a provider cannot use the patient function on a patient''s request (false)',
      pg_temp.rs(p1, b_req, now() + interval '15 days') = 'false');
    r := r || pg_temp.ck('a missing id and a null id return false',
      pg_temp.rs(pa, gen_random_uuid(), now() + interval '15 days') = 'false'
      and pg_temp.rs(pa, null, now() + interval '15 days') = 'false');
    r := r || pg_temp.ck('after all those false answers the rows are exactly as they were',
      snap = pg_temp.snap(array[a_sch3, a_past_req, a_done, a_can, b_req, b_sch, d_req]));
    r := r || pg_temp.ck('a bad time gives the same time error for someone else''s id (no information about other ids)',
      pg_temp.rs(pa, b_req, now() + interval '30 minutes') = 'ERR P0001 appointment_too_soon');
    s := pg_temp.rs(pc, c_req2, now() + interval '9 days');
    r := r || pg_temp.ck('a patient with no provider can move their own requested appointment (true)',
      s = 'true' and exists (select 1 from public.appointments where id = c_req2 and provider_id is null and status = 'requested'), s);
    r := r || pg_temp.ck('reschedule: no user id gets not_signed_in; anon gets permission denied',
      pg_temp.rs(null, a_req3, now() + interval '3 days') = 'ERR P0001 not_signed_in'
      and pg_temp.rs(null, a_req3, now() + interval '3 days', 'anon') like 'ERR 42501 permission denied for function%');

    ---------------------------------------------------------------
    -- 5. Providers still can what Phase 4 needs, for assigned patients only
    ---------------------------------------------------------------
    r := r || pg_temp.ck('provider P1 schedules a confirmed appointment for their patients A and B (insert ok)',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '5 days', 'scheduled')$q$, pa, p1), p1) = 'ok'
      and pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '5 days', 'scheduled')$q$, pb, p1), p1) = 'ok');
    r := r || pg_temp.ck('...but not for patient D (provider P2''s) or for patient C (nobody''s)',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '5 days', 'scheduled')$q$, pd, p1), p1) like 'ERR 42501 new row violates row-level security%'
      and pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '5 days', 'scheduled')$q$, pc, p1), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('...and not in another provider''s name',
      pg_temp.x(format($q$insert into public.appointments (patient_id, provider_id, starts_at, status) values (%L, %L, now() + interval '5 days', 'scheduled')$q$, pa, p2), p1) like 'ERR 42501 new row violates row-level security%');
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'scheduled' where id = %L returning 1) select count(*)::int from u$q$, a_req4), p1);
    r := r || pg_temp.ck('provider P1 confirms an assigned patient''s requested appointment (1 row)', n = 1, 'rows: ' || n);
    r := r || pg_temp.ck('...and the patient sees it as scheduled (confirmed)',
      pg_temp.cnt(format($q$select count(*)::int from public.appointments where id = %L and status = 'scheduled'$q$, a_req4), pa) = 1);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set starts_at = now() + interval '6 days' where id = %L returning 1) select count(*)::int from u$q$, a_req4), p1);
    r := r || pg_temp.ck('provider P1 can set the time of an assigned patient''s appointment (1 row)', n = 1, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'completed' where id = %L returning 1) select count(*)::int from u$q$, a_req4), p1);
    r := r || pg_temp.ck('provider P1 completes it (1 row)', n = 1, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'scheduled' where id in (%L, %L) returning 1) select count(*)::int from u$q$, d_req, c_req3), p1);
    r := r || pg_temp.ck('provider P1 cannot confirm patient D''s or patient C''s request (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set starts_at = now() + interval '8 days' where id in (%L, %L) returning 1) select count(*)::int from u$q$, d_req, c_req3), p1);
    r := r || pg_temp.ck('provider P1 cannot move patient D''s or patient C''s appointment (0 rows)', n = 0, 'rows: ' || n);
    n := pg_temp.cnt(format($q$with u as (update public.appointments set status = 'scheduled' where patient_id = %L returning 1) select count(*)::int from u$q$, pa), p2);
    r := r || pg_temp.ck('provider P2 cannot change patient A''s appointments (0 rows)', n = 0, 'rows: ' || n);
    r := r || pg_temp.ck('a provider cannot change patient_id or provider_id, and cannot delete (permission denied)',
      pg_temp.x(format('update public.appointments set provider_id = %L where id = %L', p2, b_req), p1) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.appointments set patient_id = %L where id = %L', pa, b_req), p1) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('delete from public.appointments where id = %L', b_req), p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('P1 sees all of A''s and B''s appointments and none of C''s or D''s',
      pg_temp.cnt(format('select count(*)::int from public.appointments where patient_id = %L', pa), p1) = (select count(*) from public.appointments where patient_id = pa)
      and pg_temp.cnt(format('select count(*)::int from public.appointments where patient_id = %L', pb), p1) = (select count(*) from public.appointments where patient_id = pb)
      and pg_temp.cnt(format('select count(*)::int from public.appointments where patient_id in (%L, %L)', pc, pd), p1) = 0);
    r := r || pg_temp.ck('P2 sees D''s appointments and none of A''s',
      pg_temp.cnt(format('select count(*)::int from public.appointments where patient_id = %L', pd), p2) = (select count(*) from public.appointments where patient_id = pd)
      and pg_temp.cnt(format('select count(*)::int from public.appointments where patient_id = %L', pa), p2) = 0);

    ---------------------------------------------------------------
    -- 6. Patients read only their own appointments
    ---------------------------------------------------------------
    r := r || pg_temp.ck('patient A sees exactly their own appointments, nobody else''s',
      pg_temp.cnt('select count(*)::int from public.appointments', pa) = (select count(*) from public.appointments where patient_id = pa)
      and pg_temp.cnt(format('select count(*)::int from public.appointments where patient_id <> %L', pa), pa) = 0);
    r := r || pg_temp.ck('patient C (no provider) sees only their own rows, and no provider sees them',
      pg_temp.cnt('select count(*)::int from public.appointments', pc) = (select count(*) from public.appointments where patient_id = pc)
      and pg_temp.cnt(format('select count(*)::int from public.appointments where patient_id = %L', pc), p1) = 0
      and pg_temp.cnt(format('select count(*)::int from public.appointments where patient_id = %L', pc), p2) = 0);

    ---------------------------------------------------------------
    -- 7. my_provider_name
    ---------------------------------------------------------------
    s := pg_temp.pname(pa);
    r := r || pg_temp.ck('a patient gets their provider''s display name, trimmed', s = 'Test Provider One', s);
    r := r || pg_temp.ck('another patient of the same provider gets the same name', pg_temp.pname(pb) = 'Test Provider One');
    r := r || pg_temp.ck('a provider with a blank name gives null', pg_temp.pname(pd) = '<null>', pg_temp.pname(pd));
    r := r || pg_temp.ck('a patient with no provider gets null', pg_temp.pname(pc) = '<null>', pg_temp.pname(pc));
    r := r || pg_temp.ck('a patient assigned to an account that is not a provider gets null', pg_temp.pname(pe) = '<null>', pg_temp.pname(pe));
    r := r || pg_temp.ck('a provider calling it gets null (no assignment of their own)', pg_temp.pname(p1) = '<null>', pg_temp.pname(p1));
    r := r || pg_temp.ck('it answers only for the caller: patient D never gets provider P1''s name',
      pg_temp.pname(pd) <> 'Test Provider One' and pg_temp.pname(pc) <> 'Test Provider One');
    r := r || pg_temp.ck('no user id gets not_signed_in; anon gets permission denied',
      pg_temp.pname(null) = 'ERR P0001 not_signed_in'
      and pg_temp.pname(null, 'anon') like 'ERR 42501 permission denied for function%');
    r := r || pg_temp.ck('patients still cannot read provider profiles directly (0 rows): the function is the only door',
      pg_temp.cnt(format('select count(*)::int from public.profiles where id = %L', p1), pa) = 0);

    ---------------------------------------------------------------
    -- 8. anon gets nothing; the helper is closed to everybody
    ---------------------------------------------------------------
    r := r || pg_temp.ck('anon cannot read, insert, update or delete appointments (permission denied)',
      pg_temp.x('select count(*) from public.appointments', null, 'anon') like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$insert into public.appointments (patient_id, starts_at) values (%L, now() + interval '3 days')$q$, pa), null, 'anon') like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$update public.appointments set status = 'cancelled' where id = %L$q$, a_req2), null, 'anon') like 'ERR 42501 permission denied%'
      and pg_temp.x(format('delete from public.appointments where id = %L', a_req2), null, 'anon') like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('neither anon nor a signed-in user can run the time-limit helper directly (permission denied)',
      pg_temp.x('select public.appointment_time_check(now() + interval ''1 day'')', null, 'anon') like 'ERR 42501 permission denied for function%'
      and pg_temp.x('select public.appointment_time_check(now() + interval ''1 day'')', pa) like 'ERR 42501 permission denied for function%');

    -- Abort the block so every fake row above is rolled back. The report in r is kept.
    raise exception 'nl_rollback' using errcode = 'NL999';
  exception
    when sqlstate 'NL999' then
      null;
  end;

  r := r || ('INFO|the limit of 3 open requests under two requests at the very same moment cannot be proven by a SQL file (one session); request_appointment locks the patient''s pregnancy_profiles row first so they are counted one by one|')::text;
  r := r || ('INFO|the Care screen itself is not covered here: do the Manual Steps|')::text;

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')::text
    into pass_n, fail_n from unnest(r) e;
  return array['SUMMARY|' || pass_n || ' PASS, ' || fail_n || ' FAIL|' ||
               case when fail_n = '0' then 'patient care database rules hold' else 'send me every FAIL row' end] || r;
end
$fn$;

-- ---------------------------------------------------------------------
-- The report: SUMMARY first, then FAIL, then INFO, then PASS
-- ---------------------------------------------------------------------
select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_care_tests()) with ordinality as x(e, o)
order by 1;
