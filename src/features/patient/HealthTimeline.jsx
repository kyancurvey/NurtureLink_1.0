import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import {
  AlertOctagonIcon,
  AlertTriangleIcon,
  BellIcon,
  Button,
  Card,
  CheckCircleIcon,
  CheckIcon,
  CloseIcon,
  InfoIcon,
} from '../../components/ui/index.js'
import { formatManilaDateTime } from '../../lib/dates.js'
import {
  ALERTS_LIMIT,
  APPOINTMENTS_LIMIT,
  TIMELINE_PAGE,
  confidenceLevel,
  useAlerts,
  useAppointments,
  useBeltHistory,
} from '../../lib/patientData.js'
import { alertSentence, alertTypeLabel, isHandled, severityKind } from './alertText.js'
import { statusKind } from './careTime.js'
import { buildTimeline } from './timeline.js'

// Profile > Health record timeline (step 3.5). Baby heart-rate checks, alerts and
// appointments in one list, newest first, times in Philippine time. It reuses
// the existing hooks (belt history from 3.2, alerts from 3.3, appointments from
// 3.4). Only a SMALL set of readings is fetched, never the 1000 the charts use.
// All text comes from i18n or from our own helpers; nothing from the database is
// shown except numbers and times. Wording is never diagnostic and promises nothing.

// Status of an appointment: icon + words (same words as the Care tab).
const APPT_ICON = {
  requested: InfoIcon,
  scheduled: CheckCircleIcon,
  completed: CheckIcon,
  cancelled: CloseIcon,
  notConfirmed: InfoIcon,
}
const APPT_TONE = {
  requested: 'neutral',
  scheduled: 'success',
  completed: 'success',
  cancelled: 'neutral',
  notConfirmed: 'neutral',
}

function Status({ tone, Icon, children }) {
  return (
    <span className={`nl-profile__status nl-profile__status--${tone}`}>
      <Icon size={16} />
      <span>{children}</span>
    </span>
  )
}

function apptWord(t, kind) {
  switch (kind) {
    case 'scheduled':
      return t('patient:care.appt.status.scheduled')
    case 'completed':
      return t('patient:care.appt.status.completed')
    case 'cancelled':
      return t('patient:care.appt.status.cancelled')
    case 'notConfirmed':
      return t('patient:care.appt.status.notConfirmed')
    default:
      return t('patient:care.appt.status.requested')
  }
}

function Reading({ row }) {
  const { t } = useTranslation()
  const lost = row.signal_lost === true
  const level = confidenceLevel(row.signal_quality)
  return (
    <>
      <div className="nl-profile__tl-head">
        <h3 className="nl-profile__tl-title">{t('patient:profile.timeline.reading')}</h3>
        {lost ? (
          <Status tone="warning" Icon={AlertTriangleIcon}>
            {t('patient:monitor.history.signalLost')}
          </Status>
        ) : (
          <Status tone="neutral" Icon={CheckIcon}>
            {t('patient:profile.timeline.recorded')}
          </Status>
        )}
      </div>
      {!lost && (
        <p>
          <strong>
            {row.fetal_hr_bpm} {t('patient:home.unit.bpm')}
          </strong>
          {level && (
            <span className="nl-profile__muted">
              {' · '}
              {t('patient:monitor.history.qualityValue', {
                level: t(`patient:home.confidence.${level}`),
                percent: row.signal_quality,
              })}
            </span>
          )}
        </p>
      )}
      <p className="nl-profile__muted">
        {t('patient:monitor.history.source')}: {t(`patient:monitor.source.${row.source}`)}
      </p>
    </>
  )
}

function AlertRow({ row }) {
  const { t } = useTranslation()
  const kind = severityKind(row.severity)
  const handled = isHandled(row)
  return (
    <>
      <div className="nl-profile__tl-head">
        <h3 className="nl-profile__tl-title">{alertTypeLabel(t, row.alert_type)}</h3>
        {kind === 'danger' && (
          <Status tone="danger" Icon={AlertOctagonIcon}>
            {t('status.danger')}
          </Status>
        )}
        {kind === 'warning' && (
          <Status tone="warning" Icon={AlertTriangleIcon}>
            {t('status.warning')}
          </Status>
        )}
        {kind === 'info' && (
          <Status tone="neutral" Icon={InfoIcon}>
            {t('patient:alerts.severity.info')}
          </Status>
        )}
        {handled ? (
          <Status tone="success" Icon={CheckCircleIcon}>
            {t('patient:alerts.status.handled')}
          </Status>
        ) : (
          <Status tone="neutral" Icon={BellIcon}>
            {t('patient:alerts.status.open')}
          </Status>
        )}
      </div>
      <p>{alertSentence(t, row)}</p>
    </>
  )
}

