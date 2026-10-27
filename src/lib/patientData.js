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
