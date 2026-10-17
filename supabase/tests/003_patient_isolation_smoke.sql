-- =====================================================================
-- 003_patient_isolation_smoke.sql
-- NurtureLink step 2.3: shows that a real PATIENT account you just created
-- in the app cannot reach provider-only data or become a provider.
--
-- WHAT IT DOES
--   Finds the patient by email, then runs 9 small checks while pretending to be
--   that user (role "authenticated" plus their id in request.jwt.claims, like a
--   real API request). Each check is rolled back, so nothing is ever changed.
--   Result: one table with PASS or FAIL for each check.
--
-- HOW TO RUN
--   1. Replace PATIENT_EMAIL@example.com below with a test patient's email.
--      Use a FAKE test account, never a real person.
--   2. Paste the whole file into a new SQL Editor tab and click Run.
--   If the table is empty, no account has that email.
--
-- EXPECTED
--   All 9 rows PASS. Checks 5 to 7 are "permission denied" (no grant exists at
--   all); checks 3 and 4 are 0 rows (a patient shares the database role with
--   providers, so row rules hide the rows instead).
--
-- DEPENDS ON: 000 to 005 already run, and the account exists with role patient.
-- SAFE TO RE-RUN: yes. READ-ONLY for your data (every check is undone).
-- HOW TO UNDO: nothing to undo; the helper function lives only in this session.
-- =====================================================================

create or replace function pg_temp.as_user(p_uid uuid, p_sql text)
returns text
language plpgsql
as $fn$
declare
  v text;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  begin
    execute p_sql into v;
    -- Always abort the inner block, so whatever the statement did is undone.
    raise exception 'nl_done:%', coalesce(v, 'null');
  exception when others then
    reset role;
    if sqlerrm like 'nl_done:%' then
      return 'ok ' || substr(sqlerrm, 9);
    end if;
    return 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
end
$fn$;

select n, check_name, expect,
       case when result = expect or (expect like 'ERR%' and result like expect || '%')
            then 'PASS' else 'FAIL' end as status,
       result
from (
  select c.n, c.check_name, c.expect, pg_temp.as_user(me.uid, c.q) as result
  from (select id as uid from auth.users
        where lower(email) = lower('PATIENT_EMAIL@example.com')) me
  cross join (values
    (1, 'My profile says patient',              'ok patient',  'select role from public.profiles where id = auth.uid()'),
    (2, 'is_provider() is false',               'ok false',    'select public.is_provider()::text'),
    (3, 'Validation data: 0 rows visible',      'ok 0',        'select count(*)::text from public.validation_pairs'),
    (4, 'Consult notes: 0 rows visible',        'ok 0',        'select count(*)::text from public.consult_notes'),
    (5, 'Audit log: permission denied',         'ERR 42501',   'select count(*)::text from public.audit_log'),
    (6, 'Provider invites: permission denied',  'ERR 42501',   'select count(*)::text from public.provider_invites'),
    (7, 'App settings: permission denied',      'ERR 42501',   'select count(*)::text from public.app_settings'),
    (8, 'Cannot make myself a provider',        'ERR 42501',   'update public.profiles set role = ''provider'' where id = auth.uid() returning id::text'),
    (9, 'A wrong invite code is refused',       'ERR P0001 invalid_invite', 'select public.redeem_provider_invite(''NOTAREALCODE0'')')
  ) as c(n, check_name, expect, q)
) r
order by n;
