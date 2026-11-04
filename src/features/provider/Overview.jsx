import { useTranslation } from 'react-i18next'
import { Link, Outlet, useMatch, useNavigate } from 'react-router-dom'
import { SplitView } from '../../components/layout/index.js'
import {
  ActivityIcon,
  AlertOctagonIcon,
  BellIcon,
  Button,
  Card,
  CheckIcon,
  EmptyState,
  InfoIcon,
  PageHeader,
  StatusBadge,
} from '../../components/ui/index.js'
import { formatManilaDateTime } from '../../lib/dates.js'
import { friendlyError } from '../../lib/errors.js'
import { OPEN_ALERTS_LIMIT, useProviderOverview } from '../../lib/providerData.js'
import './overview.css'

// Provider > Overview (step 4.1).
// Rules this screen follows:
//  - The status, the missed-check flag and the order of the list come from the
//    database (provider_overview(), migration 015). This screen never works them out.
//  - Only the signed-in provider's assigned patients can ever be in the list: the
//    database limits every query. The route guard only picks the screen.
//  - Every piece of text from the database (the patient's chosen name) is shown as
//    plain text. It is never shown as verified: patients type it themselves.
//  - Status is icon + text + color. "No recent data" is never shown as stable.
//  - "Patient has seen this" is information only. It never sorts, hides or closes an
//    alert.
//  - Nothing here promises a response or a time. Times are Philippine time.
//  - Tapping a patient opens a placeholder (step 4.3 adds the record). No patient
//    data is shown there.
//  - Live: alert events refetch the list; falls back to every 30 seconds.
//  - Monitoring and screening, not diagnosis: the disclaimer is always shown.

function fallbackPatient(id) {
  return { patient_id: id, label_code: String(id ?? '').slice(0, 6).toUpperCase(), display_name: null }
}

function PatientLabel({ patient }) {
  const { t } = useTranslation()
  const code = patient.label_code
  if (patient.display_name) {
    return (
      <span className="nl-ov__label">
        <span className="nl-ov__name">{patient.display_name}</span>
        <span className="nl-ov__code">{t('provider:overview.code', { code })}</span>
      </span>
    )
  }
  return (
    <span className="nl-ov__label">
      <span className="nl-ov__name">{t('provider:overview.patientNoName', { code })}</span>
    </span>
  )
}

// critical / warning / stable use the shared badge (icon + words + color).
const STATUS = {
  urgent: { kind: 'danger', labelKey: 'provider:overview.status.critical' },
  attention: { kind: 'warning', labelKey: 'provider:overview.status.warning' },
  ok: { kind: 'success', labelKey: 'provider:overview.status.stable' },
}

function StatusLabel({ status }) {
  const { t } = useTranslation()
  const entry = STATUS[status]
  if (entry) return <StatusBadge status={entry.kind}>{t(entry.labelKey)}</StatusBadge>
  // "No recent data" and any status this screen does not know: neutral, never green.
  return (
    <span className="nl-badge nl-ov__badge-neutral">
      <InfoIcon />
      <span>{status === 'no_recent_data' ? t('provider:overview.status.noData') : t('provider:overview.status.unknown')}</span>
    </span>
  )
}

function alertTypeText(t, type) {
  switch (type) {
    case 'sos':
      return t('alerts:type.sos')
    case 'fhr_out_of_range':
      return t('alerts:type.fhr_out_of_range')
    case 'signal_loss':
      return t('alerts:type.signal_loss')
    case 'low_spo2':
      return t('alerts:type.low_spo2')
    case 'fever':
      return t('alerts:type.fever')
    default:
      return t('alerts:type.other')
  }
}

function SeverityLabel({ severity }) {
  const { t } = useTranslation()
  if (severity === 'critical') return <StatusBadge status="danger">{t('alerts:severity.critical')}</StatusBadge>
  if (severity === 'warning') return <StatusBadge status="warning">{t('alerts:severity.warning')}</StatusBadge>
  return (
    <span className="nl-badge nl-ov__badge-neutral">
      <InfoIcon />
      <span>{t('alerts:severity.info')}</span>
    </span>
  )
}

