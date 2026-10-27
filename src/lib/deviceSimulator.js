import { supabase } from './supabase.js'

// Simulator stub for "Check now" (step 3.1). The real belt and wrist band come
// in Phase 5 (first a proper simulator, then Web Bluetooth); until then this
// saves ONE synthetic check, clearly marked source = 'simulator':
//   - one belt reading (fetal heart rate, signal quality, confidence)
//   - one vitals row (maternal heart rate, SpO2, temperature)
// The values are made up and kept unremarkable. They are NOT the alert limits
// (those live in the alert_thresholds table); they only have to look plausible.
//
// measured_at is left out on purpose: the database then uses its own clock.
// Only a reading that was stored offline and sent later should carry a device
// time (Phase 5/8), and the database refuses one that is in the future
// (migration 008, error text reading_time_in_future).
//
// TEST_CLOCK_SKEW_MINUTES exists only so the "wrong phone clock" message can be
// seen once in the real app. Keep it at 0. To test: set it to 30, upload,
// press Check now, expect the friendly message, then set it back to 0.
const TEST_CLOCK_SKEW_MINUTES = 0

const between = (min, max) => min + Math.floor(Math.random() * (max - min + 1))

function newClientId() {
  // A fresh id per check lets a resend never create a duplicate (unique per patient).
  return typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : undefined
}

// beltId / bandId: the patient's own device ids if they have them, else null.
// Returns { error } (null on success). The belt row is saved first; if it fails
// nothing else is written.
export async function runSimulatedCheck({ patientId, beltId = null, bandId = null }) {
  if (!supabase) return { error: { message: 'not_configured' } }

  const when =
    TEST_CLOCK_SKEW_MINUTES > 0
      ? { measured_at: new Date(Date.now() + TEST_CLOCK_SKEW_MINUTES * 60000).toISOString() }
      : {}

  const belt = await supabase.from('belt_readings').insert({
    patient_id: patientId,
    device_id: beltId,
    fetal_hr_bpm: between(132, 148),
    signal_quality: between(75, 95),
    confidence: between(80, 97),
    signal_lost: false,
    source: 'simulator',
    client_id: newClientId(),
    ...when,
  })
  if (belt.error) return { error: belt.error }

  const vitals = await supabase.from('maternal_vitals').insert({
    patient_id: patientId,
    device_id: bandId,
    heart_rate_bpm: between(70, 90),
    spo2_percent: between(97, 99),
    temperature_c: (between(365, 371) / 10).toFixed(1),
    source: 'simulator',
    client_id: newClientId(),
    ...when,
  })
  return { error: vitals.error ?? null }
}
