import { useCallback, useEffect, useState } from 'react'
import { supabase } from './supabase.js'
import { useAuth } from './auth.jsx'

// Small data hooks for the patient Home tab (step 3.1). Each one reads only the
// signed-in patient's own rows; the database (grants plus RLS, migrations 004
// and 005) is what really enforces that, the .eq('patient_id', ...) is only so
// the query uses the right index.
//
// Every hook returns { data, error, loading, loaded, reload }:
//   loaded   false until the first answer (or error) has arrived
//   loading  true while a request is running (including a reload)
//   error    the raw error; show it with friendlyError(t, error)
//   data     the last good answer, or null (null also means "no rows")
// A failed request never turns into "empty" or "normal": error is set and data
// is null, so the screen can say it could not load.

// UI wording only, not clinical limits: below this battery level the screen
// adds the words "Low battery". Pending review with the other wording.
export const LOW_BATTERY_PERCENT = 20

// UI wording only: how the signal confidence number is described. The number
// itself is always shown too. Pending review.
export function confidenceLevel(percent) {
  if (percent === null || percent === undefined) return null
  if (percent >= 80) return 'high'
  if (percent >= 50) return 'medium'
  return 'low'
}

function useQuery(run, key) {
  const [state, setState] = useState({ data: null, error: null, loading: true, loaded: false })
  const [tick, setTick] = useState(0)
  const reload = useCallback(() => setTick((n) => n + 1), [])

  useEffect(() => {
    if (!supabase || !key) {
      setState({
        data: null,
        error: supabase ? null : { message: 'not_configured' },
        loading: false,
        loaded: !supabase,
      })
      return undefined
    }
    let live = true
    setState((s) => ({ ...s, loading: true }))
    Promise.resolve()
      .then(run)
      .then(({ data, error }) => {
        if (live) setState({ data: error ? null : data, error: error ?? null, loading: false, loaded: true })
      })
      .catch((error) => {
        if (live) setState({ data: null, error, loading: false, loaded: true })
      })
    return () => {
      live = false
    }
    // `run` is a new function on every render on purpose; only the patient and
    // a reload request should start a new request.
  }, [key, tick])

  return { ...state, reload }
}

function usePatientId() {
  const { profile } = useAuth()
  return profile?.id ?? null
}

