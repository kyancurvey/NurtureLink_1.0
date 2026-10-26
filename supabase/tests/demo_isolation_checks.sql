-- =====================================================================
-- demo_isolation_checks.sql
-- NurtureLink step 2.5: proves, on the REAL demo accounts created by
-- supabase/seed/demo_seed.sql, that
--   * a patient sees only their own data and nothing provider-only,
--   * a provider sees only the patients assigned to them,
--   * a patient with no provider is invisible to both providers,
--   * anon (not signed in) is refused on every table.
-- It is the real-data companion of access_tests.sql (which uses throw-away
-- fake users). Run it after the seed and after access_tests.sql.
--
-- HOW IT WORKS: like access_tests.sql, it switches the session to the role
-- "authenticated" (or "anon") with a demo user's id in request.jwt.claims,
-- exactly like a real API request, and counts what that user can see.
--
-- READ-ONLY: it changes nothing and saves nothing. Only temporary helper
-- functions are created (they vanish when the session ends).
--
-- HOW TO RUN: paste the WHOLE file into a new SQL Editor tab and click Run (if
-- asked about "destructive operations", click Run: there are none, only
-- temporary functions). Result: one table, SUMMARY first, then FAIL, INFO, PASS.
-- Expected: "29 PASS, 0 FAIL".
-- WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and every FAIL row.
--
-- DEPENDS ON: 000 to 008 and demo_seed.sql already run (it says so and stops
-- if the demo accounts are missing). SAFE TO RE-RUN: yes, any time. If you
-- have since assigned more patients to the demo providers, or handled alerts,
-- the checks still hold: they compare with what is really in the tables.
-- HOW TO UNDO: nothing to undo.
--
-- NOTE: the demo data has no consult notes and no validation pairs, so the
-- "patient sees 0 consult notes / validation pairs" lines are weak here; the
-- throw-away tests in access_tests.sql cover those with real rows.
-- =====================================================================

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

create or replace function pg_temp.nl_demo_checks()
returns text[]
language plpgsql
as $fn$
declare
  r        text[] := '{}';
  p        uuid[];                                   -- demo providers 1 and 2
  pat      uuid[];                                   -- demo patients 01 .. 10
  prov_of  int[] := array[1, 1, 1, 1, 1, 2, 2, 2, 2, 0];   -- expected provider of each patient (0 = none)
  i        int;
  j        int;
  me       uuid;
  tbl      text;
  n        int;
  own      int;
  ok       boolean;
  t1       int;
  t2       int;
  t3       int;
  pass_n   int;
  fail_n   int;
  seen     int;
  want     int;
  seen_list text;
