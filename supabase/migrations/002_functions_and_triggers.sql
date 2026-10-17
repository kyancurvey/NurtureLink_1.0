-- =====================================================================
-- 002_functions_and_triggers.sql
-- NurtureLink: signup trigger, role helpers, provider invites, alert
-- creation, language update, and the guards that keep roles safe.
--
-- WHAT IT DOES
--   1. set_updated_at()            keeps updated_at current on edited rows.
--   2. guard_profile_role()        last-line lock: the API roles (anon,
--                                  authenticated) can never set or change a role.
--   3. handle_new_user()           creates a profiles row on signup. Role is
--                                  ALWAYS 'patient'; any role in the signup
--                                  metadata is ignored.
--   4. is_provider(), is_admin(), is_assigned_provider(patient_id)
--                                  helpers that RLS policies (004) will call.
--   5. redeem_provider_invite(code)  the ONLY client-callable way to become a
--                                  provider.
--   6. create_alerts_from_reading()  turns bad readings into alerts.
--   7. set_my_language(code)       lets a user change only profiles.language.
--
-- DEPENDS ON: 000 (hardening) and 001 (tables).
--
-- SAFE TO RE-RUN: yes ("create or replace", "drop trigger if exists").
--
-- HOW TO UNDO:
--   drop trigger if exists on_auth_user_created on auth.users;
--     (if Supabase answers "must be owner of relation users", skip this line
--      and instead run "drop function public.handle_new_user() cascade;"
--      below, which removes the trigger with it)
--   drop trigger if exists belt_readings_create_alerts on public.belt_readings;
--   drop trigger if exists maternal_vitals_create_alerts on public.maternal_vitals;
--   drop trigger if exists profiles_guard_role on public.profiles;
--   drop trigger if exists profiles_set_updated_at on public.profiles;
--   (and the same "_set_updated_at" trigger on pregnancy_profiles, devices,
--    appointments, consult_notes, alert_thresholds, app_settings)
--   drop function if exists
--     public.set_updated_at(), public.guard_profile_role(), public.handle_new_user() cascade,
--     public.is_provider(), public.is_admin(), public.is_assigned_provider(uuid),
--     public.redeem_provider_invite(text), public.create_alerts_from_reading(),
--     public.set_my_language(text);
--
-- SECURITY NOTES
--   * Every SECURITY DEFINER function below sets search_path = '' and uses
--     fully qualified names, so nobody can trick it into calling a look-alike
--     object. Each one has a comment saying why it needs SECURITY DEFINER.
--   * Roles are only ever read from the profiles table. Never trust a role
--     stored in the JWT or in user_metadata: a user can edit their own
--     user_metadata.
--   * EXECUTE is revoked from PUBLIC, anon and authenticated on every function,
--     then granted back to authenticated ONLY where the app must call it.
--     anon is never granted anything.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. updated_at keeper
-- Not SECURITY DEFINER: it only edits the row being saved.
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end
$$;
revoke all on function public.set_updated_at() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'pregnancy_profiles', 'devices', 'appointments',
    'consult_notes', 'alert_thresholds', 'app_settings'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I', t || '_set_updated_at', t);
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      t || '_set_updated_at', t);
  end loop;
end
$$;


-- ---------------------------------------------------------------------
-- 2. Role guard (defence in depth)
-- Even if someone one day grants UPDATE on profiles by mistake, or writes a
-- policy that is too loose, this trigger still stops the API roles from
-- creating a non-patient profile or changing a role.
-- It is deliberately SECURITY INVOKER: current_user is then the role that is
-- really running the statement.
--   * A request from the app runs as 'authenticated' (or 'anon'): blocked.
--   * Our own SECURITY DEFINER functions (redeem_provider_invite) run as the
--     function owner, 'postgres': allowed.
--   * The SQL Editor runs as 'postgres': allowed (that is how you make the
--     admin account).
-- ---------------------------------------------------------------------
create or replace function public.guard_profile_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' and new.role <> 'patient' then
      raise exception 'role_change_not_allowed' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and new.role is distinct from old.role then
      raise exception 'role_change_not_allowed' using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;
revoke all on function public.guard_profile_role() from public, anon, authenticated;

