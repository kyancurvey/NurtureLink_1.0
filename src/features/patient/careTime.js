import { MANILA_OFFSET_MS } from '../../lib/dates.js'

// Small pure helpers for the Care tab (step 3.4). No React, no network, so they
// can be tested on their own.

// UI HINTS ONLY, NOT RULES. These repeat the numbers in migration 012
// (request_appointment and request_reschedule), which is what really decides.
// They only set the date picker's min/max and the hint text under the form.
// If a limit changes in 012, change it here too. Pending review.
export const APPT_MIN_LEAD_MINUTES = 60
export const APPT_MAX_AHEAD_DAYS = 90
// The length of a visit comes from the database column default (30 minutes).
// This number is only used in the explanatory text under the form.
export const APPT_DEFAULT_MINUTES = 30

const DAY_MS = 24 * 60 * 60 * 1000

// Philippine calendar date (YYYY-MM-DD) of a moment, whatever the phone's time zone.
export function manilaDate(ms) {
  return new Date(ms + MANILA_OFFSET_MS).toISOString().slice(0, 10)
}

// Philippine clock time (HH:MM) of a moment.
export function manilaTime(ms) {
  return new Date(ms + MANILA_OFFSET_MS).toISOString().slice(11, 16)
}

// The first and last date the picker offers (a convenience, the database decides).
export function manilaDateRange(nowMs) {
  return { min: manilaDate(nowMs), max: manilaDate(nowMs + APPT_MAX_AHEAD_DAYS * DAY_MS) }
}

// A date and a time typed in Philippine time ("2026-11-05", "10:30") become the
// UTC moment stored in the database (ISO text). null if either is missing or not
// a real date and time. Asia/Manila is always UTC+8 (no daylight saving).
export function manilaToUtcIso(date, time) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date ?? '') || !/^\d{2}:\d{2}$/.test(time ?? '')) return null
  const ms = Date.parse(`${date}T${time}:00+08:00`)
  if (Number.isNaN(ms)) return null
  // Reject dates that JavaScript would silently roll over (for example 31 February).
  if (manilaDate(ms) !== date || manilaTime(ms) !== time) return null
  return new Date(ms).toISOString()
}

// Which row goes where. "Upcoming" = requested or confirmed and not yet started
// (this device's clock, display only). Everything else is "Past". Upcoming is
// soonest first, past is newest first.
export function splitAppointments(rows, nowMs) {
  const upcoming = []
  const past = []
  for (const a of rows ?? []) {
    const ahead = new Date(a.starts_at).getTime() >= nowMs
    if (ahead && (a.status === 'requested' || a.status === 'scheduled')) upcoming.push(a)
    else past.push(a)
  }
  const time = (a) => new Date(a.starts_at).getTime()
  upcoming.sort((x, y) => time(x) - time(y))
  past.sort((x, y) => time(y) - time(x))
  return { upcoming, past }
}

// The status word to show. The database status 'scheduled' is shown as
// "Confirmed". A request whose time has passed without being confirmed is shown
// as "Not confirmed" (device clock, display only; the stored status is unchanged).
export function statusKind(appointment, nowMs) {
  switch (appointment.status) {
    case 'scheduled':
      return 'scheduled'
    case 'completed':
      return 'completed'
    case 'cancelled':
      return 'cancelled'
    default:
      return new Date(appointment.starts_at).getTime() >= nowMs ? 'requested' : 'notConfirmed'
  }
}
