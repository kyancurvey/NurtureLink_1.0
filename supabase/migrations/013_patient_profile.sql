-- =====================================================================
-- 013_patient_profile.sql
-- NurtureLink step 3.5 (Profile tab): two client functions that become the ONLY
-- way to write a display name and the pregnancy details.
--
-- WHAT IT DOES
--   1. Two small helpers (text_has_bad_chars, nl_trim_text). Nobody can run them
--      from the API; only the two functions below use them.
--   2. public.set_my_display_name(p_name text) returns text
--        Sets profiles.display_name for the CALLER only.
--          - null, empty or blank after trimming  -> display_name becomes NULL
--            (clearing is allowed, never an error)
--          - control characters, line breaks and invisible zero-width or
--            text-direction characters  -> error 'display_name_invalid'
--          - more than 100 characters after trimming -> 'display_name_invalid'
--          - otherwise the trimmed text is stored literally (markup characters
--            such as < > & " ' are kept as typed; nothing is escaped or stripped)
--        Returns the stored text (null when cleared).
--   3. public.save_pregnancy_details(p_due_date date, p_obstetric_history text,
--                                    p_conditions text[]) returns void
--        Creates or updates the CALLER's own pregnancy_profiles row in one step
--        (a new patient has no row yet; calling it twice never makes two rows).
--        It never touches assigned_provider_id.
--        LIMITS (all DRAFT, pending medical officer):
--          - due date: empty allowed. Otherwise from 14 days ago to 280 days
--            ahead on the Asia/Manila calendar date, checked ONLY when the value
--            differs from the stored one (so an old date never blocks editing the
--            other fields)                                   -> 'due_date_out_of_range'
--          - obstetric history: at most 1000 characters after trimming; a blank
--            becomes empty (NULL); line breaks are allowed (CRLF is stored as LF);
--            other control and invisible characters are refused -> 'history_invalid'
--          - conditions: at most 10 entries after cleaning; each trimmed, 1 to 60
--            characters, no control, line-break or invisible characters; blank
--            entries are dropped; duplicates ignoring case are dropped (the first
--            spelling stays); a NULL element is refused         -> 'conditions_invalid'
--   4. Closes the direct write routes (the 3.3 / 3.4 pattern):
--        revoke update (display_name) on public.profiles from authenticated;
--        revoke insert, update on public.pregnancy_profiles from authenticated;
--      Language still works (set_my_language, and the direct language grant stays).
--      pregnancy_profiles keeps SELECT only, so assigned_provider_id is now
--      unwritable by construction, not just by a column list.
--
-- WHY SECURITY DEFINER: `authenticated` is one shared role for patients and
-- providers and grants are per column, not per row or per rule. The functions run
-- as their owner so the clients need no write privilege on these tables at all,
-- and they act only on auth.uid() (never on an id the client sends). The same
-- set_my_display_name serves providers in Phase 4.
--
-- WHO STILL WRITES THESE TABLES DIRECTLY (all run as postgres, which is unaffected):
--   the signup trigger (profiles only), ADMIN_SQL snippet 5 (assignment),
--   supabase/seed/demo_seed.sql and the SQL test fixtures.
--
-- DEPENDS ON: 000 to 012 already run.
-- SAFE TO RE-RUN: yes ("create or replace", revoke is repeatable, grants repeated).
--
-- HOW TO UNDO (restores the 3.4 state, direct writes again):
--   drop function if exists public.set_my_display_name(text);
--   drop function if exists public.save_pregnancy_details(date, text, text[]);
--   drop function if exists public.text_has_bad_chars(text, boolean);
--   drop function if exists public.nl_trim_text(text);
--   grant update (display_name) on public.profiles to authenticated;
--   grant insert (patient_id, due_date, obstetric_history, conditions) on public.pregnancy_profiles to authenticated;
--   grant update (due_date, obstetric_history, conditions) on public.pregnancy_profiles to authenticated;
--
-- NOTE: 004_grants.sql was edited in the same step (line 97 and lines 103-104)
-- so that re-running 004 does not reopen these routes. The edited 004 has not
-- been re-run live; 013 itself makes the same change.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Helpers (invoker rights, nobody can run them from the API)
-- ---------------------------------------------------------------------

-- true when the text holds a character we refuse: control characters (0001-001F,
-- 007F-009F), zero-width and text-direction characters (200B-200F, 2028-202E,
-- 2060-206F, 061C, 180E, FEFF). With p_allow_newline the line feed (000A) is
-- allowed (obstetric history); everything else in that list is still refused.
create or replace function public.text_has_bad_chars(p_text text, p_allow_newline boolean default false)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_text is null then false
    when p_allow_newline
      then p_text ~ '[\u0001-\u0009\u000b-\u001f\u007f-\u009f\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]'
    else p_text ~ '[\u0001-\u001f\u007f-\u009f\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]'
  end
$$;

-- Trims white space (including no-break and ideographic spaces) from both ends.
create or replace function public.nl_trim_text(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(p_text, '^[\s\u00a0\u3000]+|[\s\u00a0\u3000]+$', '', 'g')
$$;

revoke all on function public.text_has_bad_chars(text, boolean) from public, anon, authenticated;
revoke all on function public.nl_trim_text(text) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 2. set_my_display_name
-- ---------------------------------------------------------------------
create or replace function public.set_my_display_name(p_name text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;

  -- Bad characters are judged on the text as sent (a leading line break is
  -- refused, not silently trimmed).
  if public.text_has_bad_chars(p_name, false) then
    raise exception 'display_name_invalid';
  end if;

  v_name := public.nl_trim_text(p_name);
  if v_name is null or v_name = '' then
    v_name := null;                           -- clearing is allowed
  elsif char_length(v_name) > 100 then
    raise exception 'display_name_invalid';
  end if;

  update public.profiles
     set display_name = v_name
   where id = auth.uid();
  if not found then
    raise exception 'no_profile';
  end if;

  return v_name;
end
$$;

comment on function public.set_my_display_name(text) is
  'SECURITY DEFINER because authenticated has no UPDATE privilege on profiles.display_name (013). Changes only the caller''s own display name; blank clears it; control, line-break and invisible characters and names over 100 characters raise display_name_invalid.';

revoke all on function public.set_my_display_name(text) from public, anon, authenticated;
grant execute on function public.set_my_display_name(text) to authenticated;


-- ---------------------------------------------------------------------
-- 3. save_pregnancy_details
-- ---------------------------------------------------------------------
create or replace function public.save_pregnancy_details(
  p_due_date date,
  p_obstetric_history text,
  p_conditions text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- DRAFT, pending medical officer. Repeated in src/lib/gestation.js (form hints).
  c_past_days   constant integer := 14;     -- due date up to 14 days ago (42w0d)
  c_ahead_days  constant integer := 280;    -- due date up to 280 days ahead (0w0d)
  c_history_max constant integer := 1000;   -- characters
  c_cond_max    constant integer := 10;     -- entries
  c_cond_len    constant integer := 60;     -- characters per entry
  c_cond_raw    constant integer := 100;    -- refuse absurd arrays before working on them

  v_uid     uuid := auth.uid();
  v_today   date := (now() at time zone 'Asia/Manila')::date;
  v_old     date;
  v_hist    text;
  v_cond    text[];
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  -- Due date: only a CHANGED value has to be inside the window.
  select pp.due_date into v_old from public.pregnancy_profiles pp where pp.patient_id = v_uid;
  if p_due_date is not null and p_due_date is distinct from v_old then
    if p_due_date < v_today - c_past_days or p_due_date > v_today + c_ahead_days then
      raise exception 'due_date_out_of_range';
    end if;
  end if;

  -- Obstetric history: CRLF counts as one line break; then characters, then length.
  v_hist := replace(p_obstetric_history, E'\r\n', E'\n');
  if public.text_has_bad_chars(v_hist, true) then
    raise exception 'history_invalid';
  end if;
  v_hist := public.nl_trim_text(v_hist);
  if v_hist = '' then
    v_hist := null;
  elsif char_length(v_hist) > c_history_max then
    raise exception 'history_invalid';
  end if;

  -- Conditions.
  if p_conditions is null then
    v_cond := '{}';
  else
    if cardinality(p_conditions) > c_cond_raw
       or exists (select 1 from unnest(p_conditions) as u(c) where u.c is null)
       or exists (select 1 from unnest(p_conditions) as u(c) where public.text_has_bad_chars(u.c, false))
    then
      raise exception 'conditions_invalid';
    end if;
    select coalesce(array_agg(d.v order by d.ord), '{}')
      into v_cond
      from (select distinct on (lower(s.v)) s.v, s.ord
              from (select public.nl_trim_text(u.c) as v, u.ord
                      from unnest(p_conditions) with ordinality as u(c, ord)) s
             where s.v <> ''
             order by lower(s.v), s.ord) d;
    if cardinality(v_cond) > c_cond_max
       or exists (select 1 from unnest(v_cond) as u(c) where char_length(u.c) > c_cond_len)
    then
      raise exception 'conditions_invalid';
    end if;
  end if;

  -- Create or update the caller's own row. assigned_provider_id is not in either
  -- column list, so it is never set here and never changed.
  insert into public.pregnancy_profiles (patient_id, due_date, obstetric_history, conditions)
  values (v_uid, p_due_date, v_hist, v_cond)
  on conflict (patient_id) do update
     set due_date          = excluded.due_date,
         obstetric_history = excluded.obstetric_history,
         conditions        = excluded.conditions;
end
$$;

comment on function public.save_pregnancy_details(date, text, text[]) is
  'SECURITY DEFINER because authenticated has no INSERT or UPDATE privilege on pregnancy_profiles (013). Creates or updates only the caller''s own row; never touches assigned_provider_id. Limits are DRAFT, pending medical officer.';

revoke all on function public.save_pregnancy_details(date, text, text[]) from public, anon, authenticated;
grant execute on function public.save_pregnancy_details(date, text, text[]) to authenticated;


-- ---------------------------------------------------------------------
-- 4. Close the direct write routes
-- ---------------------------------------------------------------------
revoke update (display_name) on public.profiles from authenticated;
revoke insert, update on public.pregnancy_profiles from authenticated;


-- ---------------------------------------------------------------------
-- Checks (read-only). Expect 6 rows:
--   function x4  set_my_display_name and save_pregnancy_details:
--                security_definer = true, anon = false, signed-in = true;
--                the two helpers: security_definer = false, anon = false, signed-in = false
--   column grants  profiles.display_name UPDATE = false, profiles.language UPDATE = true
--   table grants   pregnancy_profiles: SELECT true, INSERT false, UPDATE false
-- ---------------------------------------------------------------------
select 'function' as what, p.proname::text as name, p.prosecdef as security_definer,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_run,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as signed_in_can_run
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('set_my_display_name', 'save_pregnancy_details', 'text_has_bad_chars', 'nl_trim_text')
union all
select 'column grants', 'profiles.display_name / language update',
       has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE'),
       null,
       has_column_privilege('authenticated', 'public.profiles', 'language', 'UPDATE')
union all
select 'table grants', 'pregnancy_profiles select / insert / update',
       has_table_privilege('authenticated', 'public.pregnancy_profiles', 'SELECT'),
       has_table_privilege('authenticated', 'public.pregnancy_profiles', 'INSERT')
         or has_column_privilege('authenticated', 'public.pregnancy_profiles', 'due_date', 'INSERT'),
       has_table_privilege('authenticated', 'public.pregnancy_profiles', 'UPDATE')
         or has_column_privilege('authenticated', 'public.pregnancy_profiles', 'due_date', 'UPDATE');
