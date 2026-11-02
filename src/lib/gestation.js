import { MANILA_OFFSET_MS } from './dates.js'

// Gestational age and trimester from the due date. Pure functions: no React, no
// network, nothing stored. The numbers below are DRAFT, pending medical officer.
//
// Rule (completed weeks and days, a 40-week pregnancy of 280 days):
//   gaDays = 280 - (dueDate - today)        both are Philippine calendar dates
//   weeks  = floor(gaDays / 7), days = gaDays mod 7
//   trimester 1 = 0w0d to 13w6d, 2 = 14w0d to 27w6d, 3 = 28w0d onward
//
// States returned:
//   unset         no due date (or an unreadable one): nothing is worked out
//   before_start  the due date is more than 280 days away (gaDays below 0)
//   ok            gaDays 0 to 280
//   past_due      gaDays 281 to 294 (after the due date, up to 42w0d)
//   over_42       gaDays above 294: no weeks or trimester are shown
//
// Dates are compared as whole calendar days, so there is no time zone or
// daylight-saving problem (Asia/Manila has none anyway). The Manila calendar
// date comes from manilaToday(), never from the phone's own zone.

export const PREGNANCY_DAYS = 280
export const SECOND_TRIMESTER_DAY = 14 * 7 // 14w0d
export const THIRD_TRIMESTER_DAY = 28 * 7 // 28w0d
export const OVER_DAY = 42 * 7 // 42w0d = 294 days

// Allowed due-date window when SAVING. These repeat the numbers in migration 013
// (save_pregnancy_details); the database decides, the form only warns first.
// Change both together. Draft, pending medical officer.
export const DUE_DATE_PAST_DAYS = 14 // up to 14 days ago = 42w0d
export const DUE_DATE_AHEAD_DAYS = 280 // up to 280 days ahead = 0w0d

const DAY_MS = 24 * 60 * 60 * 1000

// The Philippine calendar date (YYYY-MM-DD) of a moment.
export function manilaToday(nowMs = Date.now()) {
  return new Date(nowMs + MANILA_OFFSET_MS).toISOString().slice(0, 10)
}

// Whole days since 1970-01-01 for a real calendar date "YYYY-MM-DD", else null.
function dayNumber(iso) {
  if (typeof iso !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return null
  const ms = Date.parse(`${iso}T00:00:00Z`)
  if (Number.isNaN(ms)) return null
  // Reject dates JavaScript would roll over (31 February).
  if (new Date(ms).toISOString().slice(0, 10) !== iso) return null
  return Math.round(ms / DAY_MS)
}

export function gestationalAge(dueDateIso, todayIso) {
  const due = dayNumber(dueDateIso)
  const today = dayNumber(todayIso)
  if (due === null || today === null) return { state: 'unset', totalDays: null, weeks: null, days: null, trimester: null }

  const totalDays = PREGNANCY_DAYS - (due - today)
  if (totalDays < 0) return { state: 'before_start', totalDays, weeks: null, days: null, trimester: null }
  if (totalDays > OVER_DAY) return { state: 'over_42', totalDays, weeks: null, days: null, trimester: null }

  const trimester = totalDays < SECOND_TRIMESTER_DAY ? 1 : totalDays < THIRD_TRIMESTER_DAY ? 2 : 3
  return {
    state: totalDays > PREGNANCY_DAYS ? 'past_due' : 'ok',
    totalDays,
    weeks: Math.floor(totalDays / 7),
    days: totalDays % 7,
    trimester,
  }
}

// Is this due date one the database will accept? null = yes, else why not:
//   'invalid' not a real date, 'past' more than 14 days ago, 'ahead' more than 280 days ahead.
export function dueDateProblem(dueDateIso, todayIso) {
  const due = dayNumber(dueDateIso)
  const today = dayNumber(todayIso)
  if (due === null || today === null) return 'invalid'
  if (due < today - DUE_DATE_PAST_DAYS) return 'past'
  if (due > today + DUE_DATE_AHEAD_DAYS) return 'ahead'
  return null
}
