-- =====================================================================
-- 001_tables.sql
-- NurtureLink: all tables from the Data Model in PLAN.md (section 10).
--
-- WHAT IT DOES
--   Creates 16 tables with primary keys, foreign keys, timestamps, check
--   constraints and indexes, then switches Row Level Security (RLS) ON for
--   every one of them. There are no policies and no grants yet, so at the end
--   of this file nobody except the SQL Editor (postgres) can read or write
--   anything. That is intended: policies and grants come in 004.
--
-- DEPENDS ON: 000_project_hardening.sql (so the new tables get no default
--             privileges). Needs Supabase's built-in auth.users table.
--
-- SAFE TO RE-RUN: yes. "create table if not exists" and "create index if not
--   exists" skip anything that is already there. Note that it will NOT alter
--   a table that already exists with a different shape.
--
-- HOW TO UNDO (DELETES ALL DATA in these tables; fine on a fresh project):
--   drop table if exists
--     public.app_settings, public.audit_log, public.deletion_requests,
--     public.consent_records, public.consent_documents, public.validation_pairs,
--     public.consult_notes, public.appointments, public.alerts,
--     public.alert_thresholds, public.maternal_vitals, public.belt_readings,
--     public.devices, public.pregnancy_profiles, public.provider_invites,
--     public.profiles cascade;
--
-- Conventions: ids are uuid (audit_log uses a counter so it stays in order);
-- all times are timestamptz (UTC); "patient_id" always points at profiles.id,
-- which is the same value as the user's auth.users.id.
-- No table grants here. Grants come in 004.
-- =====================================================================


-- ---------------------------------------------------------------------
-- profiles: one row per signed-up user. Created by a trigger (002), never
-- by the client. "role" is the single source of truth for permissions.
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  role          text not null default 'patient'
                  check (role in ('patient', 'provider', 'admin')),
  language      text not null default 'en'
                  check (language in ('en', 'fil')),
  display_name  text check (display_name is null or char_length(display_name) <= 100),
  date_of_birth date check (date_of_birth is null or date_of_birth >= date '1900-01-01'),  -- used for the under-18 guardian check
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- provider_invites: single-use codes that let a signed-in user become a
-- provider (see redeem_provider_invite in 002). Created by the admin in the
-- SQL Editor only. If "email" is set, only that email can redeem the code.
-- ---------------------------------------------------------------------
create table if not exists public.provider_invites (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique
               check (char_length(code) >= 12 and code = upper(code)),  -- long and random so it cannot be guessed
  email      text,                                                    -- optional: tie the code to one email
  expires_at timestamptz not null,
  used       boolean not null default false,
  used_by    uuid references auth.users (id) on delete set null,
  used_at    timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at),
  check (used or (used_at is null and used_by is null))
);

-- ---------------------------------------------------------------------
-- pregnancy_profiles: one pregnancy per patient (prototype). Gestational age
-- and trimester are worked out from due_date in the app, not stored.
-- ---------------------------------------------------------------------
create table if not exists public.pregnancy_profiles (
  id                   uuid primary key default gen_random_uuid(),
  patient_id           uuid not null unique references public.profiles (id) on delete cascade,
  due_date             date,
  obstetric_history    text,
  conditions           text[] not null default '{}',
  assigned_provider_id uuid references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  check (assigned_provider_id is distinct from patient_id)
);
create index if not exists pregnancy_profiles_provider_idx
  on public.pregnancy_profiles (assigned_provider_id);

