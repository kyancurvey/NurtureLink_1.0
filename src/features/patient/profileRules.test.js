// Unit tests for profileRules.js. Run with:  node --test src/features/patient/profileRules.test.js
import test from 'node:test'
import assert from 'node:assert/strict'
import { checkCondition, checkHistory, checkName, hasBadChars, trimText } from './profileRules.js'

test('name: trimmed, blank clears, markup kept literally', () => {
  assert.deepEqual(checkName('  Ana  Reyes '), { value: 'Ana  Reyes', error: null })
  assert.deepEqual(checkName('   '), { value: null, error: null })
  assert.deepEqual(checkName(''), { value: null, error: null })
  assert.deepEqual(checkName(null), { value: null, error: null })
  assert.equal(checkName('<b>Ana</b> & "Co" \'x\'').value, '<b>Ana</b> & "Co" \'x\'')
  assert.equal(checkName('&lt;i&gt;').value, '&lt;i&gt;')
})

test('name: 100 characters fine, 101 refused, counted after trimming', () => {
  assert.equal(checkName('a'.repeat(100)).error, null)
  assert.equal(checkName('a'.repeat(101)).error, 'long')
  assert.equal(checkName('a'.repeat(100) + '     ').error, null)
  assert.equal(checkName('  ' + 'a'.repeat(101) + '  ').error, 'long')
})

test('name: control, line-break, zero-width and direction characters are refused', () => {
  for (const code of [9, 10, 13, 127, 133, 0x61c, 0x180e, 0x200b, 0x200d, 0x200e, 0x2028, 0x202e, 0x2060, 0x2066, 0xfeff]) {
    assert.equal(checkName('An' + String.fromCharCode(code) + 'a').error, 'bad', 'U+' + code.toString(16))
  }
  assert.equal(checkName('\nAna').error, 'bad') // refused, not trimmed away
  assert.equal(checkName('\u200b').error, 'bad')
  assert.equal(checkName('Mar\u00eda Jos\u00e9 \u00d1 \u65e5\u672c').error, null)
})

test('history: CRLF to LF, line breaks kept, bad characters refused, 1000 limit', () => {
  assert.equal(checkHistory('a\r\nb').value, 'a\nb')
  assert.equal(checkHistory('line1\nline2').error, null)
  assert.equal(checkHistory('a\rb').error, 'bad')
  assert.equal(checkHistory('a\tb').error, 'bad')
  assert.equal(checkHistory('a\u200bb').error, 'bad')
  assert.equal(checkHistory('h'.repeat(1000)).error, null)
  assert.equal(checkHistory('h'.repeat(1001)).error, 'long')
  assert.equal(checkHistory('   ' + 'h'.repeat(1000) + ' \n ').error, null)
  assert.deepEqual(checkHistory('  \n '), { value: null, error: null })
  assert.equal(checkHistory('<i>x</i> &amp; "q"').value, '<i>x</i> &amp; "q"')
})

test('condition: trimmed, 60 limit, duplicates ignoring case, at most 10', () => {
  assert.deepEqual(checkCondition('  Asthma ', []), { value: 'Asthma', error: null })
  assert.equal(checkCondition('   ', []).error, 'empty')
  assert.equal(checkCondition('k'.repeat(60), []).error, null)
  assert.equal(checkCondition('k'.repeat(61), []).error, 'long')
  assert.equal(checkCondition('asthma', ['Asthma']).error, 'duplicate')
  assert.equal(checkCondition('a\tb', []).error, 'bad')
  assert.equal(checkCondition('a\nb', []).error, 'bad')
  const ten = Array.from({ length: 10 }, (_, i) => 'c' + i)
  assert.equal(checkCondition('new', ten).error, 'full')
  assert.equal(checkCondition('<b>x</b>', []).value, '<b>x</b>')
})

test('hasBadChars and trimText basics', () => {
  assert.equal(hasBadChars('plain'), false)
  assert.equal(hasBadChars('a\nb'), true)
  assert.equal(hasBadChars('a\nb', true), false)
  assert.equal(trimText('\u00a0 a b \u3000'), 'a b')
})
