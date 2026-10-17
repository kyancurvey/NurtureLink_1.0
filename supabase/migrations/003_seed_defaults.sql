-- =====================================================================
-- 003_seed_defaults.sql
-- NurtureLink: default alert limits and the demo_mode switch. No patient data.
--
-- WHAT IT DOES
--   Adds 4 rows to alert_thresholds and 1 row to app_settings.
--   ALL THRESHOLDS BELOW ARE DEFAULTS, PENDING MEDICAL OFFICER CONFIRMATION.
--   They are a starting point for building and testing, not clinical advice.
--   After the medical officer decides, edit them (Provider > Settings later,
--   or the SQL Editor) and set is_confirmed = true.
--
-- DEPENDS ON: 001_tables.sql. (002 makes the alert function read these rows.)
--
-- SAFE TO RE-RUN: yes. "on conflict do nothing" means a re-run never
--   overwrites a value that has since been changed.
--
-- HOW TO UNDO:
--   delete from public.alert_thresholds
--     where alert_type in ('fhr_out_of_range', 'signal_loss', 'low_spo2', 'fever');
--   delete from public.app_settings where key = 'demo_mode';
-- =====================================================================

-- min_value = lowest normal value, max_value = highest normal value.
-- A reading below min or above max is "out of range".
-- sustained_count = how many readings in a row must be out of range.
insert into public.alert_thresholds
  (alert_type, min_value, max_value, sustained_count, severity, is_confirmed, notes)
values
  ('fhr_out_of_range', 110,  160,  3, 'critical', false,
   'DEFAULT, pending medical officer confirmation. Fetal heart rate normal range 110-160 bpm; alert after 3 usable readings in a row outside it.'),
  ('signal_loss',      null, null, 3, 'warning',  false,
   'DEFAULT, pending medical officer confirmation. Alert after 3 belt readings in a row with no usable signal.'),
  ('low_spo2',         95,   null, 2, 'warning',  false,
   'DEFAULT, pending medical officer confirmation. Alert when maternal SpO2 is below 95 percent on 2 readings in a row.'),
  ('fever',            null, 37.9, 2, 'warning',  false,
   'DEFAULT, pending medical officer confirmation. max_value is the highest normal temperature in deg C, so an alert means 38.0 or above on 2 readings in a row.')
on conflict (alert_type) do nothing;

-- Demo Mode is OFF by default. Turn it on or off with docs/ADMIN_SQL.md.
insert into public.app_settings (key, value, description)
values ('demo_mode', 'off', 'on = seeded demo data and simulated device stream; off = live mode')
on conflict (key) do nothing;
