// Date and time for people, in their language and time zone. Filipino uses the
// Philippine locale. Falls back to the raw text if the value is not a date.
export function formatDateTime(value, language) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return String(value ?? '')
  try {
    return new Intl.DateTimeFormat(language === 'fil' ? 'fil-PH' : 'en-PH', {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(date)
  } catch {
    return date.toLocaleString()
  }
}

// Philippine time. Times are stored in UTC; the Monitor tab always shows them
// in Asia/Manila, whatever time zone the phone is set to.
export const MANILA_TZ = 'Asia/Manila'
// Asia/Manila has no daylight saving time: it is always UTC+8.
export const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000

const locale = (language) => (language === 'fil' ? 'fil-PH' : 'en-PH')

export function formatManilaDateTime(value, language) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return String(value ?? '')
  try {
    return new Intl.DateTimeFormat(locale(language), {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone: MANILA_TZ,
    }).format(date)
  } catch {
    return date.toLocaleString()
  }
}

// A short label for a chart axis. range 'day' shows the hour, 'week' and
// 'month' show the date.
export function formatManilaTick(ms, language, range) {
  const options =
    range === 'day'
      ? { hour: 'numeric', minute: '2-digit', timeZone: MANILA_TZ }
      : { month: 'short', day: 'numeric', timeZone: MANILA_TZ }
  try {
    return new Intl.DateTimeFormat(locale(language), options).format(new Date(ms))
  } catch {
    return String(ms)
  }
}