-- ---------------------------------------------------------------------
-- devices: the belt and the wrist band a patient has paired.
-- ---------------------------------------------------------------------
create table if not exists public.devices (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references public.profiles (id) on delete cascade,
  kind           text not null check (kind in ('belt', 'band')),
  label          text check (label is null or char_length(label) <= 100),
  hardware_id    text,                                                    -- e.g. Bluetooth id, set in Phase 5
  battery_percent smallint check (battery_percent between 0 and 100),
  last_seen_at   timestamptz,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists devices_patient_idx on public.devices (patient_id);

-- ---------------------------------------------------------------------
-- belt_readings: one fetal heart-rate check from the belt.
-- signal_lost = true means the belt could not get a trustworthy value
-- (fetal_hr_bpm is then normally empty). Units: bpm; quality and confidence
-- are percentages 0-100.
-- client_id lets an offline device resend a reading after reconnecting
-- without creating a duplicate (unique per patient).
-- ---------------------------------------------------------------------
create table if not exists public.belt_readings (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references public.profiles (id) on delete cascade,
  device_id      uuid references public.devices (id) on delete set null,
  measured_at    timestamptz not null default now(),
  fetal_hr_bpm   smallint check (fetal_hr_bpm between 0 and 300),
  signal_quality smallint check (signal_quality between 0 and 100),
  confidence     smallint check (confidence between 0 and 100),
  signal_lost    boolean not null default false,
  source         text not null check (source in ('device', 'simulator', 'manual')),
  client_id      uuid,
  created_at     timestamptz not null default now(),
  check (signal_lost or fetal_hr_bpm is not null),
  unique (patient_id, client_id)
);
-- "readings by patient and time"
create index if not exists belt_readings_patient_time_idx
  on public.belt_readings (patient_id, measured_at desc);

-- ---------------------------------------------------------------------
-- maternal_vitals: the mother's heart rate, oxygen (SpO2) and temperature.
-- ---------------------------------------------------------------------
create table if not exists public.maternal_vitals (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references public.profiles (id) on delete cascade,
  device_id      uuid references public.devices (id) on delete set null,
  measured_at    timestamptz not null default now(),
  heart_rate_bpm smallint check (heart_rate_bpm between 0 and 300),
  spo2_percent   smallint check (spo2_percent between 0 and 100),
  temperature_c  numeric(4, 1) check (temperature_c between 25 and 45),
  source         text not null check (source in ('device', 'simulator', 'manual')),
  client_id      uuid,
  created_at     timestamptz not null default now(),
  check (heart_rate_bpm is not null or spo2_percent is not null or temperature_c is not null),
  unique (patient_id, client_id)
);
create index if not exists maternal_vitals_patient_time_idx
  on public.maternal_vitals (patient_id, measured_at desc);

-- ---------------------------------------------------------------------
-- alert_thresholds: the limits the alert function (002) uses. One row per
-- alert type. DEFAULTS ONLY: pending medical officer confirmation.
--   min_value = lowest normal value, max_value = highest normal value
--   (a reading below min or above max is "out of range"; empty = no limit)
--   sustained_count = how many readings in a row must be out of range
-- ---------------------------------------------------------------------
create table if not exists public.alert_thresholds (
  alert_type      text primary key
                    check (alert_type in ('fhr_out_of_range', 'signal_loss', 'low_spo2', 'fever')),
  min_value       numeric,
  max_value       numeric,
  sustained_count smallint not null default 1 check (sustained_count >= 1),
  severity        text not null check (severity in ('info', 'warning', 'critical')),
  enabled         boolean not null default true,
  is_confirmed    boolean not null default false,   -- becomes true only after the medical officer signs off
  notes           text,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.profiles (id) on delete set null,
  check (min_value is null or max_value is null or min_value <= max_value)
);

-- ---------------------------------------------------------------------
-- alerts: created by the database (002), or by an SOS press (type 'sos').
-- "details" holds numbers only (value, limits, count). The screen turns them
-- into words with i18n, so no language is stored here.
-- ---------------------------------------------------------------------
create table if not exists public.alerts (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references public.profiles (id) on delete cascade,
  alert_type       text not null
                     check (alert_type in ('fhr_out_of_range', 'signal_loss', 'low_spo2', 'fever', 'sos')),
  severity         text not null check (severity in ('info', 'warning', 'critical')),
  status           text not null default 'open' check (status in ('open', 'acknowledged', 'resolved')),
  details          jsonb not null default '{}'::jsonb,
  belt_reading_id  uuid references public.belt_readings (id) on delete set null,
  maternal_vital_id uuid references public.maternal_vitals (id) on delete set null,
  action_taken     text check (action_taken is null or action_taken in ('call', 'telemedicine', 'refer_to_clinic')),
  acknowledged_by  uuid references public.profiles (id) on delete set null,
  acknowledged_at  timestamptz,
  resolved_at      timestamptz,
  created_at       timestamptz not null default now(),
  check (belt_reading_id is null or maternal_vital_id is null)
);
-- "alerts by status" (provider queue) and "alerts by patient"
create index if not exists alerts_status_time_idx  on public.alerts (status, created_at desc);
create index if not exists alerts_patient_time_idx on public.alerts (patient_id, created_at desc);
-- At most ONE unacknowledged (open) alert per patient and type, so a run of
-- bad readings does not flood the provider. SOS is excluded: every press counts.
-- Once someone acknowledges it, the next bad reading may raise a new alert.
create unique index if not exists alerts_one_open_per_type_idx
  on public.alerts (patient_id, alert_type)
  where status = 'open' and alert_type <> 'sos';

-- ---------------------------------------------------------------------
-- appointments: booking requests and visits.
-- ---------------------------------------------------------------------
create table if not exists public.appointments (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references public.profiles (id) on delete cascade,
  provider_id      uuid references public.profiles (id) on delete set null,
  starts_at        timestamptz not null,
  duration_minutes smallint not null default 30 check (duration_minutes between 5 and 480),
  status           text not null default 'requested'
                     check (status in ('requested', 'scheduled', 'completed', 'cancelled')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists appointments_patient_time_idx  on public.appointments (patient_id, starts_at);
create index if not exists appointments_provider_time_idx on public.appointments (provider_id, starts_at);

-- ---------------------------------------------------------------------
-- consult_notes: provider notes, kept in the language they were written in.
-- ---------------------------------------------------------------------
create table if not exists public.consult_notes (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references public.profiles (id) on delete cascade,
  author_id      uuid references public.profiles (id) on delete set null,
  appointment_id uuid references public.appointments (id) on delete set null,
  body           text not null check (char_length(body) between 1 and 10000),
  language       text not null check (language in ('en', 'fil')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists consult_notes_patient_time_idx on public.consult_notes (patient_id, created_at desc);

-- ---------------------------------------------------------------------
-- validation_pairs: belt value next to a Doppler value (the reference
-- device) for the validation study. Provider-only. An empty belt value means
-- the belt did not detect a heartbeat (used for the detection rate).
-- ---------------------------------------------------------------------
create table if not exists public.validation_pairs (
  id                          uuid primary key default gen_random_uuid(),
  session_id                  uuid not null,                          -- groups the pairs of one session
  patient_id                  uuid not null references public.profiles (id) on delete cascade,
  recorded_by                 uuid references public.profiles (id) on delete set null,
  belt_reading_id             uuid references public.belt_readings (id) on delete set null,
  measured_at                 timestamptz not null default now(),
  gestational_age_weeks       smallint check (gestational_age_weeks between 0 and 45),
  belt_fhr_bpm                smallint check (belt_fhr_bpm between 0 and 300),
  doppler_fhr_bpm             smallint not null check (doppler_fhr_bpm between 0 and 300),
  session_consent_confirmed   boolean not null default false,
  ob_signoff_by               uuid references public.profiles (id) on delete set null,
  ob_signoff_at               timestamptz,
  pediatrician_signoff_by     uuid references public.profiles (id) on delete set null,
  pediatrician_signoff_at     timestamptz,
  created_at                  timestamptz not null default now()
);
create index if not exists validation_pairs_session_idx on public.validation_pairs (session_id);
create index if not exists validation_pairs_patient_idx on public.validation_pairs (patient_id);

-- ---------------------------------------------------------------------
-- consent_documents: the legal texts, one row per type, version and
-- language. Written by the admin in the SQL Editor only. Never edit a
-- published row: add a new version instead, so old consents stay accurate.
-- Draft text must say "DRAFT, pending ethics/legal review".
-- ---------------------------------------------------------------------
create table if not exists public.consent_documents (
  id           uuid primary key default gen_random_uuid(),
  doc_type     text not null check (doc_type in (
                 'terms_of_use', 'privacy_notice', 'informed_consent', 'medical_disclaimer',
                 'guardian_assent', 'study_data_use', 'provider_confidentiality')),
  version      integer not null check (version >= 1),
  language     text not null check (language in ('en', 'fil')),
  title        text not null,
  body         text not null,
  is_published boolean not null default false,   -- the app only shows published rows
  published_at timestamptz,
  created_at   timestamptz not null default now(),
  unique (doc_type, version, language)
);

-- ---------------------------------------------------------------------
-- consent_records: who accepted which document and when. The version and
-- language come from the linked consent_documents row. Withdrawing sets
-- withdrawn_at; the row is kept as history. A user can hold only one ACTIVE
-- (not withdrawn) record per document.
-- ---------------------------------------------------------------------
create table if not exists public.consent_records (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  document_id  uuid not null references public.consent_documents (id) on delete restrict,
  accepted_at  timestamptz not null default now(),
  withdrawn_at timestamptz,
  check (withdrawn_at is null or withdrawn_at >= accepted_at)
);
create index if not exists consent_records_user_idx on public.consent_records (user_id);
create unique index if not exists consent_records_one_active_idx
  on public.consent_records (user_id, document_id)
  where withdrawn_at is null;

-- ---------------------------------------------------------------------
-- deletion_requests: a patient asks for their data to be deleted; the admin
-- handles it in the SQL Editor. If the patient's account is later deleted,
-- the row stays (patient_id becomes empty) as proof the request was handled.
-- ---------------------------------------------------------------------
create table if not exists public.deletion_requests (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid references public.profiles (id) on delete set null,
  status       text not null default 'pending' check (status in ('pending', 'completed', 'declined')),
  note         text check (note is null or char_length(note) <= 1000),
  requested_at timestamptz not null default now(),
  completed_at timestamptz
);
create unique index if not exists deletion_requests_one_pending_idx
  on public.deletion_requests (patient_id)
  where status = 'pending';

-- ---------------------------------------------------------------------
-- audit_log: who looked at or changed what. Append-only by design (004 will
-- allow inserts through a function and reads for providers/admin only).
-- ---------------------------------------------------------------------
create table if not exists public.audit_log (
  id         bigint generated always as identity primary key,
  actor_id   uuid references public.profiles (id) on delete set null,
  patient_id uuid references public.profiles (id) on delete set null,
  action     text not null check (char_length(action) between 1 and 64),
  details    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
-- "audit_log by patient"
create index if not exists audit_log_patient_time_idx on public.audit_log (patient_id, created_at desc);
create index if not exists audit_log_actor_time_idx   on public.audit_log (actor_id, created_at desc);

-- ---------------------------------------------------------------------
-- app_settings: key/value flags such as demo_mode. Admin-write only.
-- ---------------------------------------------------------------------
create table if not exists public.app_settings (
  key         text primary key check (char_length(key) between 1 and 64),
  value       text not null,
  description text,
  updated_at  timestamptz not null default now(),
  check (key <> 'demo_mode' or value in ('on', 'off'))
);


-- ---------------------------------------------------------------------
-- Row Level Security: ON for every table, default deny (no policies yet).
-- The event trigger from 000 does this too; doing it here as well means the
-- result is the same even if that trigger could not be created.
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'provider_invites', 'pregnancy_profiles', 'devices', 'belt_readings',
    'maternal_vitals', 'alert_thresholds', 'alerts', 'appointments', 'consult_notes',
    'validation_pairs', 'consent_documents', 'consent_records', 'deletion_requests',
    'audit_log', 'app_settings'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end
$$;
