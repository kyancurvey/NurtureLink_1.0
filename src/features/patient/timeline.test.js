// Unit tests for timeline.js. Run with:  node --test src/features/patient/timeline.test.js
import test from 'node:test'
import assert from 'node:assert/strict'
import { buildTimeline } from './timeline.js'

const at = (iso) => new Date(iso).getTime()

test('merges the three sources newest first', () => {
  const { items, limited } = buildTimeline({
    readings: [{ id: 'r1', measured_at: '2026-11-01T02:00:00Z' }],
    alerts: [{ id: 'a1', created_at: '2026-11-01T03:00:00Z' }],
    appointments: [{ id: 'p1', starts_at: '2026-11-01T01:00:00Z' }],
    cut: {},
  })
  assert.deepEqual(items.map((i) => i.key), ['alert:a1', 'reading:r1', 'appointment:p1'])
  assert.equal(limited, false)
})

test('a cut source hides older items of the other sources (no silent gap)', () => {
  // readings were cut: the oldest loaded reading is 10:00, so a 09:00 alert might hide older readings.
  const { items, limited } = buildTimeline({
    readings: [
      { id: 'r2', measured_at: '2026-11-01T12:00:00Z' },
      { id: 'r1', measured_at: '2026-11-01T10:00:00Z' },
    ],
    alerts: [
      { id: 'a2', created_at: '2026-11-01T11:00:00Z' },
      { id: 'a1', created_at: '2026-11-01T09:00:00Z' },
    ],
    appointments: [],
    cut: { readings: true },
  })
  assert.deepEqual(items.map((i) => i.key), ['reading:r2', 'alert:a2', 'reading:r1'])
  assert.equal(limited, true)
})

test('the horizon is the newest of the oldest-loaded times of the cut sources', () => {
  const { items } = buildTimeline({
    readings: [{ id: 'r1', measured_at: '2026-11-01T10:00:00Z' }],
    alerts: [{ id: 'a1', created_at: '2026-11-01T11:00:00Z' }],
    appointments: [{ id: 'p1', starts_at: '2026-11-01T10:30:00Z' }],
    cut: { readings: true, alerts: true },
  })
  assert.deepEqual(items.map((i) => i.key), ['alert:a1'])
})

test('nulls, bad dates and empty input are safe', () => {
  const out = buildTimeline({ readings: null, alerts: [{ id: 'x', created_at: 'not a date' }], appointments: undefined, cut: undefined })
  assert.deepEqual(out, { items: [], limited: false })
  assert.equal(at('2026-11-01T00:00:00Z') > 0, true)
})

test('equal times keep a stable order', () => {
  const a = buildTimeline({ readings: [{ id: 'r', measured_at: '2026-11-01T00:00:00Z' }], alerts: [{ id: 'a', created_at: '2026-11-01T00:00:00Z' }], appointments: [], cut: {} })
  const b = buildTimeline({ readings: [{ id: 'r', measured_at: '2026-11-01T00:00:00Z' }], alerts: [{ id: 'a', created_at: '2026-11-01T00:00:00Z' }], appointments: [], cut: {} })
  assert.deepEqual(a.items.map((i) => i.key), b.items.map((i) => i.key))
})
