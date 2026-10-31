-- =====================================================================
-- 011_manual_seen_check.sql
-- NurtureLink step 3.3: a quick live check of "Mark as seen" with the DEMO
-- accounts, as simulated patients and providers (like a real API request).
-- It proves, on your live project:
--   1. patient08 can mark their own open heart-rate alert as seen (true), once;
--      the second call returns false and keeps the first time;
--   2. patient08 cannot mark patient09's alert (false) and a provider cannot
--      mark a patient's alert (false);
--   3. patient08 setting status = 'resolved' on their own alert changes 0 rows,
--      and changing severity is "permission denied";
--   4. patient10's alert (no provider) is invisible to provider01 and provider02;
--   5. anon cannot call mark_alert_seen.
-- Everything is rolled back at the end: your real alerts are NOT changed, so
-- you can run it as often as you like and the app screens stay as they were.
--
-- HOW TO RUN: run 011_patient_alerts.sql and the demo seed first. Paste this
-- WHOLE file into a new SQL Editor tab and click Run (if asked about
-- "destructive operations", click Run: it only creates temporary functions).
-- Result: one table, SUMMARY first. Expected: "N PASS, 0 FAIL".
-- DEPENDS ON: 000 to 011 and the 12 demo accounts. SAFE TO RE-RUN: yes.
-- HOW TO UNDO: nothing to undo.
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


create or replace function pg_temp.manual_seen_check()
returns text[]
language plpgsql
as $fn$
declare
  r text[] := '{}';
  p8 uuid; p9 uuid; p10 uuid; pr1 uuid; pr2 uuid;
  a8 uuid; a9 uuid; a10 uuid;
  t1 timestamptz; s text;
  pass_n integer; fail_n text;
begin
  select id into p8  from auth.users where email = 'patient08@example.test';
  select id into p9  from auth.users where email = 'patient09@example.test';
  select id into p10 from auth.users where email = 'patient10@example.test';
  select id into pr1 from auth.users where email = 'provider01@example.test';
  select id into pr2 from auth.users where email = 'provider02@example.test';
  if p8 is null or p9 is null or p10 is null or pr1 is null or pr2 is null then
    return array['SUMMARY|0 PASS, 1 FAIL|the demo accounts are missing; run the demo seed first'];
  end if;
  select id into a8  from public.alerts where patient_id = p8  and alert_type = 'fhr_out_of_range' order by created_at desc limit 1;
  select id into a9  from public.alerts where patient_id = p9  and alert_type = 'fever' order by created_at desc limit 1;
  select id into a10 from public.alerts where patient_id = p10 and alert_type = 'fhr_out_of_range' order by created_at desc limit 1;
  if a8 is null or a9 is null or a10 is null then
    return array['SUMMARY|0 PASS, 1 FAIL|the demo alerts are missing (patient08 heart rate, patient09 fever, patient10 heart rate); re-run the demo seed'];
  end if;

  begin   -- rolled back at the end
    -- Start from "not seen" inside this rolled-back block, so the result does not depend on what you did in the app.
    update public.alerts set seen_by_patient_at = null where id in (a8, a9, a10);

    s := pg_temp.mark(p8, a8);
    r := r || pg_temp.ck('patient08 marks their own heart-rate alert as seen: true', s = 'true', s);
    select seen_by_patient_at into t1 from public.alerts where id = a8;
    r := r || pg_temp.ck('the time was set by the server, status is still open',
      t1 is not null and abs(extract(epoch from (t1 - now()))) < 5 and (select status from public.alerts where id = a8) = 'open');
    update public.alerts set seen_by_patient_at = now() - interval '1 hour' where id = a8;
    select seen_by_patient_at into t1 from public.alerts where id = a8;
    s := pg_temp.mark(p8, a8);
    r := r || pg_temp.ck('a second call returns false', s = 'false', s);
    r := r || pg_temp.ck('and keeps the first time', (select seen_by_patient_at from public.alerts where id = a8) = t1);

    s := pg_temp.mark(p8, a9);
    r := r || pg_temp.ck('patient08 cannot mark patient09''s alert (false, nothing changed)',
      s = 'false' and (select seen_by_patient_at from public.alerts where id = a9) is null, s);
    s := pg_temp.mark(pr2, a9);
    r := r || pg_temp.ck('provider02 cannot mark patient09''s alert as seen either (false, nothing changed)',
      s = 'false' and (select seen_by_patient_at from public.alerts where id = a9) is null, s);

    r := r || pg_temp.ck('patient08 setting status = resolved on their own alert changes 0 rows',
      pg_temp.cnt(format($q$with u as (update public.alerts set status = 'resolved' where id = %L returning 1) select count(*)::int from u$q$, a8), p8) = 0
      and (select status from public.alerts where id = a8) = 'open');
    r := r || pg_temp.ck('patient08 changing severity is permission denied',
      pg_temp.x(format($q$update public.alerts set severity = 'info' where id = %L$q$, a8), p8) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('patient08 writing seen_by_patient_at directly is permission denied',
      pg_temp.x(format('update public.alerts set seen_by_patient_at = now() where id = %L', a9), p8) like 'ERR 42501 permission denied%');

    r := r || pg_temp.ck('patient10''s alert is invisible to provider01 (0 rows)',
      pg_temp.cnt(format('select count(*)::int from public.alerts where id = %L', a10), pr1) = 0);
    r := r || pg_temp.ck('patient10''s alert is invisible to provider02 (0 rows)',
      pg_temp.cnt(format('select count(*)::int from public.alerts where id = %L', a10), pr2) = 0);
    r := r || pg_temp.ck('patient10 sees their own alert', pg_temp.cnt(format('select count(*)::int from public.alerts where id = %L', a10), p10) = 1);
    r := r || pg_temp.ck('anon calling mark_alert_seen gets permission denied',
      pg_temp.mark(null, a8, 'anon') like 'ERR 42501 permission denied for function%');

    raise exception 'nl_rollback' using errcode = 'NL999';
  exception when sqlstate 'NL999' then null;
  end;

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')::text into pass_n, fail_n from unnest(r) e;
  return array['SUMMARY|' || pass_n || ' PASS, ' || fail_n || ' FAIL|' || case when fail_n = '0' then 'mark as seen behaves on the live project' else 'send me every FAIL row' end] || r;
end
$fn$;

select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 else 3 end, o) as n,
       split_part(e, '|', 1) as status, split_part(e, '|', 2) as test, split_part(e, '|', 3) as detail
from unnest(pg_temp.manual_seen_check()) with ordinality as x(e, o)
order by 1;
