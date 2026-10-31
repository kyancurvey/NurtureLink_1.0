// Plain-language wording for one alert. No React.
//
// The database stores only NUMBERS in alerts.details (value, min, max, readings;
// migration 002). This file turns them into a calm sentence through i18n, in the
// person's language. Rules:
//  - Only finite numbers from `details` are used. Anything else (a missing key,
//    text, an object, a number that is not finite) is ignored and the short
//    sentence without numbers is shown instead. No text from the database is
//    ever shown, so there is nothing to inject.
//  - Never diagnostic: it says what the app recorded and that it was outside
//    "the app's usual range" (these limits are defaults pending the medical
//    officer), never what it means.
//  - Never promises a response or a time.

const finite = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const whole = (v) => (Number.isInteger(v) && v >= 1 && v <= 99 ? v : null)
// Whole numbers stay whole; other values keep one decimal.
const plain = (v) => String(Math.round(v * 10) / 10)
const oneDecimal = (v) => v.toFixed(1)

// Alert kinds the screen knows. Anything else is shown as a generic alert.
export const KNOWN_TYPES = ['fhr_out_of_range', 'signal_loss', 'low_spo2', 'fever', 'sos']

export function alertTypeLabel(t, type) {
  switch (type) {
    case 'fhr_out_of_range':
      return t('patient:home.fhr.title')
    case 'signal_loss':
      return t('patient:alerts.type.signal_loss')
    case 'low_spo2':
      return t('patient:home.vitals.spo2')
    case 'fever':
      return t('patient:home.vitals.temp')
    case 'sos':
      return t('patient:alerts.type.sos')
    default:
      return t('patient:alerts.type.other')
  }
}

// The sentence for an alert: { alert_type, details }.
export function alertSentence(t, alert) {
  const d = alert && typeof alert.details === 'object' && alert.details !== null ? alert.details : {}
  const value = finite(d.value)
  const min = finite(d.min)
  const max = finite(d.max)
  const readings = whole(d.readings)

  switch (alert?.alert_type) {
    case 'fhr_out_of_range':
      return value !== null && min !== null && max !== null && readings !== null
        ? t('patient:alerts.text.fhr', { readings, min: plain(min), max: plain(max), value: plain(value) })
        : t('patient:alerts.text.fhrShort')
    case 'signal_loss':
      return readings !== null
        ? t('patient:alerts.text.signalLoss', { readings })
        : t('patient:alerts.text.signalLossShort')
    case 'low_spo2':
      return value !== null && min !== null && readings !== null
        ? t('patient:alerts.text.spo2', { readings, min: plain(min), value: plain(value) })
        : t('patient:alerts.text.spo2Short')
    case 'fever':
      return value !== null && max !== null && readings !== null
        ? t('patient:alerts.text.fever', { readings, max: oneDecimal(max), value: oneDecimal(value) })
        : t('patient:alerts.text.feverShort')
    case 'sos':
      return t('patient:alerts.text.sos')
    default:
      return t('patient:alerts.text.other')
  }
}

// open = not yet handled; handled = acknowledged or resolved by a provider.
// An unknown status counts as open (the safer reading).
export const isHandled = (alert) => alert?.status === 'acknowledged' || alert?.status === 'resolved'

// critical -> urgent, warning -> needs attention, anything else -> information.
export const severityKind = (severity) => (severity === 'critical' ? 'danger' : severity === 'warning' ? 'warning' : 'info')
