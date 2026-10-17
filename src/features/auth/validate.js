// Small checks shared by the sign-in forms. Each takes the translate function
// and returns calm, translated text (or null when the value is fine), so every
// message is a plain translate call that the i18n check can verify.
// Server-side rules still apply.

export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
export const MIN_PASSWORD = 8

export function emailProblem(t, value) {
  if (!value.trim()) return t('errors:email_required')
  if (!EMAIL_RE.test(value.trim())) return t('errors:email_invalid')
  return null
}

// Today as YYYY-MM-DD in the person's own time zone.
export function todayString(now = new Date()) {
  const m = String(now.getMonth() + 1).padStart(2, '0')
  const d = String(now.getDate()).padStart(2, '0')
  return `${now.getFullYear()}-${m}-${d}`
}

// The database keeps a date of birth only if it is a real date from
// 1900-01-01 to today (otherwise the signup trigger silently drops it), so the
// form must enforce the same rule.
export function dobProblem(t, value, now = new Date()) {
  if (!value) return t('errors:dob_required')
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  if (!match) return t('errors:dob_invalid')
  const [y, m, d] = match.slice(1).map(Number)
  const real = new Date(Date.UTC(y, m - 1, d))
  if (real.getUTCFullYear() !== y || real.getUTCMonth() !== m - 1 || real.getUTCDate() !== d) {
    return t('errors:dob_invalid')
  }
  if (value < '1900-01-01' || value > todayString(now)) return t('errors:dob_invalid')
  return null
}

// Whole years. Call only with a value that passed dobProblem.
export function ageFromDob(value, now = new Date()) {
  const [y, m, d] = value.split('-').map(Number)
  let age = now.getFullYear() - y
  const beforeBirthday = now.getMonth() + 1 < m || (now.getMonth() + 1 === m && now.getDate() < d)
  if (beforeBirthday) age -= 1
  return age
}