// The newest belt check, including one where the signal was lost.
export function useLatestReading() {
  const id = usePatientId()
  return useQuery(
    () =>
      supabase
        .from('belt_readings')
        .select('measured_at, fetal_hr_bpm, signal_quality, confidence, signal_lost, source')
        .eq('patient_id', id)
        .order('measured_at', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle(),
    id,
  )
}

// The newest value of each vital sign, with its own time. A vitals row may hold
// only some of the three values, so each one is taken from the newest row that
// has it. data = { hr, spo2, temp }, each { value, measured_at } or null.
export function useLatestVitals() {
  const id = usePatientId()
  return useQuery(async () => {
    const { data, error } = await supabase
      .from('maternal_vitals')
      .select('measured_at, heart_rate_bpm, spo2_percent, temperature_c')
      .eq('patient_id', id)
      .order('measured_at', { ascending: false })
      .order('created_at', { ascending: false })
      .limit(20)
    if (error) return { data: null, error }
    const pick = (field) => {
      const row = (data ?? []).find((r) => r[field] !== null && r[field] !== undefined)
      return row ? { value: Number(row[field]), measured_at: row.measured_at } : null
    }
    return {
      data: { hr: pick('heart_rate_bpm'), spo2: pick('spo2_percent'), temp: pick('temperature_c') },
      error: null,
    }
  }, id)
}

// The status verdict from the database (migration 009, my_home_status()).
// data = { status: 'urgent' | 'attention' | 'ok' | 'no_recent_data', reasons: [...],
//          fresh_hours, fresh_belt, fresh_vitals, latest_belt_at, latest_vitals_at }
// The screen never works out the status itself and never reads the alert limits.
export function useHomeStatus() {
  const id = usePatientId()
  return useQuery(() => supabase.rpc('my_home_status'), id)
}

// The next appointment that is still ahead (requested or scheduled).
// The "still ahead" test uses this device's clock; it only decides what is
// listed, nothing is stored from it.
export function useNextAppointment() {
  const id = usePatientId()
  return useQuery(async () => {
    const { data, error } = await supabase
      .from('appointments')
      .select('id, starts_at, status')
      .eq('patient_id', id)
      .in('status', ['requested', 'scheduled'])
      .order('starts_at', { ascending: true })
    if (error) return { data: null, error }
    const now = Date.now()
    const next = (data ?? []).find((a) => new Date(a.starts_at).getTime() >= now)
    return { data: next ?? null, error: null }
  }, id)
}

// The patient's active devices. data = array (maybe empty) of
// { id, kind: 'belt' | 'band', label, battery_percent, last_seen_at }.
export function useDevices() {
  const id = usePatientId()
  return useQuery(
    () =>
      supabase
        .from('devices')
        .select('id, kind, label, battery_percent, last_seen_at')
        .eq('patient_id', id)
        .eq('is_active', true)
        .order('kind', { ascending: true }),
    id,
  )
}

// Does the patient have a provider assigned? Read from their own pregnancy
// profile (assigned_provider_id is set only by the admin).
// `assigned` is true, false, or null while unknown or when it could not be read.
// Callers must treat null like false when the wording would otherwise promise
// that someone will respond.
export function useProviderAssigned() {
  const id = usePatientId()
  const q = useQuery(async () => {
    const { data, error } = await supabase
      .from('pregnancy_profiles')
      .select('assigned_provider_id')
      .eq('patient_id', id)
      .maybeSingle()
    if (error) return { data: null, error }
    return { data: { assigned: !!data?.assigned_provider_id }, error: null }
  }, id)
  return { ...q, assigned: q.data ? q.data.assigned : null }
}

// Raise an SOS for the signed-in patient. The database (migration 009) refuses a
// second one within 5 minutes with the message 'sos_rate_limited'.
// Returns { error } (null on success). The saved row is not asked for back.
export async function sendSos(patientId) {
  if (!supabase) return { error: { message: 'not_configured' } }
  const { error } = await supabase
    .from('alerts')
    .insert({ patient_id: patientId, alert_type: 'sos', severity: 'critical' })
  return { error: error ?? null }
}

// ---------------------------------------------------------------------
// Step 3.2: Monitor tab
// ---------------------------------------------------------------------

// Plausible ENTRY limits for hand-typed values. These are data-entry sanity
// checks, NOT the clinical alert limits (those live in alert_thresholds). They
// repeat the numbers in migration 010 (guard_manual_reading), which is the
// real check; the form uses them only to warn before saving. Pending review.
export const MANUAL_LIMITS = {
  fhr: { min: 60, max: 220 },
  hr: { min: 30, max: 220 },
  spo2: { min: 70, max: 100 },
  temp: { min: 34, max: 42 },
}

// UI wording only, not a clinical limit: a belt check with a signal quality
// below this counts as "poor" for the Adjust belt guidance. Same 50 as the
// "Low" confidence label. Pending review.
export const POOR_SIGNAL_QUALITY = 50

// Chart ranges: how far back each one looks. The window is worked out on this
// device's clock; it only decides which rows are listed, nothing is stored.
const HOUR = 60 * 60 * 1000
export const TREND_RANGES = { day: 24 * HOUR, week: 7 * 24 * HOUR, month: 30 * 24 * HOUR }
const TREND_ROW_LIMIT = 1000 // the API returns at most 1000 rows; the newest are kept
export const HISTORY_PAGE = 20

// The normal-range limits for the chart band (migration 010, my_normal_ranges()).
// data = { fhr?: {min?, max?, confirmed}, spo2?: {...}, temp?: {...} }. A limit
// that is disabled is missing. The screen never reads alert_thresholds itself.
export function useNormalRanges() {
  const id = usePatientId()
  return useQuery(() => supabase.rpc('my_normal_ranges'), id)
}

// Belt readings and vitals for the chart window, oldest first.
// data = { range, since, until, belt: [...], vitals: [...], truncated }  (since and until in ms;
// range says which window the rows belong to, so the screen never shows old rows under a new range)
export function useTrends(range) {
  const id = usePatientId()
  return useQuery(
    async () => {
      const until = Date.now()
      const since = until - TREND_RANGES[range]
      const from = new Date(since).toISOString()
      const [belt, vitals] = await Promise.all([
        supabase
          .from('belt_readings')
          .select('measured_at, fetal_hr_bpm, signal_quality, signal_lost, source')
          .eq('patient_id', id)
          .gte('measured_at', from)
          .order('measured_at', { ascending: false })
          .limit(TREND_ROW_LIMIT),
        supabase
          .from('maternal_vitals')
          .select('measured_at, heart_rate_bpm, spo2_percent, temperature_c, source')
          .eq('patient_id', id)
          .gte('measured_at', from)
          .order('measured_at', { ascending: false })
          .limit(TREND_ROW_LIMIT),
      ])
      const error = belt.error ?? vitals.error
      if (error) return { data: null, error }
      return {
        data: {
          range,
          since,
          until,
          belt: [...(belt.data ?? [])].reverse(),
          vitals: [...(vitals.data ?? [])].reverse(),
          truncated: (belt.data ?? []).length >= TREND_ROW_LIMIT || (vitals.data ?? []).length >= TREND_ROW_LIMIT,
        },
        error: null,
      }
    },
    id ? `${id}:trend:${range}` : null,
  )
}

// The check history, newest first. Asks for one row more than `limit` so the
// screen knows whether "Show more" is needed. Raising `limit` fetches again;
// the previous rows stay on screen meanwhile.
export function useBeltHistory(limit) {
  const id = usePatientId()
  return useQuery(
    () =>
      supabase
        .from('belt_readings')
        .select('id, measured_at, fetal_hr_bpm, signal_quality, confidence, signal_lost, source')
        .eq('patient_id', id)
        .order('measured_at', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(limit + 1),
    id ? `${id}:hist:${limit}` : null,
  )
}

// Fresh ids for one manual entry form. Created once when the form is shown (not
// per tap), so a double tap or a retry cannot save the same entry twice: the
// database refuses a repeated client_id (unique per patient, 23505) and the
// helper below treats that as "already saved".
export function newManualIds() {
  const make = () =>
    typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function' ? crypto.randomUUID() : undefined
  return { belt: make(), vitals: make() }
}

// For testing the "wrong phone clock" message once in the real app, like
// TEST_CLOCK_SKEW_MINUTES in deviceSimulator.js. Keep it at 0. To test: set it
// to 30, upload, save a manual reading, expect the friendly message, set it back to 0.
const TEST_MANUAL_CLOCK_SKEW_MINUTES = 0

// Save a hand-typed entry for the signed-in patient.
//   values = { fhr, hr, spo2, temp } numbers; fhr is required, the rest may be null.
// Rows are stored with source 'manual', no device and the SERVER time
// (measured_at is left out). Migration 010 checks the values again.
// Returns { error, savedBelt }. If the baby heart rate was saved but the
// vitals failed, error is set and savedBelt is true; pressing Save again with
// the same ids saves only what is missing (a repeat is a 23505, treated as saved).
export async function saveManualReading({ patientId, values, ids }) {
  if (!supabase) return { error: { message: 'not_configured' }, savedBelt: false }
  const when =
    TEST_MANUAL_CLOCK_SKEW_MINUTES > 0
      ? { measured_at: new Date(Date.now() + TEST_MANUAL_CLOCK_SKEW_MINUTES * 60000).toISOString() }
      : {}
  const alreadySaved = (e) => e && e.code === '23505'

  const belt = await supabase.from('belt_readings').insert({
    patient_id: patientId,
    fetal_hr_bpm: values.fhr,
    signal_lost: false,
    source: 'manual',
    client_id: ids.belt,
    ...when,
  })
  if (belt.error && !alreadySaved(belt.error)) return { error: belt.error, savedBelt: false }

  const hasVitals = [values.hr, values.spo2, values.temp].some((v) => v !== null && v !== undefined)
  if (!hasVitals) return { error: null, savedBelt: true }

  const vitals = await supabase.from('maternal_vitals').insert({
    patient_id: patientId,
    heart_rate_bpm: values.hr ?? null,
    spo2_percent: values.spo2 ?? null,
    temperature_c: values.temp ?? null,
    source: 'manual',
    client_id: ids.vitals,
    ...when,
  })
  if (vitals.error && !alreadySaved(vitals.error)) return { error: vitals.error, savedBelt: true }
  return { error: null, savedBelt: true }
}