function AppointmentRow({ row, nowMs }) {
  const { t } = useTranslation()
  const kind = statusKind(row, nowMs)
  const Icon = APPT_ICON[kind] ?? InfoIcon
  return (
    <div className="nl-profile__tl-head">
      <h3 className="nl-profile__tl-title">{t('patient:profile.timeline.appointment')}</h3>
      <Status tone={APPT_TONE[kind] ?? 'neutral'} Icon={Icon}>
        {apptWord(t, kind)}
      </Status>
    </div>
  )
}

export default function HealthTimeline() {
  const { t, i18n } = useTranslation()
  const [limit, setLimit] = useState(TIMELINE_PAGE)
  const readings = useBeltHistory(limit)
  const alerts = useAlerts()
  const appts = useAppointments()

  const readingRows = (readings.data ?? []).slice(0, limit)
  const built = buildTimeline({
    readings: readingRows,
    alerts: alerts.data,
    appointments: appts.data,
    cut: {
      readings: (readings.data ?? []).length > limit,
      alerts: (alerts.data ?? []).length >= ALERTS_LIMIT,
      appointments: (appts.data ?? []).length >= APPOINTMENTS_LIMIT,
    },
  })
  const shown = built.items.slice(0, limit)
  const canShowMore = built.items.length > limit || (readings.data ?? []).length > limit

  const everyLoaded = readings.loaded && alerts.loaded && appts.loaded
  const failedCount = [readings, alerts, appts].filter((q) => q.error).length
  const allFailed = failedCount === 3
  const nowMs = Date.now()

  let body
  if (!everyLoaded) {
    body = (
      <p className="nl-profile__muted" role="status">
        {t('ui.loading')}
      </p>
    )
  } else if (allFailed) {
    body = (
      <p className="nl-profile__msg nl-profile__msg--error" role="alert">
        <AlertOctagonIcon size={20} />
        <span>{t('patient:profile.timeline.loadFailed')}</span>
      </p>
    )
  } else {
    body = (
      <>
        {failedCount > 0 && (
          <p className="nl-profile__msg nl-profile__msg--info" role="status">
            <InfoIcon size={20} />
            <span>{t('patient:profile.timeline.partial')}</span>
          </p>
        )}
        {shown.length === 0 ? (
          <p className="nl-profile__muted">{t('patient:profile.timeline.empty')}</p>
        ) : (
          <ul className="nl-profile__timeline">
            {shown.map((item) => (
              <li key={item.key} className="nl-profile__tl-item">
                {item.kind === 'reading' && <Reading row={item.row} />}
                {item.kind === 'alert' && <AlertRow row={item.row} />}
                {item.kind === 'appointment' && <AppointmentRow row={item.row} nowMs={nowMs} />}
                <p className="nl-profile__tl-when">{formatManilaDateTime(item.at, i18n.language)}</p>
              </li>
            ))}
          </ul>
        )}
        {canShowMore && (
          <div className="nl-profile__actions">
            <Button variant="secondary" disabled={readings.loading} onClick={() => setLimit((n) => n + TIMELINE_PAGE)}>
              {readings.loading ? t('ui.loading') : t('patient:profile.timeline.more')}
            </Button>
          </div>
        )}
        {built.limited && !canShowMore && (
          <p className="nl-profile__muted">{t('patient:profile.timeline.limited')}</p>
        )}
      </>
    )
  }

  return (
    <Card title={t('patient:profile.timeline.title')}>
      <div className="nl-profile__form">
        <p className="nl-profile__muted">{t('patient:profile.timeline.intro')}</p>
        {body}
      </div>
    </Card>
  )
}
