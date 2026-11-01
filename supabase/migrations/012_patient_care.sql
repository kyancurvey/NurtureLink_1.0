-- =====================================================================
-- 012_patient_care.sql
-- NurtureLink step 3.4: the database side of the patient Care tab.
--
-- WHAT IT DOES
--   1. Moves every PATIENT write on public.appointments into functions and
--      DROPS the two patient policies from 005:
--         appointments_insert_patient
--         appointments_update_patient
--      After this a patient has no direct way to INSERT or UPDATE an
--      appointment. The provider policies, the select policy and ALL grants
--      are left exactly as they are (Phase 4 needs them).
--
--   2. Adds four functions that signed-in users can run. Each acts only on
--      auth.uid(); the caller can never name another user or a provider:
--
--      request_appointment(p_starts_at timestamptz) returns uuid
--        Creates a request for the caller: status 'requested', provider taken
--        from the caller's OWN assignment (the client never sends it), the
--        column default duration (30 minutes). Returns the new id. Errors:
--          not_signed_in           no signed-in user
--          appointment_time_invalid  the time is null
--          appointment_too_soon    earlier than 1 hour from now
--          appointment_too_far     later than 90 days from now
--          no_provider             no provider assigned (patient10), or the
--                                  assigned account is not a provider
--          too_many_open_requests  3 requests are already open
--
--      cancel_my_appointment(p_id uuid) returns boolean
--        Cancels the caller's OWN appointment if it is 'requested' or
--        'scheduled' (confirmed) AND still in the future. Changes only
--        status. Returns true, or false when nothing changed (someone else's
--        appointment, missing, already cancelled or completed, in the past:
--        all look the same, so it cannot be used to probe other ids).
--
--      request_reschedule(p_id uuid, p_new_starts_at timestamptz) returns boolean
--        Moves the caller's OWN 'requested' appointment (still in the
--        future) to a new time. It stays 'requested'. It NEVER works on a
--        'scheduled' (confirmed) appointment: for those the app says to
--        cancel and request a new time. Changes only starts_at. Same time
--        rules and same true/false behaviour as above. Errors for a bad
--        time: appointment_time_invalid, appointment_too_soon,
--        appointment_too_far.
--
--      my_provider_name() returns text
--        The display name of the caller's OWN assigned provider, trimmed, or
--        null (no provider, blank name, or the assigned account is not a
--        provider). One text value: no id, no email, no role.
--
--   3. Adds one helper, appointment_time_check(timestamptz), that holds the
--      time limits so request_appointment and request_reschedule cannot drift
--      apart. Nobody can run it directly (only the functions above, which run
--      with the owner's rights).
--
-- SCHEDULING LIMITS (named constants inside the functions; pending review)
--   c_min_lead  = 1 hour   (appointment_time_check)
--   c_max_ahead = 90 days  (appointment_time_check)
--   c_max_open  = 3        (request_appointment)
--   To change a limit: edit the constant in this file and run the file again.
--   "Open" means status 'requested' AND starting in the future. A request whose
--   time has passed does not count (the patient cannot cancel past rows, so
--   counting them would lock the patient out for good). Confirmed
--   ('scheduled'), completed and cancelled rows never count.
--
-- WHY FUNCTIONS AND NOT POLICIES
--   Grants are per role and  authenticated  is one shared role for patients
--   and providers: 004 grants UPDATE on starts_at, duration_minutes and
--   status for the provider's sake. Row-level security picks rows, not
--   columns, so the old patient UPDATE policy (new status requested or
--   cancelled) let a patient change starts_at and duration_minutes freely,
--   and even flip a provider-confirmed ('scheduled') visit back to
--   'requested' at a new time. It also let any patient, including one with no
--   provider, insert a request, with any time and any duration, and without
--   any limit on how many. Now there is no patient write policy at all.
--
-- WHAT A DIRECT PATIENT WRITE DOES NOW (tested in 012_patient_care_tests.sql)
--   INSERT  -> error 42501 "new row violates row-level security policy"
--              (not "permission denied": the grant exists, no policy passes).
--   UPDATE  -> no error, 0 rows changed (the row is invisible to the update).
--   DELETE  -> error 42501 "permission denied" (there is no DELETE grant).
--
-- DEPENDS ON: 000 to 011.
--
-- ABOUT 005_rls.sql: 005 drops every policy in public and recreates its own.
--   Since step 3.4 the edited 005 no longer creates appointments_insert_patient
--   or appointments_update_patient (a comment there points here), so running 005
--   again does NOT reopen the gaps. If you ever use an OLD copy of 005, run this
--   file again after it. The tests (section 0) catch the old policies either way.
--
-- SAFE TO RE-RUN: yes ("create or replace", "drop policy if exists").
--
-- HOW TO UNDO (restores the 005 behaviour, including its gaps):
--   drop function if exists public.request_reschedule(uuid, timestamptz);
--   drop function if exists public.cancel_my_appointment(uuid);
--   drop function if exists public.request_appointment(timestamptz);
--   drop function if exists public.my_provider_name();
--   drop function if exists public.appointment_time_check(timestamptz);
--   drop policy if exists appointments_insert_patient on public.appointments;
--   create policy appointments_insert_patient on public.appointments
--     for insert to authenticated
--     with check (
--       patient_id = (select auth.uid())
--       and status = 'requested'
--       and (provider_id is null
--            or provider_id = (select pp.assigned_provider_id from public.pregnancy_profiles pp
--                              where pp.patient_id = (select auth.uid())))
--     );
--   drop policy if exists appointments_update_patient on public.appointments;
--   create policy appointments_update_patient on public.appointments
--     for update to authenticated
--     using (patient_id = (select auth.uid()) and status in ('requested', 'scheduled'))
--     with check (patient_id = (select auth.uid()) and status in ('requested', 'cancelled'));
--   Then in supabase/tests/access_tests.sql put back lines 316-317 and 322-325
--   and the list of client functions (see the step 3.4 notes).
--
-- SECURITY NOTES
--   * The four client functions are SECURITY DEFINER because patients have no
--     write policy on appointments or read access to provider profiles. Each
--     has a fixed (empty) search_path with every name schema-qualified, uses
--     auth.uid() only, and has EXECUTE revoked from PUBLIC and anon and
--     granted to authenticated only.
--   * request_appointment locks the caller's own pregnancy_profiles row
--     (FOR UPDATE) before counting open requests, so two requests sent at the
--     same moment cannot both slip under the limit. A SQL file cannot prove
--     parallel timing; the lock is the reason to trust it.
--   * No grant changed. No DELETE grant exists. Nothing is granted to anon.
--   * appointments is NOT added to the Realtime publication; the Care tab
--     refetches on focus and after each action.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Helper: the time limits (nobody can run it from the API)
-- ---------------------------------------------------------------------
create or replace function public.appointment_time_check(p_starts_at timestamptz)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  -- Scheduling limits, pending review. Change here, then run this file again.
  c_min_lead  constant interval := interval '1 hour';
  c_max_ahead constant interval := interval '90 days';
begin
  if p_starts_at is null then
    raise exception 'appointment_time_invalid';
  end if;
  if p_starts_at < now() + c_min_lead then
    raise exception 'appointment_too_soon';
  end if;
  if p_starts_at > now() + c_max_ahead then
    raise exception 'appointment_too_far';
  end if;
end
$$;

comment on function public.appointment_time_check(timestamptz) is
  'Holds the scheduling time limits (at least 1 hour ahead, at most 90 days ahead). Called only by request_appointment and request_reschedule; EXECUTE is revoked from everyone else.';

revoke all on function public.appointment_time_check(timestamptz) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 2. request_appointment: a new request for the caller
-- ---------------------------------------------------------------------
create or replace function public.request_appointment(p_starts_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Scheduling limit, pending review. Change here, then run this file again.
  c_max_open constant integer := 3;
  v_uid      uuid := auth.uid();
  v_provider uuid;
  v_open     integer;
  v_id       uuid;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  perform public.appointment_time_check(p_starts_at);

  -- The provider comes from the caller's own assignment, never from the caller.
  -- The row is locked so two requests at the same moment are counted one by one.
  select pp.assigned_provider_id
    into v_provider
    from public.pregnancy_profiles pp
   where pp.patient_id = v_uid
     for update;

  if v_provider is null
     or not exists (select 1 from public.profiles pr where pr.id = v_provider and pr.role = 'provider') then
    raise exception 'no_provider';
  end if;

  -- Open = still waiting for the provider and still in the future.
  select count(*)
    into v_open
    from public.appointments a
   where a.patient_id = v_uid
     and a.status = 'requested'
     and a.starts_at > now();

  if v_open >= c_max_open then
    raise exception 'too_many_open_requests';
  end if;

  -- status and duration_minutes use the column defaults ('requested', 30).
  insert into public.appointments (patient_id, provider_id, starts_at)
  values (v_uid, v_provider, p_starts_at)
  returning id into v_id;

  return v_id;
end
$$;

comment on function public.request_appointment(timestamptz) is
  'SECURITY DEFINER because patients have no INSERT policy on appointments (a patient policy cannot limit columns, times or counts). Creates a requested appointment for the caller with the caller''s own assigned provider. Needs a provider, a time 1 hour to 90 days ahead, and fewer than 3 open requests.';

revoke all on function public.request_appointment(timestamptz) from public, anon, authenticated;
grant execute on function public.request_appointment(timestamptz) to authenticated;


-- ---------------------------------------------------------------------
-- 3. cancel_my_appointment: the caller's own future appointment
-- ---------------------------------------------------------------------
create or replace function public.cancel_my_appointment(p_id uuid)
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

  -- Own, requested or scheduled, still in the future. Anything else changes
  -- 0 rows and returns false.
  update public.appointments a
     set status = 'cancelled'
   where a.id = p_id
     and a.patient_id = auth.uid()
     and a.status in ('requested', 'scheduled')
     and a.starts_at > now();

  get diagnostics v_rows = row_count;
  return v_rows = 1;
end
$$;

comment on function public.cancel_my_appointment(uuid) is
  'SECURITY DEFINER because patients have no UPDATE policy on appointments. Sets status = cancelled on the caller''s own requested or scheduled appointment that is still in the future. Returns false for anything else (someone else''s, missing, past, already closed).';

revoke all on function public.cancel_my_appointment(uuid) from public, anon, authenticated;
grant execute on function public.cancel_my_appointment(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 4. request_reschedule: move the caller's own REQUESTED appointment
-- ---------------------------------------------------------------------
create or replace function public.request_reschedule(p_id uuid, p_new_starts_at timestamptz)
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

  -- The time rules do not depend on which appointment it is, so a bad time
  -- gives the same error for your own and for someone else's id.
  perform public.appointment_time_check(p_new_starts_at);

  -- Own, still only requested (never a confirmed one), still in the future.
  -- Only starts_at changes; the status stays 'requested'.
  update public.appointments a
     set starts_at = p_new_starts_at
   where a.id = p_id
     and a.patient_id = auth.uid()
     and a.status = 'requested'
     and a.starts_at > now();

  get diagnostics v_rows = row_count;
  return v_rows = 1;
end
$$;

comment on function public.request_reschedule(uuid, timestamptz) is
  'SECURITY DEFINER because patients have no UPDATE policy on appointments. Moves the caller''s own requested appointment (still in the future) to a new valid time; it stays requested. Never works on a scheduled (confirmed) appointment. Returns false for anything else.';

revoke all on function public.request_reschedule(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.request_reschedule(uuid, timestamptz) to authenticated;


-- ---------------------------------------------------------------------
-- 5. my_provider_name: one text value, the caller's own assigned provider
-- ---------------------------------------------------------------------
create or replace function public.my_provider_name()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;

  -- No row (no provider, or the assigned account is not a provider) leaves
  -- v_name null. A blank name also becomes null.
  select nullif(btrim(pr.display_name), '')
    into v_name
    from public.pregnancy_profiles pp
    join public.profiles pr on pr.id = pp.assigned_provider_id
   where pp.patient_id = auth.uid()
     and pr.role = 'provider';

  return v_name;
end
$$;

comment on function public.my_provider_name() is
  'SECURITY DEFINER because patients cannot read provider profiles (profiles_select). Returns only the display name (trimmed, or null) of the caller''s own assigned provider. No id, email or role.';

revoke all on function public.my_provider_name() from public, anon, authenticated;
grant execute on function public.my_provider_name() to authenticated;


-- ---------------------------------------------------------------------
-- 6. Close the direct patient write routes
-- ---------------------------------------------------------------------
drop policy if exists appointments_insert_patient on public.appointments;
drop policy if exists appointments_update_patient on public.appointments;


-- ---------------------------------------------------------------------
-- Checks (read-only). Expect 6 rows:
--   function x5  the four client functions: security_definer = true, anon can
--                run = false, signed-in can run = true; and the helper:
--                security_definer = false, anon = false, signed-in = false
--   policies     appointments_insert_provider (INSERT), appointments_select
--                (SELECT), appointments_update_provider (UPDATE) and nothing else
-- ---------------------------------------------------------------------
select 'function' as what,
       p.proname::text || '(' || pg_get_function_identity_arguments(p.oid) || '): security_definer = ' || p.prosecdef::text
       || ', anon can run = ' || has_function_privilege('anon', p.oid, 'execute')::text
       || ', signed-in can run = ' || has_function_privilege('authenticated', p.oid, 'execute')::text as detail
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('request_appointment', 'cancel_my_appointment', 'request_reschedule',
                    'my_provider_name', 'appointment_time_check')
union all
select 'policies',
       'appointments policies: ' || coalesce(
         (select string_agg(policyname::text || ' (' || cmd || ')', ', ' order by policyname)
          from pg_policies where schemaname = 'public' and tablename = 'appointments'), '(none)')
order by 1, 2;
