import { useId, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import {
  AlertTriangleIcon,
  BellIcon,
  Button,
  Card,
  CheckCircleIcon,
  CheckIcon,
  InfoIcon,
  PageHeader,
  StatusBadge,
  Toast,
} from '../../components/ui/index.js'
import { formatManilaDateTime } from '../../lib/dates.js'
import { friendlyError } from '../../lib/errors.js'
import { ALERTS_LIMIT, markAlertSeen, useAlerts, useProviderAssigned } from '../../lib/patientData.js'
import { alertSentence, alertTypeLabel, isHandled, severityKind } from './alertText.js'
import './alerts.css'

// Patient > Alerts (step 3.3).
// Rules this screen follows:
//  - Read-only apart from one action: "Mark as seen" (database function
//    mark_alert_seen, migration 011). Seen is cosmetic: it never closes an alert,
//    changes its status, or says anyone has handled it.
//  - Wording is built from the numbers in alerts.details through i18n (alertText.js);
//    no text from the database is shown, and no raw HTML is ever rendered.
//  - Nothing promises a response or a time. "Handled" only appears when a
//    provider has acknowledged or resolved the alert.
//  - Times are shown in Philippine time (Asia/Manila).
//  - The list updates live (Realtime) and falls back to a refresh every 30 seconds.
//  - Monitoring and screening, not diagnosis: the disclaimer is always shown.

const FILTERS = ['open', 'handled']

function SeverityBadge({ severity }) {
  const { t } = useTranslation()
  const kind = severityKind(severity)
  if (kind === 'info') {
    return (
      <span className="nl-badge nl-alerts__badge-info">
        <InfoIcon />
        <span>{t('patient:alerts.severity.info')}</span>
      </span>
    )
  }
  // StatusBadge always draws an icon and the words (Urgent / Needs attention).
  return <StatusBadge status={kind} />
}

function StatusLine({ alert, language }) {
  const { t } = useTranslation()
  if (!isHandled(alert)) {
    return (
      <p className="nl-alerts__status">
        <BellIcon size={18} />
        <span>
          <strong>{t('patient:alerts.status.open')}</strong> · {t('patient:alerts.status.openNote')}
        </span>
      </p>
    )
  }
  const resolved = alert.status === 'resolved'
  const when = resolved ? (alert.resolved_at ?? alert.acknowledged_at) : alert.acknowledged_at
  return (
    <p className="nl-alerts__status nl-alerts__status--handled">
      <CheckCircleIcon size={18} />
      <span>
        <strong>{t('patient:alerts.status.handled')}</strong>
        {when
          ? ` · ${t(resolved ? 'patient:alerts.status.resolvedOn' : 'patient:alerts.status.handledOn', {
              date: formatManilaDateTime(when, language),
            })}`
          : ''}
      </span>
    </p>
  )
}

function AlertItem({ alert, language, pending, onSeen }) {
  const { t } = useTranslation()
  const titleId = useId()
  const urgentOpen = alert.alert_type === 'sos' && !isHandled(alert)
  return (
    <li className={`nl-alerts__item nl-alerts__item--${severityKind(alert.severity)}`}>
      <div className="nl-alerts__item-head">
        <SeverityBadge severity={alert.severity} />
        <h3 id={titleId} className="nl-alerts__item-title">
          {alertTypeLabel(t, alert.alert_type)}
        </h3>
      </div>
      <p>{alertSentence(t, alert)}</p>
      {urgentOpen && <p className="nl-alerts__strong">{t('patient:alerts.sos.openGuidance')}</p>}
      <p className="nl-alerts__muted">{t('patient:alerts.raised', { date: formatManilaDateTime(alert.created_at, language) })}</p>
      <StatusLine alert={alert} language={language} />
      <div className="nl-alerts__seen">
        {alert.seen_by_patient_at ? (
          <p className="nl-alerts__seen-done">
            <CheckIcon size={18} />
            <span>{t('patient:alerts.seen.done', { date: formatManilaDateTime(alert.seen_by_patient_at, language) })}</span>
          </p>
        ) : (
          <Button variant="secondary" onClick={() => onSeen(alert.id)} disabled={pending} aria-describedby={titleId}>
            {pending ? t('patient:alerts.seen.marking') : t('patient:alerts.seen.button')}
          </Button>
        )}
      </div>
    </li>
  )
}

function ContactCard({ provider }) {
  const { t } = useTranslation()
  const { assigned } = provider
  if (assigned === true) {
    return (
      <Card title={t('patient:alerts.contact.title')} className="nl-alerts__contact">
        <p>{t('patient:alerts.contact.placeholder')}</p>
        <Link to="/patient/care" className="nl-btn nl-btn--secondary nl-alerts__link">
          {t('patient:alerts.contact.button')}
        </Link>
        <p>{t('patient:home.guidance.providerMayNotSee')}</p>
        <p className="nl-alerts__strong">{t('patient:home.guidance.emergency')}</p>
      </Card>
    )
  }
  if (assigned === false) {
    return (
      <Card title={t('patient:home.noProvider.title')} className="nl-alerts__contact nl-alerts__contact--none">
        <p>{t('patient:alerts.contact.noProviderBody')}</p>
        <p className="nl-alerts__strong">{t('patient:home.guidance.emergency')}</p>
      </Card>
    )
  }
  // Not known yet, or could not be read: say so and give the safe guidance.
  return (
    <Card title={t('patient:alerts.contact.title')} className="nl-alerts__contact nl-alerts__contact--none">
      {provider.loaded || provider.error ? (
        <>
          <p>{t('patient:alerts.contact.unknownBody')}</p>
          <p className="nl-alerts__strong">{t('patient:home.guidance.emergency')}</p>
          <div>
            <Button variant="secondary" onClick={provider.reload}>
              {t('errors:retry')}
            </Button>
          </div>
        </>
      ) : (
        <p className="nl-alerts__muted" role="status">
          {t('ui.loading')}
        </p>
      )}
    </Card>
  )
}

function FilterSwitch({ filter, counts, onChange }) {
  const { t } = useTranslation()
  return (
    <div className="nl-alerts__filters" role="group" aria-label={t('patient:alerts.filter.label')}>
      <span className="nl-alerts__filters-label">{t('patient:alerts.filter.label')}</span>
      {FILTERS.map((f) => (
        <button
          key={f}
          type="button"
          className="nl-alerts__filter"
          aria-pressed={filter === f}
          onClick={() => onChange(f)}
        >
          {filter === f && <CheckIcon size={18} />}
          {t('patient:alerts.filter.withCount', { label: t(`patient:alerts.filter.${f}`), count: counts[f] })}
        </button>
      ))}
    </div>
  )
}

export default function AlertsPage() {
  const { t, i18n } = useTranslation()
  const language = i18n.language
  const alerts = useAlerts()
  const provider = useProviderAssigned()
  const [filter, setFilter] = useState('open')
  const [notice, setNotice] = useState(null) // { variant, text }
  const [pendingId, setPendingId] = useState(null)
  const busy = useRef(false) // a ref changes at once, so two quick taps cannot both go through

  const all = alerts.data ?? []
  const clinical = all.filter((a) => a.alert_type !== 'sos')
  const sos = all.filter((a) => a.alert_type === 'sos')
  const counts = {
    open: clinical.filter((a) => !isHandled(a)).length,
    handled: clinical.filter(isHandled).length,
  }
  const openTotal = all.filter((a) => !isHandled(a)).length
  const shown = clinical.filter((a) => (filter === 'open' ? !isHandled(a) : isHandled(a)))

  async function onSeen(id) {
    if (busy.current) return
    busy.current = true
    setPendingId(id)
    setNotice(null)
    const { error } = await markAlertSeen(id)
    busy.current = false
    setPendingId(null)
    if (error) setNotice({ variant: 'danger', text: friendlyError(t, error).text })
    else setNotice({ variant: 'success', text: t('patient:alerts.seen.saved') })
    alerts.reload()
  }

  let body
  if (alerts.error) {
    const { text, detail } = friendlyError(t, alerts.error)
    body = (
      <div className="nl-alerts__problem" role="alert">
        <p>{text}</p>
        {detail && <p className="nl-alerts__muted">{t('errors:technical_detail', { detail })}</p>}
        <Button variant="secondary" onClick={alerts.reload}>
          {t('errors:retry')}
        </Button>
      </div>
    )
  } else if (!alerts.loaded) {
    body = (
      <p className="nl-alerts__muted" role="status">
        {t('ui.loading')}
      </p>
    )
  } else {
    body = (
      <>
        <FilterSwitch filter={filter} counts={counts} onChange={setFilter} />
        {shown.length === 0 ? (
          <p className="nl-alerts__empty" role="status">
            <InfoIcon size={20} />
            <span>{t(filter === 'open' ? 'patient:alerts.list.emptyOpen' : 'patient:alerts.list.emptyHandled')}</span>
          </p>
        ) : (
          <ul className="nl-alerts__list" aria-live="polite" aria-relevant="additions">
            {shown.map((a) => (
              <AlertItem key={a.id} alert={a} language={language} pending={pendingId === a.id} onSeen={onSeen} />
            ))}
          </ul>
        )}
        <p className="nl-alerts__muted">{t('patient:alerts.seen.note')}</p>
        {all.length >= ALERTS_LIMIT && <p className="nl-alerts__muted">{t('patient:alerts.truncated', { count: ALERTS_LIMIT })}</p>}
      </>
    )
  }

  return (
    <>
      <PageHeader title={t('patient:tabs.alerts')} />
      <div className="nl-alerts">
        {notice && (
          <div className="nl-alerts__notice">
            <Toast variant={notice.variant} onDismiss={() => setNotice(null)}>
              {notice.text}
            </Toast>
          </div>
        )}

        <div className="nl-alerts__top">
          <p>{t('patient:alerts.intro')}</p>
          {alerts.loaded && !alerts.error && (
            <p className="nl-alerts__summary">
              {openTotal > 0 ? <AlertTriangleIcon size={20} /> : <InfoIcon size={20} />}
              <span>{t('patient:alerts.summary', { count: openTotal })}</span>
            </p>
          )}
          <p className="nl-alerts__muted">{t('patient:alerts.timeNote')}</p>
          {alerts.live === 'paused' && (
            <p className="nl-alerts__line" role="status">
              <InfoIcon size={20} />
              <span>{t('patient:alerts.live.paused')}</span>
            </p>
          )}
          {alerts.refreshFailed && (
            <p className="nl-alerts__line" role="status">
              <InfoIcon size={20} />
              <span>{t('patient:alerts.live.stale')}</span>
            </p>
          )}
        </div>

        <div className="nl-alerts__grid">
          <Card title={t('patient:alerts.list.title')} className="nl-alerts__main">
            {body}
          </Card>

          <aside className="nl-alerts__side">
            <ContactCard provider={provider} />

            <Card title={t('patient:alerts.sos.title')} className="nl-alerts__sos">
              <p className="nl-alerts__muted">{t('patient:alerts.sos.note')}</p>
              {!alerts.loaded || alerts.error ? (
                <p className="nl-alerts__muted">{alerts.error ? t('patient:alerts.sos.unavailable') : t('ui.loading')}</p>
              ) : sos.length === 0 ? (
                <p className="nl-alerts__empty" role="status">
                  <InfoIcon size={20} />
                  <span>{t('patient:alerts.sos.empty')}</span>
                </p>
              ) : (
                <ul className="nl-alerts__list">
                  {sos.map((a) => (
                    <AlertItem key={a.id} alert={a} language={language} pending={pendingId === a.id} onSeen={onSeen} />
                  ))}
                </ul>
              )}
            </Card>
          </aside>
        </div>

        <p className="nl-disclaimer">{t('disclaimer')}</p>
      </div>
    </>
  )
}