function patientPath(id) {
  return `/provider/patient/${encodeURIComponent(id)}`
}

function LastCheck({ patient, language }) {
  const { t } = useTranslation()
  if (!patient.last_check_at) return <span>{t('provider:overview.noCheckYet')}</span>
  return <span>{t('provider:overview.lastCheck', { time: formatManilaDateTime(patient.last_check_at, language) })}</span>
}

function SosBanner({ patients, language }) {
  const { t } = useTranslation()
  const open = patients
    .filter((p) => p.sos_open)
    .sort((a, b) => String(a.sos_since ?? '').localeCompare(String(b.sos_since ?? '')))
  if (open.length === 0) return null
  return (
    <section className="nl-ov__sos" aria-labelledby="nl-ov-sos-title">
      <h2 id="nl-ov-sos-title" className="nl-ov__sos-title">
        <AlertOctagonIcon size={24} />
        <span>{t('provider:overview.sos.title')}</span>
      </h2>
      <ul className="nl-ov__plain-list">
        {open.map((p) => (
          <li key={p.patient_id}>
            <Link to={patientPath(p.patient_id)} className="nl-ov__sos-row">
              <PatientLabel patient={p} />
              <span>
                {p.sos_since
                  ? t('provider:overview.sos.sentAt', { time: formatManilaDateTime(p.sos_since, language) })
                  : t('provider:overview.sos.sent')}
              </span>
            </Link>
          </li>
        ))}
      </ul>
      <p className="nl-ov__sos-note">{t('provider:overview.sos.note')}</p>
    </section>
  )
}

function OpenAlerts({ alerts, byId, language }) {
  const { t } = useTranslation()
  return (
    <Card title={t('provider:overview.alerts.title')} className="nl-ov__card">
      <p className="nl-ov__muted">{t('provider:overview.alerts.seenNote')}</p>
      {alerts.length === 0 ? (
        <p className="nl-ov__empty-line">
          <CheckIcon size={18} />
          <span>{t('provider:overview.alerts.none')}</span>
        </p>
      ) : (
        <ul className="nl-ov__plain-list">
          {alerts.map((a) => (
            <li key={a.id}>
              <Link to={patientPath(a.patient_id)} className="nl-ov__row">
                <PatientLabel patient={byId.get(a.patient_id) ?? fallbackPatient(a.patient_id)} />
                <span className="nl-ov__badges">
                  <SeverityLabel severity={a.severity} />
                  <span className="nl-ov__type">{alertTypeText(t, a.alert_type)}</span>
                </span>
                <span className="nl-ov__meta">
                  {t('provider:overview.alerts.raised', { time: formatManilaDateTime(a.created_at, language) })}
                </span>
                {a.seen_by_patient_at && (
                  <span className="nl-ov__meta nl-ov__seen">
                    <CheckIcon size={16} />
                    <span>{t('provider:overview.alerts.seen', { time: formatManilaDateTime(a.seen_by_patient_at, language) })}</span>
                  </span>
                )}
              </Link>
            </li>
          ))}
        </ul>
      )}
      {alerts.length >= OPEN_ALERTS_LIMIT && <p className="nl-ov__muted">{t('provider:overview.alerts.limit')}</p>}
    </Card>
  )
}

