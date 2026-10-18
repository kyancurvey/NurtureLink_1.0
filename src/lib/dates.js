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
