import { supabase } from './supabase.js'

// Audit helper: writes one row to audit_log (who did what, and about which
// patient). Only PROVIDERS can write (policy audit_log_insert_provider, 005):
// the actor must be the signed-in provider, and the patient (if given) must be
// one assigned to that provider. Nobody can read the log from the app; the
// project owner reads it in the SQL Editor.
//
//   writeAudit(AUDIT.PROVIDER_LOGIN)                          // no patient
//   writeAudit(AUDIT.PATIENT_RECORD_OPENED, { patientId })    // Phase 4: call this
//                                                             // when a patient's detail opens
//
// It never throws and never returns the saved row (there is no SELECT grant on
// audit_log, so asking for the row back would fail). It returns
// { ok: true } or { ok: false, error }. Callers decide what a failure means:
// the login entry ignores it; in Phase 4 the patient detail screen should not
// open if the entry could not be written.
//
// Keep `details` free of names, emails and readings: ids, counts and short
// labels only.

export const AUDIT = {
  PROVIDER_LOGIN: 'provider_login',
  PATIENT_RECORD_OPENED: 'patient_record_opened',
}

export async function writeAudit(action, { patientId = null, details = {} } = {}) {
  try {
    if (!supabase) return { ok: false, error: { message: 'not_configured' } }
    if (typeof action !== 'string' || action.length < 1 || action.length > 64) {
      return { ok: false, error: { message: 'invalid_action' } }
    }
    // getSession() reads the stored session on this device (no network call).
    const { data } = await supabase.auth.getSession()
    const actorId = data?.session?.user?.id
    if (!actorId) return { ok: false, error: { message: 'not_signed_in' } }

    const { error } = await supabase
      .from('audit_log')
      .insert({ actor_id: actorId, patient_id: patientId, action, details })
    return error ? { ok: false, error } : { ok: true }
  } catch (error) {
    return { ok: false, error }
  }
}
