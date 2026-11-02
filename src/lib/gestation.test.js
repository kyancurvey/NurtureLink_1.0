// Unit tests for gestation.js. Run with:  node --test src/lib/gestation.test.js
// (Node's built-in test runner; no dependency, not part of the app bundle.)
import test from 'node:test'
import assert from 'node:assert/strict'
import { gestationalAge, dueDateProblem, manilaToday } from './gestation.js'

const TODAY = '2026-11-01'
// Due date that gives exactly this many gestational days today.
const dueFor = (gaDays) => {
  const ms = Date.parse(`${TODAY}T00:00:00Z`) + (280 - gaDays) * 86400000
  return new Date(ms).toISOString().slice(0, 10)
}

test('boundary cases: state, weeks, days, trimester', () => {
  const cases = [
    [-1, 'before_start', null, null, null],
    [0, 'ok', 0, 0, 1],
    [6, 'ok', 0, 6, 1],
    [7, 'ok', 1, 0, 1],
    [97, 'ok', 13, 6, 1],
    [98, 'ok', 14, 0, 2],
    [195, 'ok', 27, 6, 2],
    [196, 'ok', 28, 0, 3],
    [280, 'ok', 40, 0, 3],
    [281, 'past_due', 40, 1, 3],
    [294, 'past_due', 42, 0, 3],
    [295, 'over_42', null, null, null],
  ]
  for (const [ga, state, weeks, days, trimester] of cases) {
    const r = gestationalAge(dueFor(ga), TODAY)
    assert.equal(r.state, state, `ga ${ga} state`)
    assert.equal(r.weeks, weeks, `ga ${ga} weeks`)
    assert.equal(r.days, days, `ga ${ga} days`)
    assert.equal(r.trimester, trimester, `ga ${ga} trimester`)
    assert.equal(r.totalDays, ga)
  }
})

test('seed ages give the 2 / 5 / 3 trimester split', () => {
  const weeks = [12, 13, 16, 20, 24, 26, 20, 29, 36, 38]
  const counts = { 1: 0, 2: 0, 3: 0 }
  for (const w of weeks) counts[gestationalAge(dueFor(w * 7), TODAY).trimester] += 1
  assert.deepEqual(counts, { 1: 2, 2: 5, 3: 3 })
})

test('no, empty or unreadable due date is "unset"', () => {
  for (const v of [null, undefined, '', 'abc', '2026-13-01', '2026-02-31', '01/11/2026', 20261101]) {
    assert.equal(gestationalAge(v, TODAY).state, 'unset', String(v))
  }
  assert.equal(gestationalAge(dueFor(100), 'nope').state, 'unset')
})

test('the answer changes when the due date changes', () => {
  const a = gestationalAge(dueFor(100), TODAY)
  const b = gestationalAge(dueFor(101), TODAY)
  assert.equal(a.weeks, 14)
  assert.equal(a.days, 2)
  assert.equal(b.days, 3)
})

test('due-date window for saving: 14 days ago to 280 days ahead', () => {
  const at = (offset) => new Date(Date.parse(`${TODAY}T00:00:00Z`) + offset * 86400000).toISOString().slice(0, 10)
  assert.equal(dueDateProblem(at(-14), TODAY), null)
  assert.equal(dueDateProblem(at(-15), TODAY), 'past')
  assert.equal(dueDateProblem(at(280), TODAY), null)
  assert.equal(dueDateProblem(at(281), TODAY), 'ahead')
  assert.equal(dueDateProblem(TODAY, TODAY), null)
  assert.equal(dueDateProblem('2026-02-31', TODAY), 'invalid')
  assert.equal(dueDateProblem('', TODAY), 'invalid')
})

test('the window edges match the gestation edges (0w0d and 42w0d)', () => {
  const at = (offset) => new Date(Date.parse(`${TODAY}T00:00:00Z`) + offset * 86400000).toISOString().slice(0, 10)
  assert.equal(gestationalAge(at(280), TODAY).totalDays, 0)
  assert.equal(gestationalAge(at(-14), TODAY).totalDays, 294)
})

test('Manila date does not follow the phone time zone', () => {
  // 2026-11-01 17:00 UTC is already 2026-11-02 01:00 in Manila.
  assert.equal(manilaToday(Date.parse('2026-11-01T17:00:00Z')), '2026-11-02')
  assert.equal(manilaToday(Date.parse('2026-11-01T15:59:00Z')), '2026-11-01')
  assert.equal(manilaToday(Date.parse('2026-11-01T16:00:00Z')), '2026-11-02')
})
