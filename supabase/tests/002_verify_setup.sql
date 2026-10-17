-- 002_verify_setup.sql
-- READ-ONLY checks to run after migrations 000-003. Run each query on its own
-- (the SQL Editor shows only the last result of a multi-query run).
-- Expected results are in the comment above each query.

-- 1. Expect 16 rows, rls_enabled = true on every row.
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' order by 1;

-- 2. Expect 11 rows: on_auth_user_created, profiles_guard_role, the two
--    *_create_alerts triggers, and seven *_set_updated_at triggers.
select n.nspname || '.' || c.relname as on_table, t.tgname as trigger_name
from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
where not t.tgisinternal and (n.nspname = 'public' or (n.nspname = 'auth' and c.relname = 'users'))
order by 1, 2;

-- 3. Expect anon_can_run = false on EVERY row. signed_in_can_run = true ONLY for
--    is_admin, is_assigned_provider, is_provider, redeem_provider_invite, set_my_language.
select p.proname as function_name, pg_get_function_identity_arguments(p.oid) as arguments,
       p.prosecdef as security_definer,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_run,
       has_function_privilege('authenticated', p.oid, 'execute') as signed_in_can_run
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prokind = 'f' order by 1;

-- 4. Expect 0 rows: no table in public grants anything to anon or authenticated yet.
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon', 'authenticated', 'PUBLIC');

-- 5. Expect 4 rows, all is_confirmed = false.
select alert_type, min_value, max_value, sustained_count, severity, is_confirmed
from public.alert_thresholds order by 1;

-- 6. Expect one row: demo_mode = off.
select key, value from public.app_settings;
