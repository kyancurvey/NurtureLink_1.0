import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from './supabase.js'
import { useAuth } from './auth.jsx'
import { AUDIT, writeAudit } from './audit.js'

// Data hooks for the provider Overview tab (step 4.1). Patient hooks live in
// patientData.js and are not touched.
//
// What is read, and who limits it:
//  - provider_overview() (migration 015): the triage list of the signed-in
//    provider's ASSIGNED patients, already sorted by priority. It runs with the
//    caller's own rights, returns nothing unless the caller is a provider, and
//    filters by assignment itself. The status, the missed-check flag and the sort
//    order are decided in the database, never here.
//  - alerts: the OPEN alerts. Row-level security (005) lets a provider read only
//    alerts of assigned patients. Only the columns named below are asked for;
//    never `details`.
// Nothing about a patient's identity is asked for beyond the display name the patient chose.

// DRAFT timing choices (screen behaviour only, not clinical limits).
export const OVERVIEW_REFETCH_MS = 5 * 60 * 1000 // time-based flags and new readings are not pushed live
export const OVERVIEW_FALLBACK_MS = 30 * 1000 // while live updates are paused
export const OVERVIEW_DEBOUNCE_MS = 2000 // a burst of alert events causes one refetch
export const OPEN_ALERTS_LIMIT = 100
const AUDIT_RETRY_MS = 3000

const ALERT_FIELDS = 'id, patient_id, alert_type, severity, created_at, seen_by_patient_at'

let overviewChannelCount = 0

// One audit row per page load of the app for each provider (module memory, so a
// browser refresh starts again; moving between tabs does not). It is written by
// the app, so a modified client can skip it: a trace, not a guarantee. It never
// blocks the screen: it is fire-and-forget, retried once quietly, and a failure
// is never shown. Only a count is stored, no patient ids.
let auditedFor = null

async function recordOverviewView(providerId, count) {
  if (!providerId || auditedFor === providerId) return
  auditedFor = providerId
  const attempt = () => writeAudit(AUDIT.OVERVIEW_VIEWED, { details: { count } })
  let { ok } = await attempt()
  if (!ok) {
    await new Promise((resolve) => setTimeout(resolve, AUDIT_RETRY_MS))
    ;({ ok } = await attempt())
  }
  // Both attempts failed: let a later visit try again instead of losing the trace for good.
  if (!ok && auditedFor === providerId) auditedFor = null
}

async function fetchOverview() {
  try {
    const [list, alerts] = await Promise.all([
      supabase.rpc('provider_overview'),
      supabase
        .from('alerts')
        .select(ALERT_FIELDS)
        .eq('status', 'open')
        .order('created_at', { ascending: false })
        .limit(OPEN_ALERTS_LIMIT),
    ])
    const error = list.error ?? alerts.error
    if (error) return { error }
    return { error: null, patients: list.data ?? [], alerts: alerts.data ?? [] }
  } catch (error) {
    return { error }
  }
}

// Returns { patients, alerts, error, loaded, refreshFailed, live, reload }.
//   patients  rows of provider_overview(), in priority order (null until loaded)
//   alerts    open alerts, newest first (null until loaded)
//   error     the raw error of the FIRST load; show it with friendlyError(t, error)
//   refreshFailed  true when a later refresh failed but an earlier list is still shown
//   live      'connecting' | 'live' | 'paused' (paused: refetching every 30 seconds)
// A failed request never turns into an empty or a "stable" list.
export function useProviderOverview() {
  const { profile } = useAuth()
  const id = profile?.id ?? null
  const [state, setState] = useState({ patients: null, alerts: null, error: null, loaded: false, refreshFailed: false })
  const [live, setLive] = useState('connecting')
  const latest = useRef(0) // only the newest request may change the screen
  const debounce = useRef(null)

  const load = useCallback(async () => {
    if (!supabase || !id) return
    const mine = ++latest.current
    const result = await fetchOverview()
    if (mine !== latest.current) return
    if (result.error) {
      setState((s) =>
        s.patients
          ? { ...s, refreshFailed: true }
          : { patients: null, alerts: null, error: result.error, loaded: true, refreshFailed: false },
      )
    } else {
      setState({ patients: result.patients, alerts: result.alerts, error: null, loaded: true, refreshFailed: false })
      recordOverviewView(id, result.patients.length)
    }
  }, [id])

  // First load (and a new load if the signed-in provider changes).
  useEffect(() => {
    if (!supabase) {
      setState({ patients: null, alerts: null, error: { message: 'not_configured' }, loaded: true, refreshFailed: false })
      return undefined
    }
    setState({ patients: null, alerts: null, error: null, loaded: false, refreshFailed: false })
    load()
    return () => {
      latest.current += 1 // drop any answer still on its way
    }
  }, [id, load])

  // Realtime on alerts. No filter on purpose: row-level security decides which
  // events reach this provider (only alerts of assigned patients). Many events in a
  // row cause ONE refetch. The channel is removed when the Overview closes or the
  // provider logs out (id becomes null).
  useEffect(() => {
    if (!supabase || !id) return undefined
    let active = true
    const channel = supabase
      .channel(`provider-overview-${id}-${++overviewChannelCount}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'alerts' }, () => {
        if (!active) return
        clearTimeout(debounce.current)
        debounce.current = setTimeout(() => {
          if (active) load()
        }, OVERVIEW_DEBOUNCE_MS)
      })
      .subscribe((status) => {
        if (!active) return
        if (status === 'SUBSCRIBED') {
          setLive('live')
          load() // catch anything that arrived while the connection was down
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          setLive('paused')
        }
      })
    return () => {
      active = false
      clearTimeout(debounce.current)
      supabase.removeChannel(channel)
    }
  }, [id, load])

  // Refetch on a timer: every 5 minutes while live (flags that depend on time or on
  // readings are not pushed), every 30 seconds while live updates are paused.
  // Nothing runs while the page is hidden; coming back refetches (next effect).
  useEffect(() => {
    if (!id) return undefined
    const ms = live === 'paused' ? OVERVIEW_FALLBACK_MS : OVERVIEW_REFETCH_MS
    const timer = setInterval(() => {
      if (document.visibilityState === 'visible') load()
    }, ms)
    return () => clearInterval(timer)
  }, [id, live, load])

  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === 'visible') load()
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => document.removeEventListener('visibilitychange', onVisible)
  }, [load])

  return { ...state, live, reload: load }
}
