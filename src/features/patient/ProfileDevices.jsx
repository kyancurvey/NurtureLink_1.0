import { AlertTriangleIcon, Card, CheckCircleIcon, InfoIcon } from '../../components/ui/index.js'
import { useTranslation } from 'react-i18next'
import { formatManilaDateTime } from '../../lib/dates.js'
import { LOW_BATTERY_PERCENT, useDevices } from '../../lib/patientData.js'

// Profile > Your devices (step 3.5). READ ONLY. It shows what the database holds
// for the patient's active devices, using the same hook and the same wording as
// the Home tab. There is no pairing here yet (Phase 5) and no "pair" button.
//
// The battery and last-seen values are written by the patient's own app, so they
// are shown as "reported by your app", never as verified. A last-seen time that
// lies in the future cannot be true, so it is shown as unknown.

const FUTURE_SLACK_MS = 5 * 60 * 1000

function Device({ device, language, nowMs }) {
  const { t } = useTranslation()
  const seenMs = device.last_seen_at ? new Date(device.last_seen_at).getTime() : NaN
  const seenKnown = Number.isFinite(seenMs) && seenMs <= nowMs + FUTURE_SLACK_MS
  const percent = Number.isFinite(device.battery_percent) ? device.battery_percent : null
  return (
    <li className="nl-profile__device">
      <p>
        <strong>{device.kind === 'band' ? t('patient:home.device.band') : t('patient:home.device.belt')}</strong>
      </p>
      <p className="nl-profile__status nl-profile__status--success">
        <CheckCircleIcon size={16} />
        <span>{t('patient:profile.device.paired')}</span>
      </p>
      <p>
        {percent === null ? t('patient:home.device.batteryUnknown') : t('patient:home.device.battery', { percent })}
        {percent !== null && percent <= LOW_BATTERY_PERCENT && (
          <span className="nl-profile__status nl-profile__status--warning">
            <AlertTriangleIcon size={16} />
            <span>{t('patient:home.device.batteryLow')}</span>
          </span>
        )}
      </p>
      <p className="nl-profile__muted">
        {device.last_seen_at === null || device.last_seen_at === undefined
          ? t('patient:home.device.neverSeen')
          : seenKnown
            ? t('patient:home.device.lastSeen', { date: formatManilaDateTime(seenMs, language) })
            : t('patient:profile.device.timeUnknown')}
      </p>
    </li>
  )
}

export default function ProfileDevices() {
  const { t, i18n } = useTranslation()
  const devices = useDevices()
  const list = devices.data ?? []
  const nowMs = Date.now()

  let body
  if (!devices.loaded) {
    body = (
      <p className="nl-profile__muted" role="status">
        {t('ui.loading')}
      </p>
    )
  } else if (devices.error) {
    body = <p className="nl-profile__muted">{t('patient:profile.device.loadFailed')}</p>
  } else if (list.length === 0) {
    body = <p>{t('patient:profile.device.none')}</p>
  } else {
    body = (
      <>
        <ul className="nl-profile__list">
          {list.map((d) => (
            <Device key={d.id} device={d} language={i18n.language} nowMs={nowMs} />
          ))}
        </ul>
        <p className="nl-profile__muted">{t('patient:profile.device.reported')}</p>
      </>
    )
  }

  return (
    <Card title={t('patient:profile.device.title')}>
      <div className="nl-profile__form">
        {body}
        <div className="nl-profile__placeholder">
          <p>
            <strong>{t('patient:profile.device.pairingTitle')}</strong>{' '}
            <span className="nl-profile__status nl-profile__status--neutral">
              <InfoIcon size={16} />
              <span>{t('patient:profile.comingSoon')}</span>
            </span>
          </p>
          <p className="nl-profile__muted">{t('patient:profile.device.pairingBody')}</p>
        </div>
      </div>
    </Card>
  )
}
