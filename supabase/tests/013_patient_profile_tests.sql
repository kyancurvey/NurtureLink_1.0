-- =====================================================================
-- 013_patient_profile_tests.sql
-- NurtureLink step 3.5: proves that migration 013 makes set_my_display_name and
-- save_pregnancy_details the ONLY client write paths for a display name and the
-- pregnancy details, and that they apply their rules.
--
--   * Grants: authenticated cannot UPDATE profiles.display_name; keeps UPDATE on
--     language; has SELECT only on pregnancy_profiles (no INSERT or UPDATE on any
--     column, assigned_provider_id included). anon has nothing.
--   * set_my_display_name: caller only; blank or null clears (no error); too long
--     (over 100 after trimming), control, line-break, zero-width and
--     text-direction characters raise display_name_invalid; markup characters are
--     stored literally; anon cannot call it; not_signed_in; no_profile.
--   * save_pregnancy_details: creates the row for a patient who has none, updates
--     it for one who has; calling twice never makes a second row or an error;
--     never changes assigned_provider_id; a provider calling it only affects the
--     provider's OWN row; due date window (14 days ago to 280 days ahead on the
--     Manila date, checked only when the value changes); history at most 1000
--     characters; conditions at most 10, 1 to 60 characters, duplicates ignoring
--     case dropped, NULL element refused; a refused call changes nothing;
--     markup characters stored literally; anon cannot call it.
--   * Direct writes: a patient and a provider get permission denied on INSERT and
--     UPDATE of pregnancy_profiles and on UPDATE of profiles.display_name.
--   * The paths that still write as the database owner keep working (ADMIN_SQL
--     snippet 5 pattern, display name set by the seed, the signup trigger).
--   * Language saving still works.
--
-- ALL LIMITS TESTED HERE ARE DRAFT, PENDING MEDICAL OFFICER.
--
-- HOW IT WORKS: like 012_patient_care_tests.sql. Clearly fake users (emails end
-- in ".invalid") are created inside ONE block that is deliberately aborted at its
-- end, so everything is rolled back (the report survives). Each test switches to
-- the role "authenticated" or "anon" with a fake user's id in request.jwt.claims,
-- like a real API request. Real data is never changed.
--
-- NOT PROVEN BY THIS FILE (I could not run Postgres when writing it):
--   - that this file or 013 run at all: the first live run is the first run. The
--     regular expressions in 013 use \u escapes inside brackets; if Postgres
--     rejects them the migration or the first bad-character test shows the error.
--   - two requests at the very same moment (one session only). The save is one
--     INSERT ... ON CONFLICT statement on a unique column, which is atomic.
--   - the Manila-date edge: the "280 days ahead" edge test only tells a Manila
--     date from a UTC date between 16:00 and 24:00 UTC.
--   - the Profile screen (front end): do the Manual Steps.
--
-- HOW TO RUN: run 013_patient_profile.sql first. Paste this WHOLE file into a new
-- SQL Editor tab and click Run (if asked about "destructive operations", click
-- Run: it only creates temporary functions; the fake data is rolled back).
-- Result: one table, SUMMARY first, then FAIL, INFO, PASS. Expected after 013:
-- "N PASS, 0 FAIL". WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and
-- every FAIL row (or the error text if the whole file stops with an error).
--
-- DEPENDS ON: 000 to 013. READ-ONLY for your real data.
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

-- Run a query that returns ONE value (as text). A null comes back as '<null>';
-- an error as 'ERR <sqlstate> <message>'.
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

-- set_my_display_name(p_name) as a signed-in user (p_uid null = signed in, no id) or any role.
create or replace function pg_temp.sdn(p_uid uuid, p_name text, p_role text default 'authenticated')
returns text
language sql
as $fn$
  select pg_temp.s(format('select public.set_my_display_name(%L)', p_name), p_uid, p_role)
$fn$;

-- save_pregnancy_details as a user. p_conds is SQL text for the array, for example
-- 'array[''a'',''b'']::text[]' or 'null::text[]'.
create or replace function pg_temp.sv(p_uid uuid, p_due text, p_hist text, p_conds text, p_role text default 'authenticated')
returns text
language sql
as $fn$
  select pg_temp.x(format('select public.save_pregnancy_details(%L::date, %L::text, %s)', p_due, p_hist, p_conds), p_uid, p_role)
$fn$;

-- The pregnancy row of a patient as json (updated_at left out), read as the owner.
create or replace function pg_temp.row_of(p_uid uuid)
returns jsonb
language sql
as $fn$
  select coalesce((select to_jsonb(pp) - 'updated_at' from public.pregnancy_profiles pp where pp.patient_id = p_uid), 'null'::jsonb)
$fn$;

-- The stored display name, read as the owner ('<null>' when empty).
create or replace function pg_temp.dn(p_uid uuid)
returns text
language sql
as $fn$
  select coalesce((select coalesce(display_name, '<null>') from public.profiles where id = p_uid), '<no profile>')
$fn$;

-- IMPORTANT (same-statement snapshot): a plain "select ... from public.x" written in the
-- SAME expression after a call that writes would still see the OLD rows (the calling
-- statement keeps its snapshot). So every read that follows a write goes through these
-- volatile helper functions, which take a fresh snapshot of their own.
-- ppv: one expression evaluated on the patient's pregnancy row, as text
-- ('<none>' when there is no row, '<null>' when the value is null).
create or replace function pg_temp.ppv(p_uid uuid, p_expr text)
returns text
language plpgsql
as $fn$
declare
  v text;
begin
  execute format('select coalesce((%s)::text, ''<null>'') from public.pregnancy_profiles where patient_id = %L', p_expr, p_uid) into v;
  return coalesce(v, '<none>');
end
$fn$;

