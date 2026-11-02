// Input rules for the Profile tab (step 3.5). Pure functions: no React, no network.
//
// These REPEAT the checks in migration 013 (set_my_display_name and
// save_pregnancy_details), which is what really decides. The form uses them only
// to refuse and explain calmly BEFORE sending, and to send already-clean text.
// If a limit changes in 013, change it here too.
//
// ALL LIMITS ARE DRAFT, PENDING MEDICAL OFFICER.

export const NAME_MAX = 100 // characters, after trimming
export const HISTORY_MAX = 1000 // characters, after trimming
export const CONDITIONS_MAX = 10 // entries
export const CONDITION_MAX = 60 // characters per entry

// Characters that are refused: control characters, zero-width and text-direction
// characters. The history may keep line breaks (LF); a name and a condition may not.
const BAD_ANY = /[\u0001-\u001f\u007f-\u009f\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]/
const BAD_BUT_LF = /[\u0001-\u0009\u000b-\u001f\u007f-\u009f\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]/

export const hasBadChars = (text, allowLineBreak = false) =>
  (allowLineBreak ? BAD_BUT_LF : BAD_ANY).test(String(text ?? ''))

// White space (including no-break and ideographic spaces) trimmed from both ends.
export const trimText = (text) => String(text ?? '').replace(/^[\s\u00a0\u3000]+|[\s\u00a0\u3000]+$/g, '')

// Display name. A blank name is allowed and means "remove it" (value null).
// error: null | 'bad' | 'long'
export function checkName(raw) {
  const text = String(raw ?? '')
  if (hasBadChars(text)) return { value: null, error: 'bad' }
  const value = trimText(text)
  if (value === '') return { value: null, error: null }
  if (Array.from(value).length > NAME_MAX) return { value: null, error: 'long' }
  return { value, error: null }
}

// Obstetric history. CRLF becomes LF; blank becomes null. error: null | 'bad' | 'long'
export function checkHistory(raw) {
  const text = String(raw ?? '').replace(/\r\n/g, '\n')
  if (hasBadChars(text, true)) return { value: null, error: 'bad' }
  const value = trimText(text)
  if (value === '') return { value: null, error: null }
  if (Array.from(value).length > HISTORY_MAX) return { value: null, error: 'long' }
  return { value, error: null }
}

// One condition typed by the person, checked against the list so far.
// error: null | 'empty' | 'bad' | 'long' | 'duplicate' | 'full'
export function checkCondition(raw, existing = []) {
  const text = String(raw ?? '')
  if (hasBadChars(text)) return { value: null, error: 'bad' }
  const value = trimText(text)
  if (value === '') return { value: null, error: 'empty' }
  if (Array.from(value).length > CONDITION_MAX) return { value: null, error: 'long' }
  const lower = value.toLowerCase()
  if (existing.some((c) => c.toLowerCase() === lower)) return { value: null, error: 'duplicate' }
  if (existing.length >= CONDITIONS_MAX) return { value: null, error: 'full' }
  return { value, error: null }
}
