-- =====================================================================
-- 008_reading_time_guard.sql
-- NurtureLink: stops a reading from being stored with a time in the FUTURE.
--
-- WHY THIS IS NEEDED (found in the step 2.5 review of 002/004/005)
--   The alert function (002) decides "were the last N readings all out of
--   range?" by sorting readings on measured_at, newest first. measured_at is
--   sent by the phone or device (004 grants INSERT on it). Two things follow:
--     1. A phone whose clock is wrong (set years ahead) stores normal
--        readings dated far in the future. Those always count as "the latest
--        N readings", so real out-of-range readings sent afterwards (dated
--        with the true time) are never among the latest N, and NO alert is
--        raised for that patient.
--     2. Readings are append-only (no update, no delete for patients), so the
--        person cannot undo it. Only the admin can, in the SQL Editor.
--   It is the same kind of problem 007 fixed for withdrawn_at: the browser
--   clock must not be trusted. Here the value cannot simply be replaced (an
--   offline device legitimately sends OLD readings later), so the rule is:
--   a reading may be old, but it may not be from the future.
--
-- WHAT IT DOES
--   A BEFORE INSERT trigger on belt_readings and on maternal_vitals. If
--   measured_at is more than 5 minutes ahead of the server clock, the insert
--   is refused with the short code  reading_time_in_future  (the app maps it
--   to i18n text when Phase 3 builds the reading screens). Five minutes is
--   allowed so a phone that is a little fast still works.
--   It applies to every role, including the SQL Editor: a future reading is
--   never right. Old readings (offline sync) are not affected.
--
-- DEPENDS ON: 001 (tables). 002 is not changed. 004 and 005 are not changed.
--
-- SAFE TO RE-RUN: yes ("create or replace", "drop trigger if exists").
--
-- HOW TO UNDO:
--   drop trigger if exists belt_readings_guard_time    on public.belt_readings;
--   drop trigger if exists maternal_vitals_guard_time  on public.maternal_vitals;
--   drop function if exists public.guard_reading_time();
--
-- SECURITY NOTES
--   * Not SECURITY DEFINER: it only looks at the row being saved. search_path
--     is fixed anyway.
--   * EXECUTE is revoked from everyone, like every function in 002. A trigger
--     does not need the caller to hold EXECUTE, so no grant is added.
--   * For Phase 3 and 5: the app should omit measured_at when a reading is
--     taken live (the database then uses its own clock), and send the device
--     time only for readings that were stored offline.
-- =====================================================================

create or replace function public.guard_reading_time()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.measured_at > now() + interval '5 minutes' then
    raise exception 'reading_time_in_future';
  end if;
  return new;
end
$$;
revoke all on function public.guard_reading_time() from public, anon, authenticated;

drop trigger if exists belt_readings_guard_time on public.belt_readings;
create trigger belt_readings_guard_time
  before insert on public.belt_readings
  for each row execute function public.guard_reading_time();

drop trigger if exists maternal_vitals_guard_time on public.maternal_vitals;
create trigger maternal_vitals_guard_time
  before insert on public.maternal_vitals
  for each row execute function public.guard_reading_time();

-- Check (expect 2 rows, tgenabled = O):
select c.relname as table_name, t.tgname, t.tgenabled
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
where t.tgname in ('belt_readings_guard_time', 'maternal_vitals_guard_time')
  and not t.tgisinternal
order by c.relname;

-- Check that nothing already stored is in the future (expect 0 and 0). If a
-- number is above 0, those rows were stored before this guard existed and are
-- hiding alerts for their patient; show them to me before deleting anything.
select
  (select count(*) from public.belt_readings   where measured_at > now() + interval '5 minutes') as future_belt_readings,
  (select count(*) from public.maternal_vitals where measured_at > now() + interval '5 minutes') as future_vitals;
