import { MANILA_OFFSET_MS } from '../../lib/dates.js'
import { POOR_SIGNAL_QUALITY } from '../../lib/patientData.js'

// Helpers for the Monitor charts. Plain functions, no Recharts, no React, so
// they are cheap to load and easy to test.

const HOUR = 60 * 60 * 1000
const DAY = 24 * HOUR

// Is this value below the lowest or above the highest normal value?
// band = { min?, max? } from my_normal_ranges(); no band means nothing is "outside".
export function isOutside(value, band) {
  if (value === null || value === undefined || !band) return false
  return (band.min != null && value < band.min) || (band.max != null && value > band.max)
}

// Turns rows (oldest first) into chart points for ONE measure.
//   field   the column to plot (for example 'fetal_hr_bpm')
//   band    { min?, max? } or undefined
//   gapMs   a longer pause than this between two points breaks the line
//
// A point with v = null is how the chart shows "nothing here": the line stops
// and starts again, it is never drawn across. That is used for
//   - a belt check where the signal was lost (no trustworthy value), and
//   - a pause longer than gapMs between two checks.
// A vitals row that simply does not hold this measure is skipped: it is not a
// check of this measure, so it is neither a point nor a gap.
export function buildSeries(rows, field, band, gapMs) {
  const points = []
  let lost = 0
  let outCount = 0
  let valueCount = 0
  let prevT = null
  for (const r of rows) {
    const isLost = r.signal_lost === true
    const raw = r[field]
    if (!isLost && (raw === null || raw === undefined)) continue
    const t = new Date(r.measured_at).getTime()
    if (Number.isNaN(t)) continue
    if (prevT !== null && t - prevT > gapMs) points.push({ t: prevT + (t - prevT) / 2, v: null })
    if (isLost) {
      lost += 1
      points.push({ t, v: null, lost: true })
    } else {
      const v = Number(raw)
      const out = isOutside(v, band)
      if (out) outCount += 1
      valueCount += 1
      points.push({ t, v, out, source: r.source })
    }
    prevT = t
  }
  return { points, lost, outCount, valueCount }
}

// Axis tick positions that fall on Philippine clock times (Asia/Manila is
// always UTC+8): every 6 hours for a day, every midnight for a week, every
// 5th midnight for a month.
export function makeTicks(since, until, range) {
  const ticks = []
  if (range === 'day') {
    const step = 6 * HOUR
    for (let t = Math.ceil((since + MANILA_OFFSET_MS) / step) * step - MANILA_OFFSET_MS; t <= until; t += step) ticks.push(t)
  } else {
    const step = range === 'week' ? DAY : 5 * DAY
    for (let t = Math.ceil((since + MANILA_OFFSET_MS) / DAY) * DAY - MANILA_OFFSET_MS; t <= until; t += step) ticks.push(t)
  }
  return ticks
}

// The vertical axis range, and the shaded band as { y1, y2 } (or null).
// The axis always includes the whole band and every value, so nothing is cut off.
// kind: 'fhr' | 'hr' | 'spo2' | 'temp'.
export function chartDomain(points, band, kind) {
  const values = points.filter((p) => p.v !== null).map((p) => p.v)
  let lo = Math.min(...values)
  let hi = Math.max(...values)
  if (band?.min != null) lo = Math.min(lo, band.min)
  if (band?.max != null) hi = Math.max(hi, band.max)

  let domain
  if (kind === 'spo2') {
    domain = [Math.floor((lo - 2) / 5) * 5, 100]
  } else if (kind === 'temp') {
    domain = [Math.floor((lo - 0.3) * 2) / 2, Math.ceil((hi + 0.3) * 2) / 2]
  } else {
    domain = [Math.floor((lo - 5) / 10) * 10, Math.ceil((hi + 5) / 10) * 10]
  }

  let area = null
  if (band && (band.min != null || band.max != null)) {
    area = { y1: band.min != null ? band.min : domain[0], y2: band.max != null ? band.max : domain[1] }
  }

  // Even steps on the vertical axis (heart rates every 10 or 20, SpO2 every 5,
  // temperature every 0.5), always including both ends.
  const span = domain[1] - domain[0]
  const step = kind === 'spo2' ? 5 : kind === 'temp' ? 0.5 : span > 60 ? 20 : 10
  const yTicks = []
  for (let v = domain[0]; v <= domain[1] + 1e-9; v += step) yTicks.push(Math.round(v * 10) / 10)
  return { domain, area, yTicks }
}

// Should the "Adjust belt" guidance show? Looks at the newest 3 belt checks
// (rows newest first): show it when the newest one lost the signal or had a
// poor signal quality, or when at least 2 of the 3 did. Typed (manual) entries
// have no signal quality and never count as poor.
export function needsBeltHelp(rows) {
  const latest = (rows ?? []).slice(0, 3)
  if (latest.length === 0) return false
  const poor = (r) => r.signal_lost === true || (r.signal_quality != null && r.signal_quality < POOR_SIGNAL_QUALITY)
  return poor(latest[0]) || latest.filter(poor).length >= 2
}