drop trigger if exists profiles_guard_role on public.profiles;
create trigger profiles_guard_role
  before insert or update on public.profiles
  for each row execute function public.guard_profile_role();


-- ---------------------------------------------------------------------
-- 3. Signup trigger: auth.users INSERT -> profiles row
-- Role is hard-coded to 'patient'. Only date of birth and language are read
-- from the signup metadata, and bad values are replaced by safe ones so a
-- typo can never block a signup.
-- SECURITY DEFINER because the new user has no privileges on profiles, and
-- the trigger runs inside Supabase Auth's own database role.
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dob  date;
  v_lang text;
begin
  -- date of birth: accept a real date between 1900-01-01 and today, else leave empty
  begin
    v_dob := (new.raw_user_meta_data ->> 'date_of_birth')::date;
  exception when others then
    v_dob := null;
  end;
  if v_dob is not null and (v_dob < date '1900-01-01' or v_dob > current_date) then
    v_dob := null;
  end if;

  -- language: only the two we support, else English
  v_lang := new.raw_user_meta_data ->> 'language';
  if v_lang is null or v_lang not in ('en', 'fil') then
    v_lang := 'en';
  end if;

  insert into public.profiles (id, role, language, date_of_birth)
  values (new.id, 'patient', v_lang, v_dob)    -- role is ALWAYS 'patient'
  on conflict (id) do nothing;

  return new;
end
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Create the trigger only if it is missing. (No "drop trigger" here: on
-- hosted Supabase the auth tables belong to Supabase's own role, which may
-- refuse a drop. Re-running "create or replace function" above already
-- updates what the trigger does.)
do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'on_auth_user_created'
      and tgrelid = 'auth.users'::regclass
      and not tgisinternal
  ) then
    create trigger on_auth_user_created
      after insert on auth.users
      for each row execute function public.handle_new_user();
  end if;
end
$$;


-- ---------------------------------------------------------------------
-- 4. Role helpers for RLS policies (used in 004)
-- Why SECURITY DEFINER: a policy on another table needs to ask "is this user
-- a provider?" or "is this patient assigned to me?" That means reading
-- profiles and pregnancy_profiles. Doing it as the function owner lets us
-- keep those tables locked for the user, and avoids policies that call
-- themselves forever (recursion).
-- They only ever answer about the CALLER (auth.uid()), so they leak nothing.
-- ---------------------------------------------------------------------
create or replace function public.is_provider()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'provider'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

