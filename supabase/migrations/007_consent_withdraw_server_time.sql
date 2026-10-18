-- =====================================================================
-- 007_consent_withdraw_server_time.sql
-- NurtureLink: makes "withdrawn_at" always the SERVER's time.
--
-- WHY THIS IS NEEDED (the one gap found in 004/005 for the consent flow)
--   004 lets a user UPDATE only consent_records.withdrawn_at, and 005 lets
--   them set it once. But the app has to SEND a value, and the browser can
--   only send its own clock. Two problems follow:
--     1. A phone with its clock a few minutes behind sends a time earlier
--        than accepted_at. The table check "withdrawn_at >= accepted_at"
--        then rejects the withdrawal, and the person cannot withdraw.
--     2. A user could send any time they like (back-dated or in the future),
--        so withdrawn_at would not be reliable evidence.
--   accepted_at is already safe, because the client has no INSERT grant on
--   it and the database fills it in. This trigger gives withdrawn_at the same
--   protection: whatever the client sends is replaced by now().
--   No new grant and no new policy is needed; 004 and 005 stay as they are.
--
-- WHAT IT DOES
--   A BEFORE UPDATE trigger on public.consent_records. When withdrawn_at goes
--   from empty to a value, it sets withdrawn_at = greatest(now(), accepted_at).
--   Other updates are not changed. It also runs for the SQL Editor, which is
--   fine: the admin gets the true time too.
--
-- DEPENDS ON: 001 (consent_records), 002 (nothing else), 004/005 unchanged.
-- SAFE TO RE-RUN: yes ("create or replace", "drop trigger if exists").
--
-- HOW TO UNDO:
--   drop trigger if exists consent_records_server_withdraw_time on public.consent_records;
--   drop function if exists public.set_consent_withdrawn_time();
--
-- SECURITY NOTES
--   * Not SECURITY DEFINER: it only edits the row being saved, so it needs no
--     extra rights. search_path is fixed anyway.
--   * EXECUTE is revoked from everyone, like every function in 002. A trigger
--     does not need the caller to have EXECUTE.
-- =====================================================================

create or replace function public.set_consent_withdrawn_time()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.withdrawn_at is null and new.withdrawn_at is not null then
    new.withdrawn_at := greatest(now(), old.accepted_at);
  end if;
  return new;
end
$$;
revoke all on function public.set_consent_withdrawn_time() from public, anon, authenticated;

drop trigger if exists consent_records_server_withdraw_time on public.consent_records;
create trigger consent_records_server_withdraw_time
  before update on public.consent_records
  for each row execute function public.set_consent_withdrawn_time();

-- Check (expect 1 row):
select tgname, tgenabled
from pg_trigger
where tgrelid = 'public.consent_records'::regclass
  and tgname = 'consent_records_server_withdraw_time';
