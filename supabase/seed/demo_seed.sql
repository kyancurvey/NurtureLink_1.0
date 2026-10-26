-- =====================================================================
-- demo_seed.sql
-- NurtureLink step 2.5: SYNTHETIC demo data for 2 providers and 10 patients.
-- Every name, email, number and date here is made up. No real person, no real
-- patient data. Do not paste real data into this file.
--
-- WHAT IT DOES (all in ONE block that either finishes completely or saves
-- nothing)
--   1. REFUSES to run unless app_settings.demo_mode = 'on'.
--   2. REFUSES to run unless all 12 demo accounts already exist (see "Create
--      the demo accounts" below). It never creates or edits an account's
--      password or email, and it only ever touches those 12 accounts.
--   3. Promotes the 2 provider demo accounts to role 'provider' (the SQL
--      Editor is allowed to set roles; the app never can) and fills in demo
--      display names and dates of birth (one patient is under 18).
--   4. Gives each patient a pregnancy profile (2 in trimester 1, 5 in
--      trimester 2, 3 in trimester 3), a belt and a wrist band, 14 days of
--      belt readings (3 checks a day: about 08:00, 14:00 and 20:00 Manila
--      time) and maternal vitals, plus appointments.
--   5. Assigns patients 01-05 to provider01 and patients 06-09 to provider02.
--      patient10 is deliberately assigned to NOBODY, so you can prove that
--      neither provider can see them.
--   6. Alerts are NOT written by hand. The readings are inserted one at a
--      time, in time order, so the real alert trigger (migration 002) creates
--      them exactly as it would live:
--         patient02  2 signal losses in a row         -> no alert (below the limit)
--         patient03  1 high heart rate (163)          -> no alert (below the limit)
--         patient04  SpO2 93 then 92                  -> low_spo2 alert, acknowledged
--         patient05  3 signal losses in a row         -> signal_loss alert, open
--         patient06  FHR 108, 106, 109                -> fhr alert, resolved
--         patient08  FHR 168, 171, 166 (yesterday)    -> fhr alert, open, plus an SOS (open)
--         patient09  temperature 38.1 then 38.3       -> fever alert, open
--         patient10  FHR 104, 102, 105 (yesterday)    -> fhr alert, open (nobody can see it)
--      Everything else is normal. The seed then only back-dates the alerts to
--      the time of the reading that caused them and marks two as handled.
--      Heart-rate values stay inside the DEFAULT range for every trimester;
--      whether the range should depend on gestational age is a question for
--      the medical officer (the limits are unconfirmed defaults).
--   7. Checks its own result (expects exactly 6 generated alerts and 1 SOS)
--      and stops with an error if anything is off, so nothing half-done is
--      saved. The last query shows one summary row per patient.
--
-- IT DOES NOT create consent records. Demo accounts see the consent screen at
-- first login and must accept it themselves; faked consent would be fake
-- evidence. It also writes no consult notes, no validation pairs and no
-- audit entries.
--
-- DEPENDS ON: migrations 000 to 007 (008 recommended, run it first), the 12
-- demo accounts, and demo_mode = 'on'.
--
-- ---------------------------------------------------------------------
-- CREATE THE DEMO ACCOUNTS (once, before running this file)
-- Do NOT insert into auth.users with SQL: a hand-made row has no valid
-- password hash or identity, so the person could never sign in, and it is
-- easy to damage Auth. Do NOT use a service-role or secret key.
-- Simplest correct way, using only your own dashboard login:
--   Supabase dashboard > Authentication > Users > Add user > Create new user
--   - Email: one of the 12 addresses below, in lower case
--   - Password: a long random one per account, kept in a password manager,
--     never in the repo, a chat or a screenshot (anyone who learns a demo
--     provider password can read all demo patients and edit the shared alert
--     limits)
--   - Tick "Auto Confirm User" (email confirmation is off, and the built-in
--     email service would not deliver to these made-up addresses anyway)
--   Repeat for:
--     provider01@example.test  provider02@example.test
--     patient01@example.test ... patient10@example.test
--   The signup trigger gives each one a profile with the role 'patient';
--   this file then promotes the two providers.
--   (Alternative: use the app's sign-up screen for each. That works too, but
--   it asks for a date of birth and takes longer. If the dashboard refuses the
--   .test domain, use another made-up domain: replace "example.test" in the
--   two email lists below, in the regex at the very end, and in the undo
--   statements, then create the accounts with that domain.)
--
-- HOW TO RUN
--   1. Turn demo mode on (docs/ADMIN_SQL.md snippet 4):
--        update public.app_settings set value = 'on' where key = 'demo_mode' returning key, value;
--   2. Paste this WHOLE file into a new SQL Editor tab and click Run. If a
--      pop-up warns about "destructive operations", click Run: it deletes only
--      earlier DEMO data of the 12 demo accounts (so the file can be re-run).
--   3. Expect: 10 rows, one per patient, matching the table at the end of this
--      header. If you see an error that starts with demo_seed_refused or
--      demo_seed_self_check_failed, nothing was saved; read the message.
--
--   Expected summary (belt_readings and vitals are 39 to 42 per patient,
--   depending on the time of day you run it, because later slots today are
--   skipped):
--     patient01 T1 adult  no alerts          patient02 T1 adult  no alerts
--     patient03 T2 adult  no alerts          patient04 T2 adult  1 alert (acknowledged)
--     patient05 T2 adult  1 alert (open)     patient06 T2 adult  1 alert (resolved)
--     patient07 T2 UNDER 18  no alerts       patient08 T3 adult  2 alerts (open): FHR and SOS
--     patient09 T3 adult  1 alert (open)     patient10 T3 adult  1 alert (open), no provider
--
-- SAFE TO RE-RUN: yes. Each run first deletes the earlier DEMO readings,
-- vitals, alerts, appointments and devices of the 12 demo accounts and builds
-- them again. Anything a tester added to those 12 accounts through the app is
-- removed too. No other account is touched.
--
-- HOW TO UNDO
--   Remove only the demo data (keeps the 12 accounts):
--     delete from public.alerts       where patient_id in (select id from auth.users where lower(email) ~ '^patient(0[1-9]|10)@example\.test$');
--     delete from public.belt_readings   where patient_id in (select id from auth.users where lower(email) ~ '^patient(0[1-9]|10)@example\.test$');
--     delete from public.maternal_vitals where patient_id in (select id from auth.users where lower(email) ~ '^patient(0[1-9]|10)@example\.test$');
--     delete from public.appointments where patient_id in (select id from auth.users where lower(email) ~ '^patient(0[1-9]|10)@example\.test$');
--     delete from public.devices      where patient_id in (select id from auth.users where lower(email) ~ '^patient(0[1-9]|10)@example\.test$');
--     delete from public.pregnancy_profiles where patient_id in (select id from auth.users where lower(email) ~ '^patient(0[1-9]|10)@example\.test$');
--   Remove the demo accounts and everything linked to them (profiles,
--   consent records, ...). Do this before real users sign up, and turn demo
--   mode off afterwards (ADMIN_SQL snippet 4):
--     delete from auth.users where lower(email) ~ '^(patient(0[1-9]|10)|provider0[12])@example\.test$';
--
-- SECURITY NOTES
--   * Runs as the SQL Editor's postgres role. No key of any kind is used.
--   * The demo emails use the reserved .test domain, which can never belong to
--     a real person.
--   * With email confirmation off and open sign-up, anyone can try to sign in.
--     That is why the demo passwords must be strong and why the accounts
--     should be deleted after Demo Day.
-- =====================================================================

do $seed$
declare
  v_tz         constant text := 'Asia/Manila';
  v_today      date := (now() at time zone 'Asia/Manila')::date;

  v_prov_emails text[] := array['provider01@example.test', 'provider02@example.test'];
  v_pat_emails  text[] := array[
    'patient01@example.test', 'patient02@example.test', 'patient03@example.test',
    'patient04@example.test', 'patient05@example.test', 'patient06@example.test',
    'patient07@example.test', 'patient08@example.test', 'patient09@example.test',
    'patient10@example.test'];

  -- Per patient (position 1 = patient01 ... 10 = patient10)
  v_ga       int[] := array[12, 13, 16, 20, 24, 26, 20, 29, 36, 38];   -- gestational age in weeks today
  v_provider int[] := array[1, 1, 1, 1, 1, 2, 2, 2, 2, 0];             -- 0 = no provider assigned
  v_age      int[] := array[27, 31, 24, 29, 35, 22, 16, 33, 28, 30];   -- years
  v_age_mo   int[] := array[0, 0, 0, 0, 0, 0, 6, 0, 0, 0];             -- extra months (patient07 is 16 years 6 months)

  v_slot     time[] := array[time '08:00', time '14:00', time '20:00'];

  v_mode     text;
  v_missing  text;
  v_bad      text;
  v_prov_ids uuid[];
  v_pat_ids  uuid[];
  v_belt_dev uuid[] := '{}';
  v_band_dev uuid[] := '{}';
  v_id       uuid;
  i          int;
  k          int;
  s          int;
  v_j        int;
  v_m        timestamptz;
  v_vm       timestamptz;
  v_fhr      int;
  v_q        int;
  v_conf     int;
  v_sl       boolean;
  v_hr       int;
  v_spo2     int;
  v_temp     numeric;
  v_src      text;
  v_n        int;
begin
  ---------------------------------------------------------------------
  -- Guard 1: demo mode must be ON
  ---------------------------------------------------------------------
  select value into v_mode from public.app_settings where key = 'demo_mode';
  if v_mode is distinct from 'on' then
    raise exception 'demo_seed_refused: app_settings.demo_mode is "%" but must be "on". Turn it on with docs/ADMIN_SQL.md snippet 4, then run this file again. Nothing was saved.',
      coalesce(v_mode, 'missing');
  end if;

  ---------------------------------------------------------------------
  -- Guard 2: the 12 demo accounts must already exist
  ---------------------------------------------------------------------
  select string_agg(e, ', ' order by e) into v_missing
  from unnest(v_prov_emails || v_pat_emails) as e
  where not exists (select 1 from auth.users u where lower(u.email) = e);
  if v_missing is not null then
    raise exception 'demo_seed_refused: these demo accounts do not exist yet: %. Create them first (see "CREATE THE DEMO ACCOUNTS" at the top of this file). Nothing was saved.', v_missing;
  end if;

  select array_agg(u.id order by array_position(v_prov_emails, lower(u.email))) into v_prov_ids
  from auth.users u where lower(u.email) = any (v_prov_emails);
  select array_agg(u.id order by array_position(v_pat_emails, lower(u.email))) into v_pat_ids
  from auth.users u where lower(u.email) = any (v_pat_emails);
  if coalesce(array_length(v_prov_ids, 1), 0) <> 2 or coalesce(array_length(v_pat_ids, 1), 0) <> 10 then
    raise exception 'demo_seed_refused: expected exactly 2 provider and 10 patient accounts but found % and % (duplicate emails?). Nothing was saved.',
      coalesce(array_length(v_prov_ids, 1), 0), coalesce(array_length(v_pat_ids, 1), 0);
  end if;

  ---------------------------------------------------------------------
  -- Guard 3: roles. A patient demo account must be a patient (an account that
  -- is already a provider or the admin is not a demo account); a provider demo
  -- account needs a profile and must not be the admin.
  ---------------------------------------------------------------------
  select string_agg(u.email || ' (' || coalesce(p.role, 'no profile') || ')', ', ') into v_bad
  from auth.users u
  left join public.profiles p on p.id = u.id
  where (u.id = any (v_pat_ids)  and p.role is distinct from 'patient')
     or (u.id = any (v_prov_ids) and (p.role is null or p.role = 'admin'));
  if v_bad is not null then
    raise exception 'demo_seed_refused: these accounts cannot be used as demo accounts: %. Use fresh accounts. Nothing was saved.', v_bad;
  end if;

  ---------------------------------------------------------------------
  -- Accounts: roles, display names, dates of birth.
  -- The SQL Editor runs as postgres, which the role guard (002) allows.
  ---------------------------------------------------------------------
  update public.profiles set role = 'provider' where id = any (v_prov_ids) and role = 'patient';
  for i in 1..2 loop
    update public.profiles
       set display_name = 'Demo Provider ' || lpad(i::text, 2, '0')
     where id = v_prov_ids[i];
  end loop;
  for i in 1..10 loop
    update public.profiles
       set display_name  = 'Demo Patient ' || lpad(i::text, 2, '0'),
           date_of_birth = (v_today - make_interval(years => v_age[i], months => v_age_mo[i]))::date
     where id = v_pat_ids[i];
  end loop;

  ---------------------------------------------------------------------
  -- Clean slate for these 12 accounts only (this is what makes a re-run safe)
  ---------------------------------------------------------------------
  delete from public.alerts           where patient_id = any (v_pat_ids);
  delete from public.belt_readings    where patient_id = any (v_pat_ids);
  delete from public.maternal_vitals  where patient_id = any (v_pat_ids);
  delete from public.appointments     where patient_id = any (v_pat_ids);
  delete from public.devices          where patient_id = any (v_pat_ids);

  ---------------------------------------------------------------------
  -- Pregnancy profiles (with the provider assignment) and devices
  ---------------------------------------------------------------------
  for i in 1..10 loop
    insert into public.pregnancy_profiles (patient_id, due_date, obstetric_history, conditions, assigned_provider_id)
    values (
      v_pat_ids[i],
      v_today + ((40 - v_ga[i]) * 7),
      'DEMO (synthetic data, not a real person)',
      '{}',
      case when v_provider[i] = 0 then null else v_prov_ids[v_provider[i]] end)
    on conflict (patient_id) do update
      set due_date             = excluded.due_date,
          obstetric_history    = excluded.obstetric_history,
          assigned_provider_id = excluded.assigned_provider_id;

    insert into public.devices (patient_id, kind, label, hardware_id, battery_percent, last_seen_at, is_active)
    values (v_pat_ids[i], 'belt', 'Demo belt ' || lpad(i::text, 2, '0'), 'DEMO-BELT-' || lpad(i::text, 2, '0'),
            40 + ((i * 11) % 55), now() - (10 + i) * interval '1 minute', true)
    returning id into v_id;
    v_belt_dev := array_append(v_belt_dev, v_id);

    insert into public.devices (patient_id, kind, label, hardware_id, battery_percent, last_seen_at, is_active)
    values (v_pat_ids[i], 'band', 'Demo band ' || lpad(i::text, 2, '0'), 'DEMO-BAND-' || lpad(i::text, 2, '0'),
            35 + ((i * 13) % 60), now() - (12 + i) * interval '1 minute', true)
    returning id into v_id;
    v_band_dev := array_append(v_band_dev, v_id);
  end loop;

  ---------------------------------------------------------------------
  -- 14 days of readings and vitals.
  -- ONE insert per reading, oldest first, so the alert trigger sees the same
  -- history a live patient would produce. (A single bulk insert would let the
  -- trigger see every row at once and raise the wrong alerts.)
  -- k = days back from today (13 .. 0); s = check of the day (1 morning,
  -- 2 afternoon, 3 evening). Slots that are still in the future today are skipped.
  ---------------------------------------------------------------------
  perform setseed(0.2026);   -- same pattern on every run

  for i in 1..10 loop
    for k in reverse 13..0 loop
      for s in 1..3 loop
        v_j := floor(random() * 31)::int - 10;                                  -- -10 .. +20 minutes
        v_m := (((v_today - k) + v_slot[s]) + v_j * interval '1 minute') at time zone v_tz;
        continue when v_m > now();

        ------------------------------------------------------------ belt
        v_sl   := false;
        v_fhr  := 130 + floor(random() * 23)::int;                              -- 130 .. 152, inside the default range
        v_q    := 72 + floor(random() * 24)::int;
        v_conf := 78 + floor(random() * 20)::int;

        if    i = 2  and k = 7 and s in (1, 2)    then v_sl := true;            -- 2 losses: below the limit of 3
        elsif i = 3  and k = 5 and s = 1          then v_fhr := 163;            -- 1 high value: below the limit of 3
        elsif i = 5  and k = 2 and s in (1, 2, 3) then v_sl := true;            -- 3 losses: signal_loss alert
        elsif i = 6  and k = 8                    then v_fhr := case s when 1 then 108 when 2 then 106 else 109 end;
        elsif i = 8  and k = 1                    then v_fhr := case s when 1 then 168 when 2 then 171 else 166 end;
        elsif i = 10 and k = 1                    then v_fhr := case s when 1 then 104 when 2 then 102 else 105 end;
        end if;
        if v_sl then
          v_fhr  := null;
          v_q    := 5 + floor(random() * 16)::int;
          v_conf := null;
        end if;

        insert into public.belt_readings
          (patient_id, device_id, measured_at, fetal_hr_bpm, signal_quality, confidence, signal_lost, source, created_at)
        values
          (v_pat_ids[i], v_belt_dev[i], v_m, v_fhr, v_q, v_conf, v_sl, 'simulator', v_m);

        ------------------------------------------------------------ vitals (the band reads 2 minutes earlier)
        v_vm   := v_m - interval '2 minutes';
        v_hr   := 70 + floor(random() * 23)::int;                               -- 70 .. 92
        v_spo2 := 96 + floor(random() * 4)::int;                                -- 96 .. 99
        v_temp := round((36.4 + random() * 0.8)::numeric, 1);                   -- 36.4 .. 37.2

        if    i = 4 and k = 6 and s = 1 then v_spo2 := 93;
        elsif i = 4 and k = 6 and s = 2 then v_spo2 := 92;                      -- 2 low values in a row: low_spo2 alert
        elsif i = 9 and k = 2 and s = 3 then v_temp := 38.1;
        elsif i = 9 and k = 1 and s = 1 then v_temp := 38.3;                    -- 2 high values in a row: fever alert
        end if;

        v_src := case when (i * 7 + k * 3 + s) % 19 = 0 then 'manual' else 'simulator' end;   -- a few hand-typed entries

        insert into public.maternal_vitals
          (patient_id, device_id, measured_at, heart_rate_bpm, spo2_percent, temperature_c, source, created_at)
        values
          (v_pat_ids[i], case when v_src = 'manual' then null::uuid else v_band_dev[i] end,
           v_vm, v_hr, v_spo2, v_temp, v_src, v_vm);
      end loop;
    end loop;
  end loop;

  ---------------------------------------------------------------------
  -- Alerts: the trigger created them. Back-date each to the time of the
  -- reading that caused it, then mark two as handled and add one SOS.
  ---------------------------------------------------------------------
  update public.alerts a
     set created_at = r.measured_at + interval '1 minute'
    from public.belt_readings r
   where a.belt_reading_id = r.id and a.patient_id = any (v_pat_ids);

  update public.alerts a
     set created_at = m.measured_at + interval '1 minute'
    from public.maternal_vitals m
   where a.maternal_vital_id = m.id and a.patient_id = any (v_pat_ids);

  -- patient04: acknowledged by provider01 after a phone call
  update public.alerts
     set status = 'acknowledged', acknowledged_by = v_prov_ids[1],
         acknowledged_at = created_at + interval '40 minutes', action_taken = 'call'
   where patient_id = v_pat_ids[4] and alert_type = 'low_spo2';

  -- patient06: handled by provider02 through telemedicine, then resolved
  update public.alerts
     set status = 'resolved', acknowledged_by = v_prov_ids[2],
         acknowledged_at = created_at + interval '15 minutes', action_taken = 'telemedicine',
         resolved_at = created_at + interval '3 hours'
   where patient_id = v_pat_ids[6] and alert_type = 'fhr_out_of_range';

  -- patient08: an SOS press yesterday evening, still open
  insert into public.alerts (patient_id, alert_type, severity, status, details, created_at)
  values (v_pat_ids[8], 'sos', 'critical', 'open', '{}'::jsonb,
          (((v_today - 1) + time '21:10') at time zone v_tz));

  ---------------------------------------------------------------------
  -- Appointments
  ---------------------------------------------------------------------
  for i in 1..10 loop
    if v_provider[i] > 0 then
      insert into public.appointments (patient_id, provider_id, starts_at, status)
      values (v_pat_ids[i], v_prov_ids[v_provider[i]],
              (((v_today - 9) + time '10:00') at time zone v_tz), 'completed');

      insert into public.appointments (patient_id, provider_id, starts_at, status)
      values (v_pat_ids[i], v_prov_ids[v_provider[i]],
              (((v_today + 2 + i) + time '09:00' + (i % 4) * interval '1 hour') at time zone v_tz), 'scheduled');
    end if;
  end loop;

  insert into public.appointments (patient_id, provider_id, starts_at, status) values
    (v_pat_ids[4],  v_prov_ids[1], (((v_today + 1) + time '14:00') at time zone v_tz), 'cancelled'),
    (v_pat_ids[2],  v_prov_ids[1], (((v_today + 5) + time '11:00') at time zone v_tz), 'requested'),
    (v_pat_ids[6],  v_prov_ids[2], (((v_today + 6) + time '15:00') at time zone v_tz), 'requested'),
    (v_pat_ids[10], null,          (((v_today + 4) + time '10:00') at time zone v_tz), 'requested');

  ---------------------------------------------------------------------
  -- Self-check: stop (and save nothing) if the result is not what this file promises
  ---------------------------------------------------------------------
  select count(*) into v_n from public.belt_readings where patient_id = any (v_pat_ids);
  if v_n < 390 then
    raise exception 'demo_seed_self_check_failed: expected at least 390 belt readings but found %. Nothing was saved.', v_n;
  end if;
  select count(*) into v_n from public.maternal_vitals where patient_id = any (v_pat_ids);
  if v_n < 390 then
    raise exception 'demo_seed_self_check_failed: expected at least 390 vitals but found %. Nothing was saved.', v_n;
  end if;

  select count(*) into v_n from public.alerts
   where patient_id = any (v_pat_ids) and alert_type <> 'sos';
  if v_n <> 6 then
    raise exception 'demo_seed_self_check_failed: expected 6 generated alerts but found %. The alert limits in alert_thresholds may differ from the defaults, or the alert trigger from migration 002 is missing. Nothing was saved.', v_n;
  end if;
  select count(*) into v_n from public.alerts
   where (patient_id, alert_type) in (
           (v_pat_ids[4], 'low_spo2'),  (v_pat_ids[5], 'signal_loss'), (v_pat_ids[6], 'fhr_out_of_range'),
           (v_pat_ids[8], 'fhr_out_of_range'), (v_pat_ids[9], 'fever'), (v_pat_ids[10], 'fhr_out_of_range'));
  if v_n <> 6 then
    raise exception 'demo_seed_self_check_failed: the 6 generated alerts are not the expected ones (%). Check alert_thresholds against the defaults in migration 003. Nothing was saved.', v_n;
  end if;
  select count(*) into v_n from public.alerts where patient_id = any (v_pat_ids) and alert_type = 'sos';
  if v_n <> 1 then
    raise exception 'demo_seed_self_check_failed: expected 1 SOS alert but found %. Nothing was saved.', v_n;
  end if;
end
$seed$;


-- ---------------------------------------------------------------------
-- Summary: one row per patient (expect 10 rows; see the table in the header)
-- ---------------------------------------------------------------------
select
  u.email                                   as patient,
  coalesce(pv.email, '(no provider)')       as provider,
  w.weeks                                   as gestational_weeks,
  case when w.weeks < 14 then 1 when w.weeks < 28 then 2 else 3 end as trimester,
  case when p.date_of_birth > (now() at time zone 'Asia/Manila')::date - interval '18 years'
       then 'under 18' else 'adult' end     as age_group,
  (select count(*) from public.belt_readings  b  where b.patient_id  = u.id) as belt_readings,
  (select count(*) from public.maternal_vitals v where v.patient_id  = u.id) as vitals,
  (select count(*) from public.alerts a  where a.patient_id  = u.id)         as alerts,
  (select count(*) from public.alerts a  where a.patient_id  = u.id and a.status = 'open') as open_alerts,
  (select count(*) from public.appointments ap where ap.patient_id = u.id)   as appointments
from auth.users u
join public.profiles p            on p.id = u.id
join public.pregnancy_profiles pp on pp.patient_id = u.id
left join auth.users pv           on pv.id = pp.assigned_provider_id
cross join lateral (select 40 - ((pp.due_date - (now() at time zone 'Asia/Manila')::date) / 7) as weeks) w
where lower(u.email) ~ '^patient(0[1-9]|10)@example\.test$'
order by u.email;
