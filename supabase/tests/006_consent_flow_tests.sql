-- =====================================================================
-- 006_consent_flow_tests.sql
-- NurtureLink step 2.4: checks the database side of the Terms and consent
-- flow. Run in the Supabase SQL Editor AFTER 006 and 007.
--
-- WHAT IT CHECKS
--   * 006 really put 14 DRAFT documents in the table (7 types x en/fil).
--   * Accept: a user records consent for a published document; the version and
--     language come from the document row; a second ACTIVE record for the same
--     document is refused; an unpublished or someone else's is refused.
--   * Withdraw: works once; the stored time is the SERVER time even when the
--     browser clock is wrong (007); cannot be undone or edited otherwise.
--   * Re-accept after withdrawing creates a new active record.
--   * Deletion requests: a patient files one for self, only one pending at a
--     time, cannot set the status, cannot read or file for someone else.
--   * Audit log: a provider can write a login entry; a patient cannot; nobody
--     can read it from the client.
--   * The admin deletion snippet (docs/ADMIN_SQL.md, snippet 10) logic: deleting
--     the user removes their consent records and keeps the deletion request.
--
-- NOTHING IS SAVED. Like access_tests.sql, everything is created inside one
-- block that is deliberately aborted at its end, so it rolls back. The fake
-- users have emails ending in ".invalid". The first checks only READ your real
-- consent_documents rows.
--
-- HOW TO RUN: paste the WHOLE file into a new SQL Editor tab and click Run (if
-- asked about "destructive operations", click Run: only temporary functions
-- are created and the fake data is rolled back). Result: one table with a
-- SUMMARY row first, then every FAIL, then INFO, then PASS.
-- WHAT TO SEND BACK IF ANYTHING FAILS: the SUMMARY row and every FAIL row.
--
-- DEPENDS ON: 000 to 007. SAFE TO RE-RUN: yes. HOW TO UNDO: nothing to undo.
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

create or replace function pg_temp.nl_consent_tests()
returns text[]
language plpgsql
as $fn$
declare
  r      text[] := '{}';
  a      uuid := gen_random_uuid();   -- patient A
  b      uuid := gen_random_uuid();   -- patient B
  p1     uuid := gen_random_uuid();   -- provider
  ad     uuid := gen_random_uuid();   -- admin
  d_terms uuid := gen_random_uuid();  -- fake published docs (version 901 so they never clash with real rows)
  d_priv  uuid := gen_random_uuid();
  d_draft uuid := gen_random_uuid();
  s      text;
  n      integer;
  fails  text;
  seeded integer;
  marked integer;
  published_now integer;
  w1     timestamptz;
  acc    timestamptz;
