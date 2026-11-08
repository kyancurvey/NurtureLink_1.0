import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatManilaNow, TIME_ZONE } from '../src/lib/time.js';

test('the time zone is Asia/Manila', () => {
  assert.equal(TIME_ZONE, 'Asia/Manila');
});

test('07:05 UTC is 3:05 PM in Manila, 12-hour', () => {
  const { time } = formatManilaNow(new Date('2026-11-08T07:05:00Z'), 'en');
  assert.match(time, /^3:05\s?PM$/i);
});

test('midnight in Manila is 12:00 AM and already the next day', () => {
  const { date, time } = formatManilaNow(new Date('2026-11-08T16:00:00Z'), 'en');
  assert.match(time, /^12:00\s?AM$/i);
  assert.match(date, /Nov 9/);
});

test('Filipino uses Filipino day and month names', () => {
  const en = formatManilaNow(new Date('2026-11-08T07:05:00Z'), 'en').date;
  const fil = formatManilaNow(new Date('2026-11-08T07:05:00Z'), 'fil').date;
  assert.notEqual(fil, en);
});

test('an unknown language falls back to English', () => {
  const date = new Date('2026-11-08T07:05:00Z');
  assert.deepEqual(formatManilaNow(date, 'xx'), formatManilaNow(date, 'en'));
});
