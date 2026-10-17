-- =====================================================================
-- 000_project_hardening.sql
-- NurtureLink: make the Supabase project safe no matter how it was created.
--
-- WHAT IT DOES
--   PART 1 (read only): a diagnostic query. Run it ALONE, first, and again
--          after PART 2, to see default privileges, RLS flags, grants and
--          event triggers.
--   PART 2 (changes):
--     a. Removes default privileges for anon and authenticated on tables,
--        sequences and functions created later in the public schema, so a
--        new object is never exposed by accident. Works whether the project
--        option "Automatically expose new tables" was ON or OFF.
--     b. Also removes the implicit "everyone can run new functions" default
--        (PUBLIC). Reason: anon and authenticated are members of PUBLIC, so
--        revoking from them alone would still leave new functions callable.
--     c. Creates an event trigger that turns on Row Level Security (RLS) for
--        every new table in public. Works whether "Enable automatic RLS" was
--        ON or OFF (if it was ON, this simply does the same thing twice).
--     d. Grants USAGE on the public schema to anon and authenticated, and
--        nothing more.
--
-- DEPENDS ON: nothing. Run this first, in the Supabase SQL Editor (role
--             "postgres", the default).
--
-- SAFE TO RE-RUN: yes. Every statement can be repeated.
--   Do NOT add "REVOKE ALL ON ALL TABLES" to this file: re-running it after
--   004 (grants) would wipe the grants.
--
-- HOW TO UNDO (rarely wanted; it re-opens the exposure this file closes):
--   drop event trigger if exists nl_enable_rls_on_new_tables;
--   drop function if exists public.nl_enable_rls_on_new_tables();
--   alter default privileges for role postgres grant execute on functions to public;
--   -- To restore the old Supabase defaults for anon/authenticated (not advised):
--   -- alter default privileges for role postgres in schema public
--   --   grant all on tables to anon, authenticated;
--   -- (same again for sequences and functions)
--   -- revoke usage on schema public from anon, authenticated;  -- not advised
--
-- NOT TOUCHED: the service_role privileges. That role is for trusted server
-- code only. This project never uses it and its key never appears anywhere.
-- =====================================================================