-- True only if the caller is a provider AND this patient is assigned to them.
create or replace function public.is_assigned_provider(p_patient_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_provider()
     and exists (
       select 1 from public.pregnancy_profiles pp
       where pp.patient_id = p_patient_id
         and pp.assigned_provider_id = auth.uid()
     );
$$;

revoke all on function public.is_provider()                 from public, anon, authenticated;
revoke all on function public.is_admin()                    from public, anon, authenticated;
revoke all on function public.is_assigned_provider(uuid)    from public, anon, authenticated;
grant execute on function public.is_provider()              to authenticated;
grant execute on function public.is_admin()                 to authenticated;
grant execute on function public.is_assigned_provider(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 5. redeem_provider_invite(code)
-- A signed-in PATIENT account presents a code made by the admin. If the code
-- exists, is unused and unexpired (and matches the user's confirmed email,
-- when the invite was tied to an email), the user becomes a provider and the
-- code is used up. All in one transaction.
-- Why SECURITY DEFINER: the user has no access to provider_invites or to the
-- role column. This function is the single, narrow door. It acts only on
-- auth.uid(); the caller cannot name another user.
-- Failure messages are short codes the app maps to i18n text:
--   not_signed_in, no_profile, not_eligible (already provider/admin),
--   invalid_invite (wrong, used, expired or not for this email: deliberately
--   one message, so nobody can probe which codes exist).
-- ---------------------------------------------------------------------
create or replace function public.redeem_provider_invite(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_role      text;
  v_email     text;
  v_confirmed timestamptz;
  v_invite    public.provider_invites%rowtype;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  select role into v_role from public.profiles where id = v_uid;
  if v_role is null then
    raise exception 'no_profile';
  end if;
  if v_role <> 'patient' then
    raise exception 'not_eligible';   -- never downgrade an admin, never burn a code for a provider
  end if;

  select email, email_confirmed_at into v_email, v_confirmed
  from auth.users where id = v_uid;

  -- lock the row so two people cannot redeem the same code at once
  select * into v_invite
  from public.provider_invites
  where code = upper(btrim(coalesce(p_code, '')))
    and not used
    and expires_at > now()
  for update;

  if not found then
    raise exception 'invalid_invite';
  end if;

  -- an email-bound invite needs a confirmed account with that same email
  if v_invite.email is not null
     and (v_confirmed is null or lower(v_invite.email) <> lower(coalesce(v_email, ''))) then
    raise exception 'invalid_invite';
  end if;

  update public.provider_invites
     set used = true, used_by = v_uid, used_at = now()
   where id = v_invite.id;

  -- Allowed here because this function runs as its owner (see guard_profile_role).
  update public.profiles set role = 'provider' where id = v_uid;

  insert into public.audit_log (actor_id, action, details)
  values (v_uid, 'provider_invite_redeemed', jsonb_build_object('invite_id', v_invite.id));

  return 'provider';
end
$$;
revoke all on function public.redeem_provider_invite(text) from public, anon, authenticated;
grant execute on function public.redeem_provider_invite(text) to authenticated;


-- ---------------------------------------------------------------------
-- 6. Alert creation
-- Runs after every INSERT into belt_readings and maternal_vitals.
-- Limits come from the alert_thresholds table (003 seeds the defaults, which
-- are PENDING MEDICAL OFFICER CONFIRMATION). Nothing is hard-coded here.
--
-- The rule for every alert type is the same and simple:
--   "the new reading is out of range AND the last N readings of that kind
--    for this patient were ALL out of range"   (N = sustained_count)
-- While an alert of that type is still unacknowledged (status 'open'), no
-- second one is created (see alerts_one_open_per_type_idx in 001). After
-- someone acknowledges it, the next bad reading can raise a new alert.
--
-- Why SECURITY DEFINER: patients may add their own readings but must NOT be
-- able to create, edit or suppress alerts. The alert is written by the
-- function owner instead. This is a trigger function, so nobody can call it
-- directly.
-- This is a monitoring and screening aid, not a diagnosis.
-- ---------------------------------------------------------------------
create or replace function public.create_alerts_from_reading()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  th      public.alert_thresholds%rowtype;
  v_total int;
  v_bad   int;
begin
  ----------------------------------------------------------------
  -- Belt readings: fetal heart rate and signal loss
  ----------------------------------------------------------------
  if tg_table_name = 'belt_readings' then

    -- Rule A: fetal heart rate outside the normal range, several times in a row.
    -- Readings where the belt lost the signal are ignored here (rule B covers them).
    select * into th
    from public.alert_thresholds
    where alert_type = 'fhr_out_of_range' and enabled;

    if found
       and not new.signal_lost
       and new.fetal_hr_bpm is not null
       and ((th.min_value is not null and new.fetal_hr_bpm < th.min_value)
         or (th.max_value is not null and new.fetal_hr_bpm > th.max_value))
    then
      -- look at the latest N usable readings (this one included)
      select count(*),
             count(*) filter (where (th.min_value is not null and r.fetal_hr_bpm < th.min_value)
                                 or (th.max_value is not null and r.fetal_hr_bpm > th.max_value))
        into v_total, v_bad
      from (
        select fetal_hr_bpm
        from public.belt_readings
        where patient_id = new.patient_id
          and not signal_lost
          and fetal_hr_bpm is not null
        order by measured_at desc, created_at desc
        limit th.sustained_count
      ) r;

      if v_total = th.sustained_count and v_bad = v_total then
        insert into public.alerts (patient_id, alert_type, severity, details, belt_reading_id)
        values (new.patient_id, 'fhr_out_of_range', th.severity,
                jsonb_build_object('value', new.fetal_hr_bpm, 'min', th.min_value,
                                   'max', th.max_value, 'readings', th.sustained_count),
                new.id)
        on conflict (patient_id, alert_type) where status = 'open' and alert_type <> 'sos'
        do nothing;
      end if;
    end if;

    -- Rule B: the belt lost the signal several times in a row.
    select * into th
    from public.alert_thresholds
    where alert_type = 'signal_loss' and enabled;

    if found and new.signal_lost then
      select count(*), count(*) filter (where r.signal_lost)
        into v_total, v_bad
      from (
        select signal_lost
        from public.belt_readings
        where patient_id = new.patient_id
        order by measured_at desc, created_at desc
        limit th.sustained_count
      ) r;

      if v_total = th.sustained_count and v_bad = v_total then
        insert into public.alerts (patient_id, alert_type, severity, details, belt_reading_id)
        values (new.patient_id, 'signal_loss', th.severity,
                jsonb_build_object('readings', th.sustained_count),
                new.id)
        on conflict (patient_id, alert_type) where status = 'open' and alert_type <> 'sos'
        do nothing;
      end if;
    end if;

  ----------------------------------------------------------------
  -- Maternal vitals: low oxygen and fever
  ----------------------------------------------------------------
  elsif tg_table_name = 'maternal_vitals' then

    -- Rule C: low oxygen (SpO2 below the minimum, several times in a row).
    select * into th
    from public.alert_thresholds
    where alert_type = 'low_spo2' and enabled;

    if found
       and new.spo2_percent is not null
       and th.min_value is not null
       and new.spo2_percent < th.min_value
    then
      select count(*), count(*) filter (where r.spo2_percent < th.min_value)
        into v_total, v_bad
      from (
        select spo2_percent
        from public.maternal_vitals
        where patient_id = new.patient_id and spo2_percent is not null
        order by measured_at desc, created_at desc
        limit th.sustained_count
      ) r;

      if v_total = th.sustained_count and v_bad = v_total then
        insert into public.alerts (patient_id, alert_type, severity, details, maternal_vital_id)
        values (new.patient_id, 'low_spo2', th.severity,
                jsonb_build_object('value', new.spo2_percent, 'min', th.min_value,
                                   'readings', th.sustained_count),
                new.id)
        on conflict (patient_id, alert_type) where status = 'open' and alert_type <> 'sos'
        do nothing;
      end if;
    end if;

    -- Rule D: fever (temperature above the highest normal value, several times in a row).
    select * into th
    from public.alert_thresholds
    where alert_type = 'fever' and enabled;

    if found
       and new.temperature_c is not null
       and th.max_value is not null
       and new.temperature_c > th.max_value
    then
      select count(*), count(*) filter (where r.temperature_c > th.max_value)
        into v_total, v_bad
      from (
        select temperature_c
        from public.maternal_vitals
        where patient_id = new.patient_id and temperature_c is not null
        order by measured_at desc, created_at desc
        limit th.sustained_count
      ) r;

      if v_total = th.sustained_count and v_bad = v_total then
        insert into public.alerts (patient_id, alert_type, severity, details, maternal_vital_id)
        values (new.patient_id, 'fever', th.severity,
                jsonb_build_object('value', new.temperature_c, 'max', th.max_value,
                                   'readings', th.sustained_count),
                new.id)
        on conflict (patient_id, alert_type) where status = 'open' and alert_type <> 'sos'
        do nothing;
      end if;
    end if;

  end if;

  return new;
end
$$;
revoke all on function public.create_alerts_from_reading() from public, anon, authenticated;

drop trigger if exists belt_readings_create_alerts on public.belt_readings;
create trigger belt_readings_create_alerts
  after insert on public.belt_readings
  for each row execute function public.create_alerts_from_reading();

drop trigger if exists maternal_vitals_create_alerts on public.maternal_vitals;
create trigger maternal_vitals_create_alerts
  after insert on public.maternal_vitals
  for each row execute function public.create_alerts_from_reading();


-- ---------------------------------------------------------------------
-- 7. set_my_language(code)
-- Changes ONLY profiles.language, ONLY for the signed-in user.
-- Why SECURITY DEFINER: the app then needs no UPDATE privilege on profiles at
-- all, which keeps the role column (and every other column) out of reach.
-- (updated_at is stamped automatically by the trigger in section 1.)
-- ---------------------------------------------------------------------
create or replace function public.set_my_language(p_language text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  if p_language is null or p_language not in ('en', 'fil') then
    raise exception 'invalid_language';
  end if;

  update public.profiles
     set language = p_language
   where id = auth.uid();
end
$$;
revoke all on function public.set_my_language(text) from public, anon, authenticated;
grant execute on function public.set_my_language(text) to authenticated;
