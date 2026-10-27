import { useEffect, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import {
  AlertOctagonIcon,
  AlertTriangleIcon,
  Button,
  Card,
  CheckCircleIcon,
  InfoIcon,
  Modal,
  PageHeader,
  Toast,
} from '../../components/ui/index.js'
import { useAuth } from '../../lib/auth.jsx'
import { formatDateTime } from '../../lib/dates.js'
import { runSimulatedCheck } from '../../lib/deviceSimulator.js'
import { friendlyError } from '../../lib/errors.js'
import {
  LOW_BATTERY_PERCENT,
  confidenceLevel,
  sendSos,
  useDevices,
  useHomeStatus,
  useLatestReading,
  useLatestVitals,
  useNextAppointment,
  useProviderAssigned,
} from '../../lib/patientData.js'
import './home.css'

// Patient > Home. Shows the status the DATABASE worked out (my_home_status, 009),
// the latest checks, devices, the next appointment and SOS.
// Rules this screen follows:
//  - A status is never shown as normal unless the database says so. While it
//    loads, or if it cannot be loaded, the banner says so; it never defaults to green.
//  - Nothing here promises that anyone will respond. SOS can only be sent when a
//    provider is known to be assigned; otherwise it shows emergency guidance only.
//  - Monitoring and screening, not diagnosis: the disclaimer is always shown.

const REASONS = [
  'sos_open',
  'alert_critical',
  'alert_open',
  'signal_lost',
  'fhr_out_of_range',
  'low_spo2',
  'fever',
]

// Shows a loading line or a calm error with a retry, otherwise the content.
function Block({ q, children }) {
  const { t } = useTranslation()
  if (q.error) {
    const { text, detail } = friendlyError(t, q.error)
    return (
      <div className="nl-home__problem" role="alert">
        <p>{text}</p>
        {detail && <p className="nl-home__muted">{t('errors:technical_detail', { detail })}</p>}
        <Button variant="secondary" onClick={q.reload}>
          {t('errors:retry')}
        </Button>
      </div>
    )
  }
  if (!q.loaded) {
    return (
      <p className="nl-home__muted" role="status">
        {t('ui.loading')}
      </p>
    )
  }
  return children
}

function StatusBanner({ q, providerAssigned, language }) {
  const { t } = useTranslation()
  const when = (v) => formatDateTime(v, language)

  let kind = 'neutral'
  let Icon = InfoIcon
  let title = t('patient:home.status.loadingTitle')
  let lines = []
  let guidance = []
  let role = 'status'

  if (q.error) {
    title = t('patient:home.status.unavailable')
    lines = [friendlyError(t, q.error).text]
  } else if (q.loaded && q.data) {
    const s = q.data
    const reasons = REASONS.filter((code) => (s.reasons ?? []).includes(code))
    const noProvider = providerAssigned !== true
    if (s.status === 'ok') {
      kind = 'ok'
      Icon = CheckCircleIcon
      title = t('status.success')
      lines = [
        t('patient:home.status.okBody'),
        t('patient:home.status.asOf', { date: when(s.latest_belt_at) }),
      ]
    } else if (s.status === 'attention' || s.status === 'urgent') {
      const urgent = s.status === 'urgent'
      kind = urgent ? 'urgent' : 'attention'
      Icon = urgent ? AlertOctagonIcon : AlertTriangleIcon
      role = urgent ? 'alert' : 'status'
      title = t(urgent ? 'status.danger' : 'status.warning')
      lines = reasons.map((code) => t(`patient:home.reason.${code}`))
      if (urgent) guidance.push(t('patient:home.guidance.emergency'))
      guidance.push(
        noProvider
          ? t('patient:home.guidance.noProvider')
          : urgent
            ? t('patient:home.guidance.providerMayNotSee')
            : t('patient:home.guidance.contactProvider'),
      )
    } else if (s.status === 'no_recent_data') {
      title = t('patient:home.status.noData')
      lines = [
        s.latest_belt_at
          ? t('patient:home.status.stale', { hours: s.fresh_hours, date: when(s.latest_belt_at) })
          : t('patient:home.status.noBelt'),
      ]
    } else {
      title = t('patient:home.status.unavailable')
    }
  }

  return (
    <section className={`nl-home__banner nl-home__banner--${kind}`} role={role} aria-label={title}>
      <div className="nl-home__banner-head">
        <Icon size={28} />
        <h2 className="nl-home__banner-title">{title}</h2>
      </div>
      {lines.length > 0 && (
        <ul className="nl-home__banner-list">
          {lines.map((text) => (
            <li key={text}>{text}</li>
          ))}
        </ul>
      )}
      {q.error && (
        <div>
          <Button variant="secondary" onClick={q.reload}>
            {t('errors:retry')}
          </Button>
        </div>
      )}
      {guidance.map((text) => (
        <p key={text} className="nl-home__banner-guidance">
          {text}
        </p>
      ))}
    </section>
  )
}

function FhrCard({ reading, status, onCheck, checking, language }) {
  const { t } = useTranslation()
  const r = reading.data
  const stale = status.data ? status.data.fresh_belt === false : false
  const level = r && !r.signal_lost ? confidenceLevel(r.confidence) : null
  return (
    <Card title={t('patient:home.fhr.title')} className="nl-home__fhr">
      <Block q={reading}>
        {!r && <p className="nl-home__muted">{t('patient:home.fhr.none')}</p>}
        {r && (
          <>
            {r.signal_lost ? (
              <p className="nl-home__lost">
                <AlertTriangleIcon size={22} />
                <span>{t('patient:home.fhr.signalLost')}</span>
              </p>
            ) : (
              <p className="nl-home__big">
                <span className="nl-home__num">{r.fetal_hr_bpm}</span>{' '}
                <span className="nl-home__unit">{t('patient:home.unit.bpm')}</span>
              </p>
            )}
            {level && (
              <p className={`nl-home__conf nl-home__conf--${level}`}>
                {level === 'high' ? <CheckCircleIcon size={18} /> : <AlertTriangleIcon size={18} />}
                <span>
                  {t('patient:home.fhr.confidence', {
                    level: t(`patient:home.confidence.${level}`),
                    percent: r.confidence,
                  })}
                </span>
              </p>
            )}
            <p className="nl-home__muted">
              {t('patient:home.fhr.checked', { date: formatDateTime(r.measured_at, language) })}
              {stale && ` · ${t('patient:home.notRecent')}`}
            </p>
          </>
        )}
      </Block>
      <div className="nl-home__check">
        <Button onClick={onCheck} disabled={checking}>
          {checking ? t('patient:home.check.checking') : t('patient:home.check.button')}
        </Button>
        <p className="nl-home__muted">{t('patient:home.check.note')}</p>
      </div>
    </Card>
  )
}

function VitalTile({ label, item, unit, format, stale, language }) {
  const { t } = useTranslation()
  return (
    <div className="nl-home__tile">
      <h3 className="nl-home__tile-title">{label}</h3>
      {item ? (
        <>
          <p className="nl-home__big">
            <span className="nl-home__num">{format ? format(item.value) : item.value}</span>{' '}
            <span className="nl-home__unit">{unit}</span>
          </p>
          <p className="nl-home__muted">
            {formatDateTime(item.measured_at, language)}
            {stale && ` · ${t('patient:home.notRecent')}`}
          </p>
        </>
      ) : (
        <p className="nl-home__muted">{t('patient:home.vitals.none')}</p>
      )}
    </div>
  )
}

function VitalsRow({ vitals, status, language }) {
  const { t } = useTranslation()
  const stale = status.data ? status.data.fresh_vitals === false : false
  return (
    <Block q={vitals}>
      <div className="nl-home__tiles">
        <VitalTile
          label={t('patient:home.vitals.hr')}
          item={vitals.data?.hr}
          unit={t('patient:home.unit.bpm')}
          stale={stale}
          language={language}
        />
        <VitalTile
          label={t('patient:home.vitals.spo2')}
          item={vitals.data?.spo2}
          unit={t('patient:home.unit.percent')}
          stale={stale}
          language={language}
        />
        <VitalTile
          label={t('patient:home.vitals.temp')}
          item={vitals.data?.temp}
          unit={t('patient:home.unit.celsius')}
          format={(v) => v.toFixed(1)}
          stale={stale}
          language={language}
        />
      </div>
    </Block>
  )
}

function DeviceRow({ kind, device, language }) {
  const { t } = useTranslation()
  const pct = device.battery_percent
  const low = pct !== null && pct !== undefined && pct < LOW_BATTERY_PERCENT
  return (
    <li className="nl-home__device">
      <strong>{t(`patient:home.device.${kind}`)}</strong>
      <span className={low ? 'nl-home__low' : ''}>
        {low ? <AlertTriangleIcon size={18} /> : null}
        {pct === null || pct === undefined
          ? t('patient:home.device.batteryUnknown')
          : t('patient:home.device.battery', { percent: pct })}
        {low ? ` · ${t('patient:home.device.batteryLow')}` : ''}
      </span>
      <span className="nl-home__muted">
        {device.last_seen_at
          ? t('patient:home.device.lastSeen', { date: formatDateTime(device.last_seen_at, language) })
          : t('patient:home.device.neverSeen')}
      </span>
    </li>
  )
}

function DeviceCard({ devices, language }) {
  const { t } = useTranslation()
  const list = devices.data ?? []
  const belt = list.find((d) => d.kind === 'belt')
  const band = list.find((d) => d.kind === 'band')
  return (
    <Card title={t('patient:home.device.title')}>
      <Block q={devices}>
        {!belt && !band ? (
          <p className="nl-home__muted">{t('patient:home.device.none')}</p>
        ) : (
          <ul className="nl-home__devices">
            {belt && <DeviceRow kind="belt" device={belt} language={language} />}
            {band && <DeviceRow kind="band" device={band} language={language} />}
          </ul>
        )}
      </Block>
    </Card>
  )
}

function AppointmentCard({ appt, language }) {
  const { t } = useTranslation()
  const a = appt.data
  return (
    <Card title={t('patient:home.appt.title')}>
      <Block q={appt}>
        {a ? (
          <>
            <p className="nl-home__big">
              <span className="nl-home__num nl-home__num--sm">{formatDateTime(a.starts_at, language)}</span>
            </p>
            <p className="nl-home__muted">{t(`patient:home.appt.${a.status}`)}</p>
          </>
        ) : (
          <p className="nl-home__muted">{t('patient:home.appt.none')}</p>
        )}
      </Block>
    </Card>
  )
}

function SosCard({ assigned, onOpen }) {
  const { t } = useTranslation()
  return (
    <Card title={t('patient:home.sos.title')} className="nl-home__sos">
      <p>{t('patient:home.sos.guidance')}</p>
      <Button variant="danger" full onClick={onOpen}>
        {assigned === true ? t('patient:home.sos.button') : t('patient:home.sos.buttonHelp')}
      </Button>
    </Card>
  )
}

export default function Home() {
  const { t, i18n } = useTranslation()
  const language = i18n.language
  const { profile } = useAuth()
  const status = useHomeStatus()
  const reading = useLatestReading()
  const vitals = useLatestVitals()
  const appt = useNextAppointment()
  const devices = useDevices()
  const provider = useProviderAssigned()

  const [notice, setNotice] = useState(null) // { variant, text }
  const [checking, setChecking] = useState(false)
  const [sosOpen, setSosOpen] = useState(false)
  const [sending, setSending] = useState(false)
  // A ref changes at once, a state only after the next render, so two quick taps
  // cannot both get through. (The database also limits SOS; this keeps the
  // screen from even sending the extra requests.)
  const busy = useRef({ check: false, sos: false })

  // Fetch everything again when the person comes back to the app.
  const reloadAll = () => [status, reading, vitals, appt, devices, provider].forEach((q) => q.reload())
  const reloadRef = useRef(reloadAll)
  reloadRef.current = reloadAll
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === 'visible') reloadRef.current()
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => document.removeEventListener('visibilitychange', onVisible)
  }, [])

  const assigned = provider.assigned // true, false or null (unknown): only true allows sending

  async function onCheck() {
    if (busy.current.check || !profile) return
    busy.current.check = true
    setChecking(true)
    setNotice(null)
    const find = (kind) => (devices.data ?? []).find((d) => d.kind === kind)?.id ?? null
    const { error } = await runSimulatedCheck({
      patientId: profile.id,
      beltId: find('belt'),
      bandId: find('band'),
    })
    busy.current.check = false
    setChecking(false)
    if (error) setNotice({ variant: 'danger', text: friendlyError(t, error).text })
    else setNotice({ variant: 'success', text: t('patient:home.check.done') })
    reloadAll()
  }

  async function onSendSos() {
    if (busy.current.sos || !profile || assigned !== true) return
    busy.current.sos = true
    setSending(true)
    const { error } = await sendSos(profile.id)
    busy.current.sos = false
    setSending(false)
    setSosOpen(false)
    if (!error) setNotice({ variant: 'warning', text: t('patient:home.sos.sent') })
    else if (error.message === 'sos_rate_limited') {
      // Not a failure: an SOS was already stored a moment ago.
      setNotice({ variant: 'warning', text: friendlyError(t, error).text })
    } else {
      setNotice({
        variant: 'danger',
        text: `${friendlyError(t, error).text} ${t('patient:home.sos.failedAdvice')}`,
      })
    }
    reloadAll()
  }

  return (
    <>
      <PageHeader title={t('patient:tabs.home')} />
      <div className="nl-home">
        {notice && (
          <div className="nl-home__notice">
            <Toast variant={notice.variant} onDismiss={() => setNotice(null)}>
              {notice.text}
            </Toast>
          </div>
        )}

        <StatusBanner q={status} providerAssigned={assigned} language={language} />

        {assigned === false && (
          <section className="nl-home__noprovider" role="note">
            <InfoIcon size={24} />
            <div>
              <h2 className="nl-home__noprovider-title">{t('patient:home.noProvider.title')}</h2>
              <p>{t('patient:home.noProvider.body')}</p>
            </div>
          </section>
        )}

        <div className="nl-home__grid">
          <FhrCard reading={reading} status={status} onCheck={onCheck} checking={checking} language={language} />
          <Card title={t('patient:home.vitals.title')} className="nl-home__vitals">
            <VitalsRow vitals={vitals} status={status} language={language} />
          </Card>
          <DeviceCard devices={devices} language={language} />
          <AppointmentCard appt={appt} language={language} />
          <SosCard assigned={assigned} onOpen={() => setSosOpen(true)} />
        </div>

        <p className="nl-disclaimer">{t('disclaimer')}</p>
      </div>

      <Modal
        open={sosOpen}
        onClose={() => {
          if (!sending) setSosOpen(false)
        }}
        title={assigned === true ? t('patient:home.sos.confirmTitle') : t('patient:home.sos.helpTitle')}
        actions={
          assigned === true ? (
            <>
              <Button variant="secondary" onClick={() => setSosOpen(false)} disabled={sending}>
                {t('patient:home.sos.cancel')}
              </Button>
              <Button variant="danger" onClick={onSendSos} disabled={sending}>
                {sending ? t('patient:home.sos.sending') : t('patient:home.sos.send')}
              </Button>
            </>
          ) : (
            <Button variant="secondary" onClick={() => setSosOpen(false)}>
              {t('ui.close')}
            </Button>
          )
        }
      >
        <p>{t('patient:home.sos.guidance')}</p>
        <p>
          {assigned === true
            ? t('patient:home.sos.confirmBody')
            : assigned === false
              ? t('patient:home.sos.noProviderBody')
              : t('patient:home.sos.unknownBody')}
        </p>
      </Modal>
    </>
  )
}