function TriageList({ patients, selectedId, language }) {
  const { t } = useTranslation()
  return (
    <Card title={t('provider:overview.triage.title')} className="nl-ov__card">
      <p className="nl-ov__muted">{t('provider:overview.triage.nameNote')}</p>
      <ul className="nl-ov__plain-list">
        {patients.map((p) => (
          <li key={p.patient_id}>
            <Link
              to={patientPath(p.patient_id)}
              className="nl-ov__row"
              aria-current={selectedId === p.patient_id ? 'page' : undefined}
            >
              <PatientLabel patient={p} />
              <span className="nl-ov__badges">
                <StatusLabel status={p.status} />
                {p.sos_open && (
                  <span className="nl-badge nl-badge--danger">
                    <AlertOctagonIcon />
                    <span>{t('provider:overview.sos.badge')}</span>
                  </span>
                )}
                {p.missed_check && (
                  <span className="nl-badge nl-ov__badge-missed">
                    <ActivityIcon size={18} />
                    <span>{t('provider:overview.missed.badge')}</span>
                  </span>
                )}
              </span>
              <span className="nl-ov__meta">
                <LastCheck patient={p} language={language} />
                {p.open_alert_count > 0 && <span> · {t('provider:overview.triage.openAlerts', { count: p.open_alert_count })}</span>}
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </Card>
  )
}

function MissedChecks({ patients, language }) {
  const { t } = useTranslation()
  const missed = patients.filter((p) => p.missed_check)
  return (
    <Card title={t('provider:overview.missed.title')} className="nl-ov__card">
      <p className="nl-ov__muted">{t('provider:overview.missed.draftNote')}</p>
      {missed.length === 0 ? (
        <p className="nl-ov__empty-line">
          <CheckIcon size={18} />
          <span>{t('provider:overview.missed.none')}</span>
        </p>
      ) : (
        <ul className="nl-ov__plain-list">
          {missed.map((p) => (
            <li key={p.patient_id}>
              <Link to={patientPath(p.patient_id)} className="nl-ov__row">
                <PatientLabel patient={p} />
                <span className="nl-ov__meta">
                  <LastCheck patient={p} language={language} />
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </Card>
  )
}

// This component stays mounted while the patient placeholder opens next to it
// (nested route), so opening a patient never reloads the list.
export default function Overview() {
  const { t, i18n } = useTranslation()
  const language = i18n.language
  const navigate = useNavigate()
  // Read the id from the address itself (works for a layout route and its child).
  const patientId = useMatch('/provider/patient/:patientId')?.params.patientId
  const data = useProviderOverview()

  const patients = data.patients ?? []
  const byId = new Map(patients.map((p) => [p.patient_id, p]))

  let listPane
  if (!data.loaded) {
    listPane = (
      <p className="nl-empty__body" role="status">
        {t('ui.loading')}
      </p>
    )
  } else if (data.error) {
    const { text, detail } = friendlyError(t, data.error)
    listPane = (
      <Card className="nl-ov__card">
        <div className="nl-ov__problem" role="alert">
          <p>{text}</p>
          {detail && <p className="nl-ov__muted">{detail}</p>}
          <Button variant="secondary" onClick={data.reload}>
            {t('provider:overview.retry')}
          </Button>
        </div>
      </Card>
    )
  } else if (patients.length === 0) {
    listPane = <EmptyState title={t('provider:overview.empty.title')} body={t('provider:overview.empty.body')} />
  } else {
    listPane = (
      <div className="nl-ov__stack">
        <OpenAlerts alerts={data.alerts ?? []} byId={byId} language={language} />
        <TriageList patients={patients} selectedId={patientId} language={language} />
        <MissedChecks patients={patients} language={language} />
      </div>
    )
  }

  return (
    <div className="nl-ov">
      <PageHeader title={t('provider:tabs.overview')} subtitle={t('provider:overview.timesNote')} />
      {data.live === 'paused' && (
        <p className="nl-ov__line" role="status">
          <InfoIcon size={18} />
          <span>{t('provider:overview.livePaused')}</span>
        </p>
      )}
      {data.refreshFailed && (
        <p className="nl-ov__line" role="status">
          <BellIcon size={18} />
          <span>{t('provider:overview.refreshFailed')}</span>
        </p>
      )}
      {data.loaded && !data.error && <SosBanner patients={patients} language={language} />}
      <SplitView
        hasSelection={Boolean(patientId)}
        onBack={() => navigate('/provider')}
        emptyDetail={t('provider:overview.selectPatient')}
        list={listPane}
        detail={<Outlet />}
      />
      <p className="nl-disclaimer">{t('disclaimer')}</p>
    </div>
  )
}