begin
  select array_agg(u.id order by array_position(array['provider01@example.test', 'provider02@example.test'], lower(u.email)))
    into p
  from auth.users u
  where lower(u.email) in ('provider01@example.test', 'provider02@example.test');

  select array_agg(u.id order by u.email)
    into pat
  from auth.users u
  where lower(u.email) ~ '^patient(0[1-9]|10)@example\.test$';

  r := r || pg_temp.ck('all 12 demo accounts exist',
    coalesce(array_length(p, 1), 0) = 2 and coalesce(array_length(pat, 1), 0) = 10,
    'found ' || coalesce(array_length(p, 1), 0) || ' providers and ' || coalesce(array_length(pat, 1), 0)
      || ' patients; create the accounts and run supabase/seed/demo_seed.sql first');
  if coalesce(array_length(p, 1), 0) <> 2 or coalesce(array_length(pat, 1), 0) <> 10 then
    return array['SUMMARY|0 PASS, 1 FAIL|create the demo accounts and run the seed first'] || r;
  end if;

  ---------------------------------------------------------------
  -- Shape of the demo data
  ---------------------------------------------------------------
  r := r || pg_temp.ck('both demo providers have the role provider and all 10 demo patients have the role patient',
    (select count(*) from public.profiles where id = any (p) and role = 'provider') = 2
    and (select count(*) from public.profiles where id = any (pat) and role = 'patient') = 10);

  r := r || pg_temp.ck('exactly one demo patient is under 18, and it is patient07',
    (select count(*) from public.profiles
      where id = any (pat) and date_of_birth > current_date - interval '18 years') = 1
    and (select date_of_birth > current_date - interval '18 years' from public.profiles where id = pat[7]));

  r := r || pg_temp.ck('exactly one demo patient has no provider, and it is patient10',
    (select count(*) from public.pregnancy_profiles
      where patient_id = any (pat) and assigned_provider_id is null) = 1
    and (select assigned_provider_id is null from public.pregnancy_profiles where patient_id = pat[10]));

  select count(*) filter (where w < 14),
         count(*) filter (where w >= 14 and w < 28),
         count(*) filter (where w >= 28)
    into t1, t2, t3
  from (select 40 - ((pp.due_date - (now() at time zone 'Asia/Manila')::date) / 7) as w
        from public.pregnancy_profiles pp where pp.patient_id = any (pat)) x;
  r := r || ('INFO|trimesters today (1 / 2 / 3): ' || t1 || ' / ' || t2 || ' / ' || t3
             || ' (2 / 5 / 3 on the day of seeding; it moves as the weeks pass)|')::text;
  r := r || ('INFO|demo_mode is currently ' ||
             coalesce((select value from public.app_settings where key = 'demo_mode'), 'missing') || '|')::text;

  ---------------------------------------------------------------
  -- Per patient: who may see the record (provider side)
  ---------------------------------------------------------------
  for i in 1..10 loop
    me := pat[i];
    ok := true;
    for j in 1..2 loop
      n := pg_temp.q(format('select count(*)::int from public.profiles where id = %L', me), p[j]);
      ok := ok and n = case when prov_of[i] = j then 1 else 0 end;

      foreach tbl in array array['pregnancy_profiles', 'belt_readings', 'maternal_vitals', 'appointments', 'devices'] loop
        n := pg_temp.q(format('select count(*)::int from public.%I where patient_id = %L', tbl, me), p[j]);
        ok := ok and case when prov_of[i] = j then n >= 1 else n = 0 end;
      end loop;

      -- alerts: the other provider (and both providers for patient10) must see none
      n := pg_temp.q(format('select count(*)::int from public.alerts where patient_id = %L', me), p[j]);
      ok := ok and (prov_of[i] = j or n = 0);
    end loop;
    r := r || pg_temp.ck(format('patient%s: only the assigned provider can see the record', lpad(i::text, 2, '0')),
      ok, 'a provider saw a record they should not, or the assigned provider saw none');
  end loop;

  -- Plain list of what each provider can see (for reading, not a pass/fail check)
  for j in 1..2 loop
    seen_list := '';
    for i in 1..10 loop
      if pg_temp.q(format('select count(*)::int from public.pregnancy_profiles where patient_id = %L', pat[i]), p[j]) = 1 then
        seen_list := seen_list || case when seen_list = '' then '' else ', ' end || 'patient' || lpad(i::text, 2, '0');
      end if;
    end loop;
    r := r || ('INFO|provider0' || j || ' can see: ' || coalesce(nullif(seen_list, ''), '(nobody)')
               || ' (expected right after seeding: ' || case when j = 1 then 'patient01 to patient05' else 'patient06 to patient09' end || ')|')::text;
  end loop;

  ---------------------------------------------------------------
  -- Per patient: sees only their own data, nothing provider-only
  ---------------------------------------------------------------
  for i in 1..10 loop
    me := pat[i];
    ok := pg_temp.q('select count(*)::int from public.profiles', me) = 1
      and pg_temp.q('select count(*)::int from public.pregnancy_profiles', me) = 1;

    foreach tbl in array array['belt_readings', 'maternal_vitals', 'alerts', 'appointments', 'devices'] loop
      execute format('select count(*)::int from public.%I where patient_id = %L', tbl, me) into own;
      ok := ok
        and pg_temp.q(format('select count(*)::int from public.%I', tbl), me) = own
        and pg_temp.q(format('select count(*)::int from public.%I where patient_id <> %L', tbl, me), me) = 0;
    end loop;

    ok := ok
      and pg_temp.q('select count(*)::int from public.consult_notes', me) = 0
      and pg_temp.q('select count(*)::int from public.validation_pairs', me) = 0
      and pg_temp.q('select count(*)::int from public.alert_thresholds', me) = 0
      and pg_temp.x('select * from public.audit_log', me)        like 'ERR 42501 permission denied%'
      and pg_temp.x('select * from public.provider_invites', me) like 'ERR 42501 permission denied%'
      and pg_temp.x('select * from public.app_settings', me)     like 'ERR 42501 permission denied%'
      and pg_temp.q('select (public.is_provider() or public.is_admin())::int', me) = 0;
    r := r || pg_temp.ck(format('patient%s: sees only their own data and nothing provider-only', lpad(i::text, 2, '0')),
      ok, 'saw someone else''s rows, saw provider-only data, or reached a locked table');
  end loop;

  ---------------------------------------------------------------
  -- Providers: exactly their assigned patients, nothing admin-only
  ---------------------------------------------------------------
  for j in 1..2 loop
    select count(*) into want from public.pregnancy_profiles where assigned_provider_id = p[j];
    seen := pg_temp.q('select count(*)::int from public.pregnancy_profiles', p[j]);
    n    := pg_temp.q('select count(*)::int from public.profiles', p[j]);
    r := r || pg_temp.ck(format('provider0%s sees exactly the %s patients assigned to them (and their own profile)', j, want),
      seen = want and n = want + 1,
      'sees ' || seen || ' pregnancy profiles and ' || n || ' profiles, expected ' || want || ' and ' || (want + 1));
  end loop;

  r := r || pg_temp.ck('both providers are refused the audit log, provider invites and app settings (permission denied)',
    pg_temp.x('select * from public.audit_log', p[1])        like 'ERR 42501 permission denied%'
    and pg_temp.x('select * from public.provider_invites', p[1]) like 'ERR 42501 permission denied%'
    and pg_temp.x('select * from public.app_settings', p[1])     like 'ERR 42501 permission denied%'
    and pg_temp.x('select * from public.audit_log', p[2])        like 'ERR 42501 permission denied%'
    and pg_temp.x('select * from public.provider_invites', p[2]) like 'ERR 42501 permission denied%'
    and pg_temp.x('select * from public.app_settings', p[2])     like 'ERR 42501 permission denied%');

  -- Open alerts: each provider sees exactly the open alerts of their own patients
  ok := true;
  for j in 1..2 loop
    select count(*) into want
    from public.alerts a
    join public.pregnancy_profiles pp on pp.patient_id = a.patient_id
    where a.status = 'open' and pp.assigned_provider_id = p[j];
    seen := pg_temp.q('select count(*)::int from public.alerts where status = ''open''', p[j]);
    ok := ok and seen = want;
    r := r || ('INFO|provider0' || j || ' sees ' || seen || ' open alert(s); expected ' || want
               || ' (right after seeding: 1 for provider01, 3 for provider02)|')::text;
  end loop;
  r := r || pg_temp.ck('each provider sees exactly the open alerts of their own patients (patient10''s open alert is seen by neither)',
    ok and exists (select 1 from public.alerts where patient_id = pat[10])
       and pg_temp.q(format('select count(*)::int from public.alerts where patient_id = %L', pat[10]), p[1]) = 0
       and pg_temp.q(format('select count(*)::int from public.alerts where patient_id = %L', pat[10]), p[2]) = 0);

  ---------------------------------------------------------------
  -- anon: nothing, on every table
  ---------------------------------------------------------------
  ok := true;
  for tbl in select tablename from pg_tables where schemaname = 'public' order by 1 loop
    ok := ok and pg_temp.x(format('select * from public.%I', tbl), null, 'anon') like 'ERR 42501 permission denied%';
  end loop;
  r := r || pg_temp.ck('anon (not signed in) is refused on every table in public', ok);

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')
    into pass_n, fail_n from unnest(r) e;
  return array['SUMMARY|' || pass_n || ' PASS, ' || fail_n || ' FAIL|' ||
               case when fail_n = 0 then 'demo accounts are isolated as designed' else 'send me every FAIL row' end] || r;
end
$fn$;

select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_demo_checks()) with ordinality as x(e, o)
order by 1;