-- =====================================================================
-- PART 1: DIAGNOSTIC (READ ONLY). Select from "-- PART 1 START" down to
-- "-- PART 1 END" and run only that. Paste the rows it returns back to
-- Claude. It changes nothing.
-- =====================================================================
-- PART 1 START
select section, item, detail
from (
  -- who you are and what exists
  select 1 as ord, 'info'::text as section, 'current_user'::text as item, current_user::text as detail
  union all
  select 1, 'info', 'postgres_version', split_part(version(), ' on ', 1)
  union all
  select 1, 'info', 'roles_found (want 3: anon, authenticated, service_role)',
         (select count(*)::text from pg_roles where rolname in ('anon', 'authenticated', 'service_role'))

  -- default privileges: what a NEW object in public would receive
  union all
  select 2, 'default_privileges',
         r.rolname || ' / ' || coalesce(n.nspname, '(all schemas)') || ' / ' ||
           case d.defaclobjtype when 'r' then 'tables' when 'S' then 'sequences'
                                when 'f' then 'functions' when 'n' then 'schemas'
                                else d.defaclobjtype::text end,
         d.defaclacl::text
  from pg_default_acl d
  join pg_roles r on r.oid = d.defaclrole
  left join pg_namespace n on n.oid = d.defaclnamespace
  union all
  select 2, 'default_privileges', '(no default privilege entries)', ''
  where not exists (select 1 from pg_default_acl)

  -- which tables in public have RLS on
  union all
  select 3, 'rls_tables', c.relname,
         'rls_enabled=' || c.relrowsecurity::text || ' forced=' || c.relforcerowsecurity::text
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p')
  union all
  select 3, 'rls_tables', '(no tables in public yet)', ''
  where not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p'))

  -- grants that anon, authenticated or PUBLIC already hold on public tables and views
  union all
  select 4, 'table_privileges',
         c.relname || ' -> ' || case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end,
         string_agg(a.privilege_type, ',' order by a.privilege_type)
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(c.relacl) a
  where n.nspname = 'public'
    and c.relkind in ('r', 'p', 'v', 'm')
    and (a.grantee = 0 or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated')))
  group by c.relname, a.grantee
  union all
  select 4, 'table_privileges', '(no grants to anon/authenticated/PUBLIC on public tables)', ''
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(c.relacl) a
    where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm')
      and (a.grantee = 0 or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated'))))

  -- functions in public (not from extensions) and who may run them
  union all
  select 5, 'functions_in_public',
         p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         case when p.proacl is null then 'no ACL set = PUBLIC can execute' else p.proacl::text end
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')

  -- can the two API roles even see the public schema
  union all
  select 6, 'schema_public_usage', r.rolname, has_schema_privilege(r.rolname, 'public', 'USAGE')::text
  from pg_roles r where r.rolname in ('anon', 'authenticated')

  -- event triggers (ours is nl_enable_rls_on_new_tables; Supabase's own may also appear)
  union all
  select 7, 'event_triggers', e.evtname,
         'event=' || e.evtevent || ' enabled=' || e.evtenabled::text || ' function=' || e.evtfoid::regproc::text
  from pg_event_trigger e
  union all
  select 7, 'event_triggers', '(none)', ''
  where not exists (select 1 from pg_event_trigger)
) diag
order by ord, section, item;
-- PART 1 END


-- =====================================================================
-- PART 2: HARDENING (changes the project). Run the whole file once PART 1
-- has been sent and reviewed.
-- =====================================================================

-- (a) New tables, sequences and functions in public get NO privileges for
--     anon or authenticated. Explicit grants come later (migration 004).
--     "for role postgres" = objects created by the SQL Editor.
alter default privileges for role postgres in schema public revoke all on tables    from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated;

-- (b) Remove the built-in default that lets PUBLIC (which includes anon and
--     authenticated) run any new function. This one has no "in schema"
--     because the PUBLIC default is global, so it applies to every function
--     that role "postgres" creates from now on. If you later install an
--     extension as postgres and an API role needs one of its functions, grant
--     EXECUTE on that function explicitly. Every NurtureLink function already
--     grants EXECUTE explicitly.
alter default privileges for role postgres revoke execute on functions from public;

-- Same as (a), for objects created by Supabase's own admin role. Supabase
-- usually does not let "postgres" change another role's defaults, so a
-- failure here is expected and only prints a notice. NurtureLink creates all
-- of its objects as "postgres", so this is a bonus, not a requirement.
do $$
begin
  alter default privileges for role supabase_admin in schema public revoke all on tables    from anon, authenticated;
  alter default privileges for role supabase_admin in schema public revoke all on sequences from anon, authenticated;
  alter default privileges for role supabase_admin in schema public revoke all on functions from anon, authenticated;
exception
  when insufficient_privilege or undefined_object then
    raise notice 'Skipped supabase_admin default privileges (%). This is normal on hosted Supabase.', sqlerrm;
end
$$;

-- (c) Automatically enable RLS on every new table in public.
--     The function is deliberately SECURITY INVOKER: it only runs
--     "alter table ... enable row level security" on a table the current
--     session just created, so it needs no extra power.
create or replace function public.nl_enable_rls_on_new_tables()
returns event_trigger
language plpgsql
set search_path = pg_catalog
as $$
declare
  cmd record;
begin
  for cmd in
    select object_identity
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table', 'partitioned table')
      and schema_name = 'public'
  loop
    execute format('alter table %s enable row level security', cmd.object_identity);
  end loop;
end
$$;

-- Nobody needs to call it by hand; the event trigger runs it.
revoke all on function public.nl_enable_rls_on_new_tables() from public, anon, authenticated;

-- Creating an event trigger normally needs a privilege that the hosted
-- "postgres" role may or may not have. If it is refused, the script does not
-- fail: it warns you. In that case RLS is still switched on explicitly, table
-- by table, inside 001_tables.sql, and you must do the same for any table you
-- create by hand later ("alter table ... enable row level security").
do $$
begin
  drop event trigger if exists nl_enable_rls_on_new_tables;
  create event trigger nl_enable_rls_on_new_tables
    on ddl_command_end
    when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
    execute function public.nl_enable_rls_on_new_tables();
exception
  when insufficient_privilege then
    raise warning 'Could not create the RLS event trigger (%). Not fatal: 001_tables.sql enables RLS explicitly on every table. Tell Claude about this warning.', sqlerrm;
end
$$;

-- (d) The two API roles may see that the public schema exists. Nothing more:
--     no table, sequence or function access is granted here.
grant usage on schema public to anon, authenticated;