begin
  -- 1. The real seed rows (read only, outside the rolled-back block's effects)
  select count(*), count(*) filter (where body like 'DRAFT, pending ethics/legal review.%')
    into seeded, marked
  from public.consent_documents
  where version = 1
    and doc_type in ('terms_of_use','privacy_notice','informed_consent','medical_disclaimer',
                     'guardian_assent','study_data_use','provider_confidentiality')
    and language in ('en','fil');
  r := r || pg_temp.ck('006 seeded 14 version-1 documents (7 types x en/fil)', seeded = 14, 'found ' || seeded);
  r := r || pg_temp.ck('every seeded document starts with "DRAFT, pending ethics/legal review."', marked = 14, marked || ' of 14');
  select count(*) into published_now from public.consent_documents where version = 1 and is_published;
  r := r || ('INFO|' || published_now || ' of the version-1 documents are published right now (the app needs the required ones published; see ADMIN_SQL snippet 7)|');

  begin   -- everything below is rolled back

    insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
    select u, 'nl-consent-' || u || '@nurturelink-test.invalid', now(), '{}'::jsonb
    from unnest(array[a, b, p1, ad]) u;
    update public.profiles set role = 'provider' where id = p1;
    update public.profiles set role = 'admin' where id = ad;

    insert into public.consent_documents (id, doc_type, version, language, title, body, is_published) values
      (d_terms, 'terms_of_use',   901, 'fil', 'DRAFT test', 'DRAFT, pending ethics/legal review.', true),
      (d_priv,  'privacy_notice', 901, 'en',  'DRAFT test', 'DRAFT, pending ethics/legal review.', true),
      (d_draft, 'terms_of_use',   902, 'en',  'DRAFT test', 'DRAFT, pending ethics/legal review.', false);

    -- 2. Accept
    r := r || pg_temp.ck('A accepts a published document',
      pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L)', a, d_terms), a) = 'ok');
    r := r || pg_temp.ck('the record carries the right version and language through document_id (the SELECT the manual steps use)',
      pg_temp.q(format($q$select count(*)::int from public.consent_records cr join public.consent_documents d on d.id = cr.document_id
                         where cr.user_id = %L and d.doc_type = 'terms_of_use' and d.version = 901 and d.language = 'fil'
                           and cr.accepted_at is not null and cr.withdrawn_at is null$q$, a), a) = 1);
    r := r || pg_temp.ck('a second ACTIVE record for the same document is refused (23505)',
      pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L)', a, d_terms), a) like 'ERR 23505%');
    r := r || pg_temp.ck('A cannot accept an unpublished document',
      pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L)', a, d_draft), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot accept on behalf of B',
      pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L)', b, d_terms), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('one insert of several records is all-or-nothing (a duplicate in the list saves none)',
      pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L), (%L, %L)', a, d_priv, a, d_terms), a) like 'ERR 23505%'
      and pg_temp.q(format('select count(*)::int from public.consent_records where user_id = %L and document_id = %L', a, d_priv), a) = 0);
    r := r || pg_temp.ck('A accepts a second document in one go with a fresh one',
      pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L)', a, d_priv), a) = 'ok');

    -- 3. Withdraw: server time wins over a wrong browser clock
    select accepted_at into acc from public.consent_records where user_id = a and document_id = d_terms;
    r := r || pg_temp.ck('A withdraws with a browser clock one YEAR behind (would break the table check without 007)',
      pg_temp.x(format($q$update public.consent_records set withdrawn_at = now() - interval '1 year' where user_id = %L and document_id = %L and withdrawn_at is null$q$, a, d_terms), a) = 'ok');
    select withdrawn_at into w1 from public.consent_records where user_id = a and document_id = d_terms;
    r := r || pg_temp.ck('the stored withdrawn_at is the server time (not the browser value) and is not before accepted_at',
      w1 is not null and w1 >= acc and abs(extract(epoch from (now() - w1))) < 60, 'withdrawn_at = ' || coalesce(w1::text, 'null') || ', accepted_at = ' || acc);
    s := pg_temp.x(format($q$update public.consent_records set withdrawn_at = now() + interval '5 years' where user_id = %L and document_id = %L$q$, a, d_priv), a);   -- own statement: a later query must see its result
    r := r || pg_temp.ck('a withdrawal sent with a FUTURE time is also stored as server time',
      s = 'ok' and (select abs(extract(epoch from (now() - withdrawn_at))) < 60 from public.consent_records where user_id = a and document_id = d_priv), s);
    r := r || pg_temp.ck('withdrawing again changes 0 rows',
      pg_temp.q(format($q$with u as (update public.consent_records set withdrawn_at = now() where user_id = %L and document_id = %L returning 1) select count(*)::int from u$q$, a, d_terms), a) = 0);
    s := pg_temp.x(format('update public.consent_records set withdrawn_at = null where user_id = %L and document_id = %L', a, d_terms), a);
    r := r || pg_temp.ck('A cannot undo a withdrawal',
      (select withdrawn_at is not null from public.consent_records where user_id = a and document_id = d_terms), s);

    -- 4. Re-accept
    r := r || pg_temp.ck('A re-accepts after withdrawing (new active record)',
      pg_temp.x(format('insert into public.consent_records (user_id, document_id) values (%L, %L)', a, d_terms), a) = 'ok');
    r := r || pg_temp.ck('after re-accept: 2 records for the document, exactly 1 active, the old one kept as history',
      (select count(*) = 2 and count(*) filter (where withdrawn_at is null) = 1 from public.consent_records where user_id = a and document_id = d_terms));
    r := r || pg_temp.ck('B sees none of A''s records; a provider sees none either',
      pg_temp.q('select count(*)::int from public.consent_records', b) = 0
      and pg_temp.q('select count(*)::int from public.consent_records', p1) = 0);

    -- 5. Deletion requests
    r := r || pg_temp.ck('A files a deletion request for self (with a note)',
      pg_temp.x(format($q$insert into public.deletion_requests (patient_id, note) values (%L, 'fake note')$q$, a), a) = 'ok');
    r := r || pg_temp.ck('a second PENDING request is refused (23505)',
      pg_temp.x(format('insert into public.deletion_requests (patient_id) values (%L)', a), a) like 'ERR 23505%');
    r := r || pg_temp.ck('A cannot file a request for B',
      pg_temp.x(format('insert into public.deletion_requests (patient_id) values (%L)', b), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('A cannot set the status or completed_at, or edit a request (permission denied)',
      pg_temp.x(format($q$insert into public.deletion_requests (patient_id, status) values (%L, 'completed')$q$, b), b) like 'ERR 42501 permission denied%'
      and pg_temp.x(format($q$update public.deletion_requests set status = 'declined' where patient_id = %L$q$, a), a) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('a note over 1000 characters is refused (23514)',
      pg_temp.x(format('insert into public.deletion_requests (patient_id, note) values (%L, repeat(%L, 1001))', b, 'x'), b) like 'ERR 23514%');
    r := r || pg_temp.ck('A reads only own request; B reads none; a provider reads none; the admin account reads all',
      pg_temp.q('select count(*)::int from public.deletion_requests', a) = 1
      and pg_temp.q('select count(*)::int from public.deletion_requests', b) = 0
      and pg_temp.q('select count(*)::int from public.deletion_requests', p1) = 0
      and pg_temp.q('select count(*)::int from public.deletion_requests', ad) >= 1);

    -- 6. Audit log (provider login entry)
    r := r || pg_temp.ck('a provider writes a provider_login audit row (no patient)',
      pg_temp.x(format($q$insert into public.audit_log (actor_id, patient_id, action, details) values (%L, null, 'provider_login', '{}'::jsonb)$q$, p1), p1) = 'ok');
    r := r || pg_temp.ck('a patient cannot write an audit row',
      pg_temp.x(format($q$insert into public.audit_log (actor_id, action) values (%L, 'provider_login')$q$, a), a) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('a provider cannot write an audit row as someone else',
      pg_temp.x(format($q$insert into public.audit_log (actor_id, action) values (%L, 'provider_login')$q$, a), p1) like 'ERR 42501 new row violates row-level security%');
    r := r || pg_temp.ck('a provider cannot read the audit log (permission denied)',
      pg_temp.x('select count(*) from public.audit_log', p1) like 'ERR 42501 permission denied%');
    r := r || pg_temp.ck('an audit action longer than 64 characters is refused (23514)',
      pg_temp.x(format('insert into public.audit_log (actor_id, action) values (%L, repeat(%L, 65))', p1, 'x'), p1) like 'ERR 23514%');

    -- 7. The admin deletion snippet: delete the user; consent goes, request stays
    select count(*) into n from public.consent_records where user_id = a;
    update public.deletion_requests set status = 'completed', completed_at = now() where patient_id = a;
    delete from auth.users where id = a;
    r := r || pg_temp.ck('deleting the user removes their consent records and profile',
      n > 0 and not exists (select 1 from public.consent_records where user_id = a) and not exists (select 1 from public.profiles where id = a));
    r := r || pg_temp.ck('the deletion request stays, marked completed, with patient_id empty',
      (select count(*) = 1 from public.deletion_requests where patient_id is null and status = 'completed' and completed_at is not null));

    raise exception 'nl_rollback' using errcode = 'NL999';
  exception
    when sqlstate 'NL999' then
      null;
  end;

  select count(*) filter (where e like 'PASS|%'), count(*) filter (where e like 'FAIL|%')
    into n, fails from unnest(r) e;
  return array['SUMMARY|' || n || ' PASS, ' || fails || ' FAIL|' || case when fails = '0' then 'consent database rules hold' else 'send me every FAIL row' end] || r;
end
$fn$;

select row_number() over (order by case split_part(e, '|', 1) when 'SUMMARY' then 0 when 'FAIL' then 1 when 'INFO' then 2 else 3 end, o) as n,
       split_part(e, '|', 1) as status,
       split_part(e, '|', 2) as test,
       split_part(e, '|', 3) as detail
from unnest(pg_temp.nl_consent_tests()) with ordinality as x(e, o)
order by 1;