-- ok: is that expression true on the patient's row?
create or replace function pg_temp.ok(p_uid uuid, p_expr text)
returns boolean
language sql
as $fn$
  select pg_temp.ppv(p_uid, p_expr) = 'true'
$fn$;

-- number of pregnancy rows the patient has (0 or 1)
create or replace function pg_temp.nrows(p_uid uuid)
returns integer
language plpgsql
as $fn$
declare
  n integer;
begin
  select count(*) into n from public.pregnancy_profiles where patient_id = p_uid;
  return n;
end
$fn$;

-- SQL text for an array of N distinct short conditions: c1, c2, ...
create or replace function pg_temp.many(p_n integer)
returns text
language sql
as $fn$
  select 'array[' || string_agg(quote_literal('c' || g), ',' order by g) || ']::text[]' from generate_series(1, p_n) g
$fn$;

-- ---------------------------------------------------------------------
-- The tests
-- ---------------------------------------------------------------------
create or replace function pg_temp.nl_profile_tests()
returns text[]
language plpgsql
as $fn$
declare
  r   text[] := '{}';
  v_today date := (now() at time zone 'Asia/Manila')::date;
  pa  uuid := gen_random_uuid();   -- patient A: has a pregnancy row, assigned to P1
  pb  uuid := gen_random_uuid();   -- patient B: has a row, assigned to P1 (must never change)
  pc  uuid := gen_random_uuid();   -- patient C: has a row, NO provider (like patient10)
  pn  uuid := gen_random_uuid();   -- patient N: NO row yet (a brand-new patient)
  pm  uuid := gen_random_uuid();   -- patient M: no row; the admin assigns a provider first (snippet 5), then M saves
  pq  uuid := gen_random_uuid();   -- patient Q: has a row with an OLD due date outside the window
  pr  uuid := gen_random_uuid();   -- patient R: bounds tests (history and conditions)
  p1  uuid := gen_random_uuid();   -- provider 1
  p2  uuid := gen_random_uuid();   -- provider 2 (not assigned to anyone)
  snap_a  jsonb;
  snap_b  jsonb;
  snap_c  jsonb;
  snap_r  jsonb;
  sig     text;
  fid     oid;
  bad     integer[] := array[9, 10, 13, 127, 133, 1564, 6158, 8203, 8204, 8205, 8206, 8207, 8232, 8233, 8234, 8238, 8288, 8294, 8297, 65279];
  c       integer;
  pass_n  integer;
  fail_n  text;
