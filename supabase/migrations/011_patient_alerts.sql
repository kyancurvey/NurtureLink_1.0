-- =====================================================================
-- 011_patient_alerts.sql
-- NurtureLink step 3.3: the database side of the patient Alerts tab.
--
-- WHAT IT DOES
--   1. Adds the column  public.alerts.seen_by_patient_at  (timestamptz, empty
--      until the patient presses "Mark as seen"). It is only a note that the
--      patient looked at the alert. It does NOT change status, the Home
--      banner or the provider's queue.
--
--   2. Adds  public.mark_alert_seen(p_alert_id uuid) returns boolean.
--      The signed-in patient calls it to set seen_by_patient_at = now() on
--      ONE of their OWN alerts, ONCE. The time comes from the database
--      server, never from the phone. It returns:
--         true   the alert was marked now
--         false  nothing changed: the alert is someone else's, does not
--                exist, or was already marked (the first time is kept).
--      The three "false" cases look identical on purpose, so the function
--      cannot be used to find out whether another patient's alert id exists.
--      A call with no signed-in user fails with  not_signed_in.
--
--   3. Adds ONLY the table  public.alerts  to the Realtime publication
--      supabase_realtime (skipped if it is already there), so the app can
--      show a new alert without a refresh. belt_readings and maternal_vitals
--      are NOT added (Phase 5 may add them).
--
-- WHY A FUNCTION AND NOT AN UPDATE POLICY
--   Grants are per role, and  authenticated  is one shared role for patients
--   and providers. 004 already grants authenticated UPDATE on status,
--   acknowledged_by, acknowledged_at, action_taken and resolved_at (the
--   provider needs them). Row-level security can pick rows, not columns, so
--   ANY policy that let a patient update their own alert row would also let
--   them set status = 'resolved' on a critical alert. So:
--     * NO patient UPDATE policy is added,
--     * NO new column grant is added (nobody can write seen_by_patient_at
--       directly, providers included),
--     * the only way to set it is this function, which touches that one
--       column on the caller's own rows.
--
-- REALTIME NOTES
--   * Who receives what: Realtime applies the existing alerts_select policy
--     (005) to every event, so a patient receives only events for their own
--     alerts, and an assigned provider only for assigned patients. A patient
--     with no provider (patient10) is invisible to every provider.
--   * REPLICA IDENTITY is left at the default (primary key). INSERT and
--     UPDATE events carry the whole new row, which is all the app needs.
--     A DELETE event carries only the id (and Realtime does not apply RLS to
--     deletes). Do NOT set REPLICA IDENTITY FULL: it would put whole old rows
--     (patient id, details) into delete events that RLS does not filter. No
--     client can delete alerts; only removing an account (admin) does.
--   * The app also filters its subscription by patient_id. That is a
--     convenience, not protection; RLS is the protection.
--   * A sandbox cannot prove Realtime delivery. Check it live (Manual Steps).
--
-- DEPENDS ON: 000 to 010. The publication supabase_realtime exists in every
--   Supabase project. If it does not, the file stops with a clear message and
--   changes nothing.
--
-- SAFE TO RE-RUN: yes ("add column if not exists", "create or replace",
--   publication step skipped when alerts is already published).
--
-- HOW TO UNDO:
--   alter publication supabase_realtime drop table public.alerts;
--   drop function if exists public.mark_alert_seen(uuid);
--   alter table public.alerts drop column if exists seen_by_patient_at;
--   Then in supabase/tests/access_tests.sql change the expected list of client
--   functions back (remove mark_alert_seen; 3 lines: header, label, list).
--
-- SECURITY NOTES
--   * mark_alert_seen is SECURITY DEFINER because patients have no UPDATE
--     right on alerts (see above); the function does the one narrow update
--     for them. It takes only an alert id, uses auth.uid() (never a user id
--     from the caller), sets a fixed search_path (empty, every name is
--     schema-qualified), and updates one column. EXECUTE is revoked from
--     PUBLIC and anon and granted to authenticated only.
--   * Readers: the column is readable like the rest of the row (table-level
--     SELECT, 004), so an assigned provider can see it. Providers cannot
--     write it.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. The column (empty = not seen yet)
-- ---------------------------------------------------------------------
alter table public.alerts add column if not exists seen_by_patient_at timestamptz;

comment on column public.alerts.seen_by_patient_at is
  'Set once by mark_alert_seen() when the patient presses "Mark as seen". Server time. Cosmetic: does not change status, acknowledgement or the provider queue.';


-- ---------------------------------------------------------------------
-- 2. The one allowed patient action
-- ---------------------------------------------------------------------
create or replace function public.mark_alert_seen(p_alert_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;

  -- Own alert, not yet seen. Anything else changes 0 rows and returns false.
  update public.alerts
     set seen_by_patient_at = now()
   where id = p_alert_id
     and patient_id = auth.uid()
     and seen_by_patient_at is null;

  get diagnostics v_rows = row_count;
  return v_rows = 1;
end
$$;

comment on function public.mark_alert_seen(uuid) is
  'SECURITY DEFINER because patients have no UPDATE right on alerts (a patient UPDATE policy would also expose status). Sets seen_by_patient_at = now() on the caller''s own alert, once. Returns false for another patient''s alert, a missing alert or an already-seen alert.';

revoke all on function public.mark_alert_seen(uuid) from public, anon, authenticated;
grant execute on function public.mark_alert_seen(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 3. Realtime: publish ONLY alerts
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'publication supabase_realtime does not exist; nothing was changed. Send me this message.';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'alerts'
  ) then
    alter publication supabase_realtime add table public.alerts;
  end if;
end
$$;


-- ---------------------------------------------------------------------
-- Checks (read-only). Expect 4 rows:
--   column       seen_by_patient_at exists
--   function     mark_alert_seen: security_definer = true, anon = false, signed-in = true
--   realtime     publishes exactly: alerts   (for the public schema)
--   replica      alerts: default (primary key)
-- ---------------------------------------------------------------------
select 'column' as what,
       'alerts.seen_by_patient_at ' || case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'alerts' and column_name = 'seen_by_patient_at')
       then 'exists' else 'is MISSING' end as detail
union all
select 'function',
       p.proname::text || ': security_definer = ' || p.prosecdef::text
       || ', anon can run = ' || has_function_privilege('anon', p.oid, 'execute')::text
       || ', signed-in can run = ' || has_function_privilege('authenticated', p.oid, 'execute')::text
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname = 'mark_alert_seen'
union all
select 'realtime',
       'public tables published: ' || coalesce(
         (select string_agg(tablename::text, ', ' order by tablename)
          from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public'), '(none)')
union all
select 'replica',
       'alerts: ' || case c.relreplident when 'd' then 'default (primary key)' when 'f' then 'FULL (change it back: alter table public.alerts replica identity default)' else c.relreplident::text end
from pg_class c where c.oid = 'public.alerts'::regclass
order by 1;