begin
  begin   -- everything in this block is rolled back at the end

    ---------------------------------------------------------------
    -- Fake users and rows (created as the database owner)
    ---------------------------------------------------------------
    insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
    select u, 'nl-prof-' || u || '@nurturelink-test.invalid', now(), '{}'::jsonb
    from unnest(array[pa, pb, pc, pn, pm, pq, pr, p1, p2]) u;
    update public.profiles set role = 'provider' where id in (p1, p2);
    update public.profiles set display_name = 'Bea B' where id = pb;
    insert into public.pregnancy_profiles (patient_id, assigned_provider_id, due_date, obstetric_history, conditions) values
      (pa, p1, v_today + 100, 'old history', array['x']),
      (pb, p1, v_today + 100, 'B history', array['b']),
      (pc, null, v_today + 100, null, '{}'),
      (pq, null, v_today - 100, 'old date', '{}'),
      (pr, null, v_today + 100, null, '{}');
    snap_b := pg_temp.row_of(pb);
    snap_c := pg_temp.row_of(pc);

    ---------------------------------------------------------------
    -- 0. The migration as built
    ---------------------------------------------------------------
    foreach sig in array array['public.set_my_display_name(text)', 'public.save_pregnancy_details(date,text,text[])'] loop
      fid := to_regprocedure(sig);
      r := r || pg_temp.ck(sig || ' exists, is SECURITY DEFINER with a fixed search_path; PUBLIC and anon cannot execute; signed-in users can',
        fid is not null
        and exists (select 1 from pg_proc p where p.oid = fid and p.prosecdef
                    and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%'))
        and not has_function_privilege('anon', fid, 'EXECUTE')
        and not has_function_privilege('public', fid, 'EXECUTE')
        and has_function_privilege('authenticated', fid, 'EXECUTE'));
    end loop;
    foreach sig in array array['public.text_has_bad_chars(text,boolean)', 'public.nl_trim_text(text)'] loop
      fid := to_regprocedure(sig);
      r := r || pg_temp.ck(sig || ' exists and nobody can run it from the API (anon, PUBLIC, signed-in)',
        fid is not null
        and not has_function_privilege('anon', fid, 'EXECUTE')
        and not has_function_privilege('public', fid, 'EXECUTE')
        and not has_function_privilege('authenticated', fid, 'EXECUTE'));
    end loop;
    r := r || pg_temp.ck('neither function takes an id: they can only act on the caller',
      (select string_agg(pg_get_function_arguments(p.oid), ' | ' order by p.proname)
         from pg_proc p where p.oid in (to_regprocedure('public.set_my_display_name(text)'), to_regprocedure('public.save_pregnancy_details(date,text,text[])')))
        !~* 'uuid');
    r := r || pg_temp.ck('profiles: display_name is NOT updatable by signed-in users; language still is; role and date_of_birth are not',
      not has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE')
      and has_column_privilege('authenticated', 'public.profiles', 'language', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')
      and not has_column_privilege('authenticated', 'public.profiles', 'date_of_birth', 'UPDATE')
      and not has_table_privilege('anon', 'public.profiles', 'SELECT,INSERT,UPDATE,DELETE'));
    r := r || pg_temp.ck('pregnancy_profiles: signed-in users have SELECT and nothing else, on the table or on any single column',
      has_table_privilege('authenticated', 'public.pregnancy_profiles', 'SELECT')
      and not has_table_privilege('authenticated', 'public.pregnancy_profiles', 'INSERT,UPDATE,DELETE,TRUNCATE')
      and not exists (select 1 from pg_attribute a
                      where a.attrelid = 'public.pregnancy_profiles'::regclass and a.attnum > 0 and not a.attisdropped
                        and has_column_privilege('authenticated', 'public.pregnancy_profiles', a.attname::text, 'INSERT,UPDATE')),
      (select string_agg(a.attname, ', ') from pg_attribute a
        where a.attrelid = 'public.pregnancy_profiles'::regclass and a.attnum > 0 and not a.attisdropped
          and has_column_privilege('authenticated', 'public.pregnancy_profiles', a.attname::text, 'INSERT,UPDATE')));
    r := r || pg_temp.ck('assigned_provider_id cannot be written by signed-in users on any path (no column privilege)',
      not has_column_privilege('authenticated', 'public.pregnancy_profiles', 'assigned_provider_id', 'INSERT')
      and not has_column_privilege('authenticated', 'public.pregnancy_profiles', 'assigned_provider_id', 'UPDATE'));
    r := r || pg_temp.ck('anon has no privilege on pregnancy_profiles',
      not has_table_privilege('anon', 'public.pregnancy_profiles', 'SELECT,INSERT,UPDATE,DELETE')
      and pg_temp.x('select count(*) from public.pregnancy_profiles', null, 'anon') like 'ERR 42501 permission denied%');

    -- the helper, run as the owner: each refused class, the newline option, plain text
    r := r || pg_temp.ck('helper text_has_bad_chars: plain, accented and markup text is fine',
      not public.text_has_bad_chars('Maria Jose N', false)
      and not public.text_has_bad_chars('Mar' || chr(237) || 'a Jos' || chr(233) || ' ' || chr(209), false)
      and not public.text_has_bad_chars('<b>x</b> & "q" ''z''', false)
      and not public.text_has_bad_chars(null, false));
    foreach c in array bad loop
      r := r || pg_temp.ck('helper text_has_bad_chars refuses U+' || to_hex(c) || ' (line breaks refused)',
        public.text_has_bad_chars('a' || chr(c) || 'b', false));
    end loop;
    r := r || pg_temp.ck('helper text_has_bad_chars with line breaks allowed: LF is fine, CR, tab and zero-width are not',
      not public.text_has_bad_chars('a' || chr(10) || 'b', true)
      and public.text_has_bad_chars('a' || chr(13) || 'b', true)
      and public.text_has_bad_chars('a' || chr(9) || 'b', true)
      and public.text_has_bad_chars('a' || chr(8203) || 'b', true)
      and public.text_has_bad_chars('a' || chr(8238) || 'b', true));
    r := r || pg_temp.ck('helper nl_trim_text trims spaces, tabs, line breaks and no-break spaces at both ends and keeps the inside',
      public.nl_trim_text(' ' || chr(160) || chr(9) || 'a  b' || chr(10) || ' ') = 'a  b' and public.nl_trim_text('   ') = '');

    ---------------------------------------------------------------
    -- 1. set_my_display_name
    ---------------------------------------------------------------
    r := r || pg_temp.ck('A sets a name: returned and stored', pg_temp.sdn(pa, 'Ana Reyes') = 'Ana Reyes' and pg_temp.dn(pa) = 'Ana Reyes');
    r := r || pg_temp.ck('only the caller changes: B name is untouched', pg_temp.dn(pb) = 'Bea B');
    r := r || pg_temp.ck('spaces at both ends are trimmed', pg_temp.sdn(pa, '   Ana   Reyes  ') = 'Ana   Reyes' and pg_temp.dn(pa) = 'Ana   Reyes');
    r := r || pg_temp.ck('no-break spaces at the ends are trimmed too', pg_temp.sdn(pa, chr(160) || 'Ana' || chr(160)) = 'Ana');
    r := r || pg_temp.ck('accents, Filipino and other scripts are kept',
      pg_temp.sdn(pa, 'Mar' || chr(237) || 'a Jos' || chr(233) || ' ' || chr(209) || ' ' || chr(26085) || chr(26412)) = 'Mar' || chr(237) || 'a Jos' || chr(233) || ' ' || chr(209) || ' ' || chr(26085) || chr(26412));
    r := r || pg_temp.ck('a blank name clears it: no error, stored as NULL',
      pg_temp.sdn(pa, 'Ana') = 'Ana' and pg_temp.sdn(pa, '    ') = '<null>' and pg_temp.dn(pa) = '<null>');
    r := r || pg_temp.ck('an empty text clears it too', pg_temp.sdn(pa, 'Ana') = 'Ana' and pg_temp.sdn(pa, '') = '<null>' and pg_temp.dn(pa) = '<null>');
    r := r || pg_temp.ck('null clears it too',
      pg_temp.sdn(pa, 'Ana') = 'Ana'
      and pg_temp.s('select public.set_my_display_name(null)', pa) = '<null>' and pg_temp.dn(pa) = '<null>');
    r := r || pg_temp.ck('clearing again when already empty is not an error', pg_temp.sdn(pa, '') = '<null>');
    r := r || pg_temp.ck('exactly 100 characters is accepted', pg_temp.sdn(pa, repeat('a', 100)) = repeat('a', 100));
    r := r || pg_temp.ck('101 characters is refused with display_name_invalid and the old name stays',
      pg_temp.sdn(pa, repeat('a', 101)) like 'ERR%display_name_invalid' and pg_temp.dn(pa) = repeat('a', 100));
    r := r || pg_temp.ck('100 characters plus spaces at the end is accepted (the length is counted after trimming)',
      pg_temp.sdn(pa, repeat('b', 100) || '     ') = repeat('b', 100));
    r := r || pg_temp.ck('a 101-character name with spaces around it is still refused', pg_temp.sdn(pa, '  ' || repeat('c', 101) || '  ') like 'ERR%display_name_invalid');
    r := r || pg_temp.ck('a name that is too long never reaches the stored name', pg_temp.dn(pa) = repeat('b', 100));
    -- bad characters, each one tried in the middle, and at the start
    foreach c in array bad loop
      r := r || pg_temp.ck('name with U+' || to_hex(c) || ' in the middle is refused, name unchanged',
        pg_temp.sdn(pa, 'An' || chr(c) || 'a') like 'ERR%display_name_invalid' and pg_temp.dn(pa) = repeat('b', 100));
    end loop;
    r := r || pg_temp.ck('a line break at the start is refused, not trimmed away', pg_temp.sdn(pa, chr(10) || 'Ana') like 'ERR%display_name_invalid');
    r := r || pg_temp.ck('a name made only of a line break is refused (it is a bad character, not a blank)', pg_temp.sdn(pa, chr(10)) like 'ERR%display_name_invalid');
    r := r || pg_temp.ck('a name made only of a zero-width character is refused', pg_temp.sdn(pa, chr(8203)) like 'ERR%display_name_invalid');
    -- markup is stored literally
    r := r || pg_temp.ck('markup characters are stored exactly as typed (nothing escaped or stripped)',
      pg_temp.sdn(pa, '<b>Ana</b> & "Co" ''x'' <script>alert(1)</script>') = '<b>Ana</b> & "Co" ''x'' <script>alert(1)</script>'
      and pg_temp.dn(pa) = '<b>Ana</b> & "Co" ''x'' <script>alert(1)</script>');
    r := r || pg_temp.ck('an already-escaped text is not changed either (&lt; stays &lt;)', pg_temp.sdn(pa, '&lt;i&gt; &amp;') = '&lt;i&gt; &amp;' and pg_temp.dn(pa) = '&lt;i&gt; &amp;');
    -- who can call it
    r := r || pg_temp.ck('anon cannot call set_my_display_name (permission denied for function)',
      pg_temp.sdn(null, 'x', 'anon') like 'ERR 42501 permission denied for function%');
    r := r || pg_temp.ck('signed in without a user id: not_signed_in', pg_temp.sdn(null, 'x') like 'ERR%not_signed_in');
    r := r || pg_temp.ck('a user with no profile row: no_profile', pg_temp.sdn(gen_random_uuid(), 'x') like 'ERR%no_profile');
    -- provider uses the same function and only changes their own row
    r := r || pg_temp.ck('a provider sets their own name; A, B and P2 are not changed',
      pg_temp.sdn(p1, '  Dr. Test One ') = 'Dr. Test One' and pg_temp.dn(p1) = 'Dr. Test One'
      and pg_temp.dn(pa) = '&lt;i&gt; &amp;' and pg_temp.dn(pb) = 'Bea B' and pg_temp.dn(p2) = '<null>');
    r := r || pg_temp.ck('the assigned provider reads the patient name as stored; an unassigned provider reads nothing',
      pg_temp.s(format('select display_name from public.profiles where id = %L', pa), p1) = '&lt;i&gt; &amp;'
      and pg_temp.cnt(format('select count(*)::int from public.profiles where id = %L', pa), p2) = 0);
    r := r || pg_temp.ck('my_provider_name() shows the new provider name to the patient (012 and 013 fit together)',
      pg_temp.s('select public.my_provider_name()', pa) = 'Dr. Test One');
    -- the old direct path is closed
    r := r || pg_temp.ck('a patient cannot update display_name directly (permission denied)',
      pg_temp.x(format($q$update public.profiles set display_name = 'direct' where id = %L$q$, pa), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient cannot update ANOTHER profile directly either (permission denied, not 0 rows)',
      pg_temp.x(format($q$update public.profiles set display_name = 'direct' where id = %L$q$, pb), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a provider cannot update a patient display_name directly (permission denied)',
      pg_temp.x(format($q$update public.profiles set display_name = 'direct' where id = %L$q$, pa), p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('nobody changed a name by those attempts', pg_temp.dn(pa) = '&lt;i&gt; &amp;' and pg_temp.dn(pb) = 'Bea B');
    r := r || pg_temp.ck('anon cannot update display_name either', pg_temp.x(format($q$update public.profiles set display_name = 'direct' where id = %L$q$, pa), null, 'anon') like 'ERR 42501 permission denied%');
    -- language saving still works
    r := r || pg_temp.ck('language: the direct language update still works for the owner (1 row)',
      pg_temp.cnt(format($q$with u as (update public.profiles set language = 'fil' where id = %L returning 1) select count(*)::int from u$q$, pa), pa) = 1);
    r := r || pg_temp.ck('language: set_my_language still works and rejects an unknown language',
      pg_temp.x($q$select public.set_my_language('en')$q$, pa) = 'ok'
      and pg_temp.x($q$select public.set_my_language('xx')$q$, pa) like 'ERR%invalid_language%');
    r := r || pg_temp.ck('role is still protected: a patient cannot make themselves a provider', pg_temp.x(format($q$update public.profiles set role = 'provider' where id = %L$q$, pa), pa) like 'ERR 42501 permission denied%');

    ---------------------------------------------------------------
    -- 2. save_pregnancy_details: create, update, double submission
    ---------------------------------------------------------------
    r := r || pg_temp.ck('A saves valid details: ok, stored, provider still P1, still one row',
      pg_temp.sv(pa, (v_today + 100)::text, 'First baby', 'array[''Asthma'',''Anemia'']::text[]') = 'ok'
      and pg_temp.ok(pa, format('due_date = %L::date and obstetric_history = %L and conditions = array[''Asthma'',''Anemia''] and assigned_provider_id = %L', v_today + 100, 'First baby', p1))
      and pg_temp.nrows(pa) = 1);
    r := r || pg_temp.ck('a brand-new patient with no row: the first save creates it (provider NULL)',
      pg_temp.nrows(pn) = 0
      and pg_temp.sv(pn, (v_today + 60)::text, 'N history', 'array[''Asthma'']::text[]') = 'ok'
      and pg_temp.nrows(pn) = 1
      and pg_temp.ok(pn, format('assigned_provider_id is null and due_date = %L::date', v_today + 60)));
    snap_r := pg_temp.row_of(pn);
    r := r || pg_temp.ck('double submission: the same call twice gives ok both times, still one row, same content',
      pg_temp.sv(pn, (v_today + 60)::text, 'N history', 'array[''Asthma'']::text[]') = 'ok'
      and pg_temp.sv(pn, (v_today + 60)::text, 'N history', 'array[''Asthma'']::text[]') = 'ok'
      and pg_temp.nrows(pn) = 1
      and pg_temp.row_of(pn) = snap_r);
    r := r || pg_temp.ck('a second save with other values updates the same row (still one row)',
      pg_temp.sv(pn, (v_today + 70)::text, 'N history 2', 'array[''Anemia'']::text[]') = 'ok'
      and pg_temp.nrows(pn) = 1
      and pg_temp.ok(pn, format('due_date = %L::date and obstetric_history = %L', v_today + 70, 'N history 2')));
    r := r || pg_temp.ck('other patients rows are untouched by those saves (B and C)', pg_temp.row_of(pb) = snap_b and pg_temp.row_of(pc) = snap_c);
    r := r || pg_temp.ck('a patient without a provider stays without one after saving (C)',
      pg_temp.sv(pc, (v_today + 90)::text, 'C', 'array[]::text[]') = 'ok'
      and pg_temp.ok(pc, format('assigned_provider_id is null and due_date = %L::date', v_today + 90)));
    r := r || pg_temp.ck('assigned_provider_id is unchanged after many saves (A stays with P1)',
      pg_temp.sv(pa, null, null, 'null::text[]') = 'ok'
      and pg_temp.sv(pa, (v_today + 120)::text, 'again', 'array[''z'']::text[]') = 'ok'
      and pg_temp.ok(pa, format('assigned_provider_id = %L', p1)));
    -- the admin assigns first (ADMIN_SQL snippet 5, as the database owner), then the patient saves
    r := r || pg_temp.ck('ADMIN_SQL snippet 5 still works as the owner after 013 (insert ... on conflict do update of assigned_provider_id)',
      pg_temp.x(format('insert into public.pregnancy_profiles (patient_id, assigned_provider_id) values (%L, %L) on conflict (patient_id) do update set assigned_provider_id = excluded.assigned_provider_id', pm, p1), null, 'postgres') = 'ok'
      and pg_temp.ok(pm, format('assigned_provider_id = %L and due_date is null', p1)));
    r := r || pg_temp.ck('then the patient saves details and the admin assignment survives',
      pg_temp.sv(pm, (v_today + 30)::text, null, 'array[''Asthma'']::text[]') = 'ok'
      and pg_temp.ok(pm, format('assigned_provider_id = %L and due_date = %L::date', p1, v_today + 30))
      and pg_temp.nrows(pm) = 1);
    r := r || pg_temp.ck('the seed pattern still works as the owner (display name update, row insert on conflict do update of the three fields)',
      pg_temp.x(format($q$update public.profiles set display_name = 'Demo Patient 99' where id = %L$q$, pm), null, 'postgres') = 'ok'
      and pg_temp.x(format($q$insert into public.pregnancy_profiles (patient_id, due_date, obstetric_history, conditions) values (%L, current_date + 10, 'DEMO', '{}') on conflict (patient_id) do update set due_date = excluded.due_date, obstetric_history = excluded.obstetric_history$q$, pm), null, 'postgres') = 'ok'
      and pg_temp.dn(pm) = 'Demo Patient 99'
      and pg_temp.ok(pm, format('assigned_provider_id = %L and obstetric_history = %L', p1, 'DEMO')));
    r := r || pg_temp.ck('the signup trigger still creates the profile row for the fake users (they exist after the insert into auth.users)',
      (select count(*) from public.profiles where id in (pa, pb, pc, pn, pm, pq, pr, p1, p2)) = 9);

    -- providers
    snap_a := pg_temp.row_of(pa);
    r := r || pg_temp.ck('a provider calling save_pregnancy_details creates and changes only THEIR OWN row; A and B are untouched',
      pg_temp.sv(p1, (v_today + 40)::text, 'provider own', 'array[''own'']::text[]') = 'ok'
      and pg_temp.nrows(p1) = 1
      and pg_temp.ok(p1, 'assigned_provider_id is null and obstetric_history = ''provider own''')
      and pg_temp.row_of(pa) = snap_a and pg_temp.row_of(pb) = snap_b);
    r := r || pg_temp.ck('the same provider saving twice still leaves one row',
      pg_temp.sv(p1, (v_today + 41)::text, 'again', 'array[]::text[]') = 'ok'
      and pg_temp.nrows(p1) = 1);
    r := r || pg_temp.ck('reads still work: A reads own row, the assigned provider reads it, an unassigned provider and another patient read nothing',
      pg_temp.cnt(format('select count(*)::int from public.pregnancy_profiles where patient_id = %L', pa), pa) = 1
      and pg_temp.cnt(format('select count(*)::int from public.pregnancy_profiles where patient_id = %L', pa), p1) = 1
      and pg_temp.cnt(format('select count(*)::int from public.pregnancy_profiles where patient_id = %L', pa), p2) = 0
      and pg_temp.cnt(format('select count(*)::int from public.pregnancy_profiles where patient_id = %L', pa), pb) = 0);

    -- direct writes are closed
    snap_a := pg_temp.row_of(pa);
    r := r || pg_temp.ck('a patient cannot UPDATE their pregnancy row directly: due_date, history, conditions, provider (all permission denied)',
      pg_temp.x(format('update public.pregnancy_profiles set due_date = current_date where patient_id = %L', pa), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$update public.pregnancy_profiles set obstetric_history = 'x' where patient_id = %L$q$, pa), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$update public.pregnancy_profiles set conditions = array['x'] where patient_id = %L$q$, pa), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.pregnancy_profiles set assigned_provider_id = %L where patient_id = %L', p2, pa), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient cannot INSERT directly, with or without a provider (permission denied)',
      pg_temp.x(format('insert into public.pregnancy_profiles (patient_id) values (%L)', pa), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('insert into public.pregnancy_profiles (patient_id, due_date) values (%L, current_date + 10)', pa), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('insert into public.pregnancy_profiles (patient_id, assigned_provider_id) values (%L, %L)', pa, p1), pa) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('insert into public.pregnancy_profiles (patient_id) values (%L)', pb), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient cannot touch ANOTHER patient row directly (permission denied, not 0 rows)',
      pg_temp.x(format('update public.pregnancy_profiles set due_date = current_date where patient_id = %L', pb), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a patient cannot delete a pregnancy row (permission denied)',
      pg_temp.x(format('delete from public.pregnancy_profiles where patient_id = %L', pa), pa) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a provider cannot write a patient pregnancy row directly (A, assigned) or assign themselves (all permission denied)',
      pg_temp.x(format('update public.pregnancy_profiles set due_date = current_date where patient_id = %L', pa), p1) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.pregnancy_profiles set assigned_provider_id = %L where patient_id = %L', p1, pc), p1) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('insert into public.pregnancy_profiles (patient_id, assigned_provider_id) values (%L, %L)', pr, p1), p1) like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.pregnancy_profiles set due_date = current_date where patient_id = %L', pa), p2) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('none of those attempts changed a row (A, B, C)', pg_temp.row_of(pa) = snap_a and pg_temp.row_of(pb) = snap_b and pg_temp.ppv(pc, 'assigned_provider_id is null') = 'true');
    -- anon and signed-out
    r := r || pg_temp.ck('anon cannot call save_pregnancy_details (permission denied for function) and cannot write the table',
      pg_temp.sv(null, (v_today + 50)::text, 'x', 'array[]::text[]', 'anon') like 'ERR 42501 permission denied for function%'
      and pg_temp.x(format('insert into public.pregnancy_profiles (patient_id) values (%L)', pn), null, 'anon') like 'ERR 42501 permission denied%'
      and pg_temp.x(format('update public.pregnancy_profiles set due_date = current_date where patient_id = %L', pa), null, 'anon') like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('signed in without a user id: not_signed_in', pg_temp.sv(null, null, null, 'null::text[]') like 'ERR%not_signed_in');
    r := r || pg_temp.ck('anon and signed-out calls changed nothing', pg_temp.row_of(pa) = snap_a);

    ---------------------------------------------------------------
    -- 3. Due date window (Manila date; checked only when the value changes)
    ---------------------------------------------------------------
    r := r || pg_temp.ck('due date empty (null) is allowed and clears it',
      pg_temp.sv(pr, null, null, 'null::text[]') = 'ok' and pg_temp.ok(pr, 'due_date is null'));
    r := r || pg_temp.ck('due date today is allowed', pg_temp.sv(pr, v_today::text, null, 'null::text[]') = 'ok');
    r := r || pg_temp.ck('due date exactly 14 days ago is allowed (42w0d)', pg_temp.sv(pr, (v_today - 14)::text, null, 'null::text[]') = 'ok');
    r := r || pg_temp.ck('due date 15 days ago is refused: due_date_out_of_range, row unchanged',
      pg_temp.sv(pr, (v_today - 15)::text, 'must not be saved', 'array[''no'']::text[]') like 'ERR%due_date_out_of_range'
      and pg_temp.ok(pr, format('due_date = %L::date and obstetric_history is null', v_today - 14)));
    r := r || pg_temp.ck('due date exactly 280 days ahead is allowed (0w0d, on the Manila date)', pg_temp.sv(pr, (v_today + 280)::text, null, 'null::text[]') = 'ok');
    r := r || pg_temp.ck('due date 281 days ahead is refused: due_date_out_of_range', pg_temp.sv(pr, (v_today + 281)::text, null, 'null::text[]') like 'ERR%due_date_out_of_range');
    r := r || pg_temp.ck('a due date far in the past or far in the future is refused',
      pg_temp.sv(pr, '1900-01-01', null, 'null::text[]') like 'ERR%due_date_out_of_range'
      and pg_temp.sv(pr, '2999-12-31', null, 'null::text[]') like 'ERR%due_date_out_of_range');
    r := r || pg_temp.ck('a text that is not a real date (31 February) is refused with a database error, nothing saved',
      pg_temp.sv(pr, '2026-02-31', null, 'null::text[]') like 'ERR 22%');
    r := r || pg_temp.ck('after all those refusals the row still holds the last good due date',
      pg_temp.ok(pr, format('due_date = %L::date', v_today + 280)));
    r := r || pg_temp.ck('an OLD due date (100 days ago, outside the window) does not block editing other fields when the date is the same',
      pg_temp.sv(pq, (v_today - 100)::text, 'edited later', 'array[''late'']::text[]') = 'ok'
      and pg_temp.ok(pq, format('obstetric_history = %L and due_date = %L::date', 'edited later', v_today - 100)));
    r := r || pg_temp.ck('...but CHANGING it to another out-of-window date is refused',
      pg_temp.sv(pq, (v_today - 101)::text, 'x', 'array[]::text[]') like 'ERR%due_date_out_of_range'
      and pg_temp.ok(pq, format('due_date = %L::date and obstetric_history = %L', v_today - 100, 'edited later')));
    r := r || pg_temp.ck('...and changing it to a date inside the window works',
      pg_temp.sv(pq, (v_today + 5)::text, 'edited later', 'array[]::text[]') = 'ok'
      and pg_temp.ok(pq, format('due_date = %L::date', v_today + 5)));

    ---------------------------------------------------------------
    -- 4. Obstetric history
    ---------------------------------------------------------------
    r := r || pg_temp.ck('history of exactly 1000 characters is accepted',
      pg_temp.sv(pr, (v_today + 50)::text, repeat('h', 1000), 'array[]::text[]') = 'ok'
      and pg_temp.ok(pr, 'char_length(obstetric_history) = 1000'));
    r := r || pg_temp.ck('history of 1001 characters is refused: history_invalid, row unchanged',
      pg_temp.sv(pr, (v_today + 51)::text, repeat('h', 1001), 'array[]::text[]') like 'ERR%history_invalid'
      and pg_temp.ok(pr, format('char_length(obstetric_history) = 1000 and due_date = %L::date', v_today + 50)));
    r := r || pg_temp.ck('1000 characters with white space around them is accepted (counted after trimming)',
      pg_temp.sv(pr, (v_today + 50)::text, '   ' || repeat('h', 1000) || E'  \n ', 'array[]::text[]') = 'ok'
      and pg_temp.ok(pr, 'char_length(obstetric_history) = 1000'));
    r := r || pg_temp.ck('line breaks inside the history are kept (LF)',
      pg_temp.sv(pr, (v_today + 50)::text, E'line1\nline2\n\nline4', 'array[]::text[]') = 'ok'
      and pg_temp.ok(pr, format('obstetric_history = %L', E'line1\nline2\n\nline4')));
    r := r || pg_temp.ck('CRLF is stored as LF',
      pg_temp.sv(pr, (v_today + 50)::text, E'a\r\nb', 'array[]::text[]') = 'ok'
      and pg_temp.ok(pr, format('obstetric_history = %L', E'a\nb')));
    r := r || pg_temp.ck('a bare carriage return, a tab, a zero-width character, a direction override and a BOM are refused: history_invalid',
      pg_temp.sv(pr, (v_today + 50)::text, E'a\rb', 'array[]::text[]') like 'ERR%history_invalid'
      and pg_temp.sv(pr, (v_today + 50)::text, E'a\tb', 'array[]::text[]') like 'ERR%history_invalid'
      and pg_temp.sv(pr, (v_today + 50)::text, 'a' || chr(8203) || 'b', 'array[]::text[]') like 'ERR%history_invalid'
      and pg_temp.sv(pr, (v_today + 50)::text, 'a' || chr(8238) || 'b', 'array[]::text[]') like 'ERR%history_invalid'
      and pg_temp.sv(pr, (v_today + 50)::text, 'a' || chr(65279) || 'b', 'array[]::text[]') like 'ERR%history_invalid');
    r := r || pg_temp.ck('refused history calls left the last good history in place',
      pg_temp.ok(pr, format('obstetric_history = %L', E'a\nb')));
    r := r || pg_temp.ck('blank, empty and null history are stored as NULL (no error)',
      pg_temp.sv(pr, (v_today + 50)::text, '   ', 'array[]::text[]') = 'ok' and pg_temp.ok(pr, 'obstetric_history is null')
      and pg_temp.sv(pr, (v_today + 50)::text, 'x', 'array[]::text[]') = 'ok' and pg_temp.ok(pr, 'obstetric_history = ''x''')
      and pg_temp.sv(pr, (v_today + 50)::text, '', 'array[]::text[]') = 'ok' and pg_temp.ok(pr, 'obstetric_history is null')
      and pg_temp.sv(pr, (v_today + 50)::text, 'y', 'array[]::text[]') = 'ok'
      and pg_temp.sv(pr, (v_today + 50)::text, null, 'array[]::text[]') = 'ok' and pg_temp.ok(pr, 'obstetric_history is null'));
    r := r || pg_temp.ck('markup characters in the history are stored exactly as typed',
      pg_temp.sv(pr, (v_today + 50)::text, '<b>one</b> & "two" ''three'' <img src=x onerror=alert(1)> &lt;', 'array[]::text[]') = 'ok'
      and pg_temp.ok(pr, format('obstetric_history = %L', '<b>one</b> & "two" ''three'' <img src=x onerror=alert(1)> &lt;')));
    r := r || pg_temp.ck('accents and other scripts are kept in the history',
      pg_temp.sv(pr, (v_today + 50)::text, 'G1P0 ' || chr(241) || ' ' || chr(26085), 'array[]::text[]') = 'ok'
      and pg_temp.ok(pr, format('obstetric_history = %L', 'G1P0 ' || chr(241) || ' ' || chr(26085))));

    ---------------------------------------------------------------
    -- 5. Conditions
    ---------------------------------------------------------------
    r := r || pg_temp.ck('10 conditions are accepted',
      pg_temp.sv(pr, (v_today + 50)::text, null, pg_temp.many(10)) = 'ok' and pg_temp.ok(pr, 'cardinality(conditions) = 10'));
    r := r || pg_temp.ck('11 different conditions are refused: conditions_invalid, the 10 stay',
      pg_temp.sv(pr, (v_today + 50)::text, null, pg_temp.many(11)) like 'ERR%conditions_invalid'
      and pg_temp.ok(pr, 'cardinality(conditions) = 10'));
    r := r || pg_temp.ck('12 entries that clean down to 10 (two case-duplicates) are accepted',
      pg_temp.sv(pr, (v_today + 50)::text, null, 'array[''c1'',''c2'',''c3'',''c4'',''c5'',''c6'',''c7'',''c8'',''c9'',''c10'',''C1'',''c2'']::text[]') = 'ok'
      and pg_temp.ok(pr, 'cardinality(conditions) = 10'));
    r := r || pg_temp.ck('duplicates ignoring case are dropped, the first spelling stays, order is kept',
      pg_temp.sv(pr, (v_today + 50)::text, null, 'array[''Asthma'',''Anemia'',''asthma'',''ASTHMA'',''anemia'']::text[]') = 'ok'
      and pg_temp.ok(pr, 'conditions = array[''Asthma'',''Anemia'']'));
    r := r || pg_temp.ck('blank entries are dropped and entries are trimmed',
      pg_temp.sv(pr, (v_today + 50)::text, null, 'array['''',''   '',''  Diabetes  '','''']::text[]') = 'ok'
      and pg_temp.ok(pr, 'conditions = array[''Diabetes'']'));
    r := r || pg_temp.ck('an empty array and a null array both store an empty list',
      pg_temp.sv(pr, (v_today + 50)::text, null, 'array[]::text[]') = 'ok' and pg_temp.ok(pr, 'cardinality(conditions) = 0')
      and pg_temp.sv(pr, (v_today + 50)::text, null, 'array[''x'']::text[]') = 'ok'
      and pg_temp.sv(pr, (v_today + 50)::text, null, 'null::text[]') = 'ok' and pg_temp.ok(pr, 'conditions = ''{}'''));
    r := r || pg_temp.ck('an entry of exactly 60 characters is accepted',
      pg_temp.sv(pr, (v_today + 50)::text, null, format('array[%L]::text[]', repeat('k', 60))) = 'ok'
      and pg_temp.ok(pr, format('conditions = array[%L]', repeat('k', 60))));
    r := r || pg_temp.ck('an entry of 61 characters is refused: conditions_invalid, list unchanged',
      pg_temp.sv(pr, (v_today + 50)::text, null, format('array[''ok'',%L]::text[]', repeat('k', 61))) like 'ERR%conditions_invalid'
      and pg_temp.ok(pr, format('conditions = array[%L]', repeat('k', 60))));
    r := r || pg_temp.ck('a NULL element is refused: conditions_invalid', pg_temp.sv(pr, (v_today + 50)::text, null, 'array[''a'',null]::text[]') like 'ERR%conditions_invalid');
    r := r || pg_temp.ck('a tab, a line break, a zero-width character and a direction override inside an entry are refused',
      pg_temp.sv(pr, (v_today + 50)::text, null, format('array[%L]::text[]', 'a' || chr(9) || 'b')) like 'ERR%conditions_invalid'
      and pg_temp.sv(pr, (v_today + 50)::text, null, format('array[%L]::text[]', 'a' || chr(10) || 'b')) like 'ERR%conditions_invalid'
      and pg_temp.sv(pr, (v_today + 50)::text, null, format('array[%L]::text[]', 'a' || chr(8203) || 'b')) like 'ERR%conditions_invalid'
      and pg_temp.sv(pr, (v_today + 50)::text, null, format('array[%L]::text[]', 'a' || chr(8238) || 'b')) like 'ERR%conditions_invalid');
    r := r || pg_temp.ck('an absurdly long array (101 entries) is refused before it is processed',
      pg_temp.sv(pr, (v_today + 50)::text, null, (select 'array[' || string_agg('''z''', ',') || ']::text[]' from generate_series(1, 101))) like 'ERR%conditions_invalid');
    r := r || pg_temp.ck('markup characters in conditions are stored exactly as typed, in order',
      pg_temp.sv(pr, (v_today + 50)::text, null, format('array[%L,%L,%L,%L]::text[]', '<b>x</b>', 'a & b', '"q"', '&lt;')) = 'ok'
      and pg_temp.ok(pr, format('conditions = array[%L,%L,%L,%L]', '<b>x</b>', 'a & b', '"q"', '&lt;')));
    r := r || pg_temp.ck('a refused call is all-or-nothing: a good due date and history sent with a bad condition are NOT saved',
      pg_temp.sv(pr, (v_today + 77)::text, 'must not be saved', 'array[''ok'','''', null]::text[]') like 'ERR%conditions_invalid'
      and pg_temp.ok(pr, format('due_date = %L::date and obstetric_history is distinct from %L', v_today + 50, 'must not be saved')));

    -- the other patients are still exactly as they were
    r := r || pg_temp.ck('B row is still untouched at the end', pg_temp.row_of(pb) = snap_b);

    -- Abort the block so every fake row above is rolled back. The report in r is kept.
    raise exception 'nl_rollback' using errcode = 'NL999';
  exception
    when sqlstate 'NL999' then
      null;
  end;

  r := r || ('INFO|the regular expressions in 013 use \u escapes in brackets; this file is their first run, a Postgres error on the first bad-character test would mean they need a different spelling|')::text;
  r := r || ('INFO|the 280-day edge test tells a Manila date from a UTC date only between 16:00 and 24:00 UTC|')::text;
  r := r || ('INFO|two requests at the very same moment are not provable in one session; the save is one INSERT ... ON CONFLICT on a unique column|')::text;
  r := r || ('INFO|all limits tested here (due date window, 1000 characters, 10 conditions of 60 characters, 100-character name) are draft, pending medical officer|')::text;
  r := r || ('INFO|the Profile screen itself is not covered here: do the Manual Steps|')::text;

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')::text
    into pass_n, fail_n from unnest(r) e;
  return array['SUMMARY|' || pass_n || ' PASS, ' || fail_n || ' FAIL|' ||
               case when fail_n = '0' then 'profile write rules hold' else 'send me every FAIL row' end] || r;
end
$fn$;

-- ---------------------------------------------------------------------
-- The report: SUMMARY first, then FAIL, then INFO, then PASS
-- ---------------------------------------------------------------------
select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_profile_tests()) with ordinality as x(e, o)
order by 1;
