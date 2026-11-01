import { useEffect, useId, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import {
  Button,
  Card,
  CheckCircleIcon,
  CheckIcon,
  CloseIcon,
  FileTextIcon,
  InfoIcon,
  MessageIcon,
  Modal,
  PageHeader,
  TextField,
  Toast,
} from '../../components/ui/index.js'
import { formatManilaDateTime } from '../../lib/dates.js'
import { friendlyError } from '../../lib/errors.js'
import {
  APPOINTMENTS_LIMIT,
  cancelAppointment,
  requestAppointment,
  rescheduleAppointment,
  useAppointments,
  useProviderAssigned,
  useProviderName,
} from '../../lib/patientData.js'
import {
  APPT_DEFAULT_MINUTES,
  APPT_MAX_AHEAD_DAYS,
  APPT_MIN_LEAD_MINUTES,
  manilaDateRange,
  manilaToUtcIso,
  splitAppointments,
  statusKind,
} from './careTime.js'
import './care.css'

// Patient > Care (step 3.4).
// Rules this screen follows:
//  - Patients have no direct write access to appointments. Request, cancel and
//    reschedule go through database functions (migration 012); the provider is
//    chosen by the database from the patient's own assignment, never sent from here.
//  - A request is NOT confirmed until the provider confirms it. The screen never
//    promises a response or a time. Database status "scheduled" is shown as "Confirmed".
//  - A confirmed visit can be cancelled (with a confirm step) but never moved from
//    here; "Change time" exists only for requests that are still not confirmed.
//  - Times are typed and shown in Philippine time (Asia/Manila) and stored in UTC.
//  - Everything from the database is rendered as plain text (no HTML of any kind).
//  - Status is always an icon plus words plus a colour, never colour alone.
//  - No Realtime here: the list reloads when the person returns to the app and
//    after every action. The database decides what is allowed; this screen only
//    shows friendly messages for its answers.
//  - Chat and video (Phase 6) and consult history are placeholders.
//  - Monitoring and screening, not diagnosis: the disclaimer is always shown.

const PAST_PAGE = 10

const STATUS_ICON = {
  requested: InfoIcon,
  scheduled: CheckCircleIcon,
  completed: CheckIcon,
  cancelled: CloseIcon,
  notConfirmed: InfoIcon,
}

function AppointmentStatus({ kind }) {
  const { t } = useTranslation()
  const Icon = STATUS_ICON[kind] ?? InfoIcon
  return (
    <span className={`nl-badge nl-care__badge nl-care__badge--${kind}`}>
      <Icon />
      <span>{t(`patient:care.appt.status.${kind}`)}</span>
    </span>
  )
}

// A date and a time, typed in Philippine time. Returns { iso, errors }; iso is the
// UTC moment to send, or null when something is missing, not real, or in the past.
// The database still decides the 1 hour and 90 day limits.
function checkWhen(date, time, t, nowMs) {
  const errors = {}
  if (!date) errors.date = t('patient:care.request.dateRequired')
  if (!time) errors.time = t('patient:care.request.timeRequired')
  if (errors.date || errors.time) return { iso: null, errors }
  const iso = manilaToUtcIso(date, time)
  if (!iso) return { iso: null, errors: { date: t('errors:appointment_time_invalid') } }
  if (new Date(iso).getTime() < nowMs) return { iso: null, errors: { date: t('errors:appointment_too_soon') } }
  return { iso, errors: {} }
}

function WhenFields({ idPrefix, date, time, onDate, onTime, errors, disabled }) {
  const { t } = useTranslation()
  const range = manilaDateRange(Date.now())
  return (
    <div className="nl-care__when">
      <TextField
        id={`${idPrefix}-date`}
        type="date"
        label={t('patient:care.request.dateLabel')}
        value={date}
        onChange={(e) => onDate(e.target.value)}
        min={range.min}
        max={range.max}
        disabled={disabled}
        required
        error={errors.date}
      />
      <TextField
        id={`${idPrefix}-time`}
        type="time"
        label={t('patient:care.request.timeLabel')}
        value={time}
        onChange={(e) => onTime(e.target.value)}
        disabled={disabled}
        required
        error={errors.time}
      />
    </div>
  )
}

function RequestForm({ enabled, reason, sending, onSubmit }) {
  const { t } = useTranslation()
  const prefix = useId()
  const [date, setDate] = useState('')
  const [time, setTime] = useState('')
  const [errors, setErrors] = useState({})

  async function submit(e) {
    e.preventDefault()
    if (!enabled || sending) return
    const result = checkWhen(date, time, t, Date.now())
    setErrors(result.errors)
    if (!result.iso) return
    const { error } = await onSubmit(result.iso)
    if (!error) {
      setDate('')
      setTime('')
    }
  }

  return (
    <form noValidate onSubmit={submit} className="nl-care__form">
      <WhenFields
        idPrefix={prefix}
        date={date}
        time={time}
        onDate={setDate}
        onTime={setTime}
        errors={errors}
        disabled={!enabled}
      />
      <p className="nl-care__muted">
        {t('patient:care.request.hint', { minutes: APPT_MIN_LEAD_MINUTES, days: APPT_MAX_AHEAD_DAYS })}
      </p>
      <p className="nl-care__muted">{t('patient:care.request.durationNote', { minutes: APPT_DEFAULT_MINUTES })}</p>
      {!enabled && (
        <p className="nl-care__line" role="status">
          <InfoIcon size={20} />
          <span>{reason}</span>
        </p>
      )}
      <div>
        <Button type="submit" disabled={!enabled || sending}>
          {sending ? t('patient:care.request.sending') : t('patient:care.request.submit')}
        </Button>
      </div>
    </form>
  )
}

function ChangeModal({ appt, language, busy, error, onClose, onSave }) {
  const { t } = useTranslation()
  const formId = useId()
  const [date, setDate] = useState('')
  const [time, setTime] = useState('')
  const [errors, setErrors] = useState({})

  function submit(e) {
    e.preventDefault()
    if (busy) return
    const result = checkWhen(date, time, t, Date.now())
    setErrors(result.errors)
    if (result.iso) onSave(result.iso)
  }

  return (
    <Modal
      open={!!appt}
      onClose={onClose}
      title={t('patient:care.change.title')}
      actions={
        <>
          <Button variant="secondary" onClick={onClose}>
            {t('patient:care.change.close')}
          </Button>
          <Button type="submit" form={formId} disabled={busy}>
            {busy ? t('patient:care.change.saving') : t('patient:care.change.submit')}
          </Button>
        </>
      }
    >
      <form id={formId} noValidate onSubmit={submit} className="nl-care__form">
        <p>{t('patient:care.change.body')}</p>
        {appt && <p className="nl-care__muted">{t('patient:care.change.current', { date: formatManilaDateTime(appt.starts_at, language) })}</p>}
        <WhenFields
          idPrefix={formId}
          date={date}
          time={time}
          onDate={setDate}
          onTime={setTime}
          errors={errors}
          disabled={busy}
        />
        <p className="nl-care__muted">
          {t('patient:care.request.hint', { minutes: APPT_MIN_LEAD_MINUTES, days: APPT_MAX_AHEAD_DAYS })}
        </p>
        {error && (
          <p className="nl-care__problem" role="alert">
            {error}
          </p>
        )}
      </form>
    </Modal>
  )
}

function CancelModal({ appt, language, busy, error, onClose, onConfirm }) {
  const { t } = useTranslation()
  const confirmed = appt?.status === 'scheduled'
  return (
    <Modal
      open={!!appt}
      onClose={onClose}
      title={t('patient:care.cancel.title')}
      actions={
        <>
          <Button variant="secondary" onClick={onClose}>
            {t('patient:care.cancel.keep')}
          </Button>
          <Button variant="danger" onClick={onConfirm} disabled={busy}>
            {busy ? t('patient:care.cancel.cancelling') : t('patient:care.cancel.confirm')}
          </Button>
        </>
      }
    >
      {appt && (
        <div className="nl-care__form">
          <p>
            <strong>{formatManilaDateTime(appt.starts_at, language)}</strong>
          </p>
          <p>{confirmed ? t('patient:care.cancel.confirmedBody') : t('patient:care.cancel.requestedBody')}</p>
          {error && (
            <p className="nl-care__problem" role="alert">
              {error}
            </p>
          )}
        </div>
      )}
    </Modal>
  )
}

function AppointmentItem({ appt, kind, upcoming, language, onCancel, onChange }) {
  const { t } = useTranslation()
  const titleId = useId()
  let note = null
  if (kind === 'requested') {
    note = appt.provider_id ? t('patient:care.appt.note.requested') : t('patient:care.appt.note.requestedNoProvider')
  } else if (kind === 'scheduled' && upcoming) {
    note = t('patient:care.appt.note.scheduled')
  } else if (kind === 'notConfirmed') {
    note = t('patient:care.appt.note.notConfirmed')
  }
  return (
    <li className={`nl-care__item nl-care__item--${kind}`}>
      <div className="nl-care__item-head">
        <AppointmentStatus kind={kind} />
        <h3 id={titleId} className="nl-care__item-title">
          {formatManilaDateTime(appt.starts_at, language)}
        </h3>
      </div>
      <p className="nl-care__muted">{t('patient:care.appt.duration', { minutes: appt.duration_minutes })}</p>
      {note && <p>{note}</p>}
      {upcoming && (
        <div className="nl-care__actions">
          {appt.status === 'requested' && appt.provider_id && (
            <Button variant="secondary" onClick={() => onChange(appt)} aria-describedby={titleId}>
              {t('patient:care.appt.change')}
            </Button>
          )}
          <Button variant="secondary" onClick={() => onCancel(appt)} aria-describedby={titleId}>
            {t('patient:care.appt.cancel')}
          </Button>
        </div>
      )}
    </li>
  )
}

function ProviderCard({ provider, name }) {
  const { t } = useTranslation()
  if (provider.assigned === true) {
    return (
      <Card title={t('patient:care.provider.title')} className="nl-care__side-card">
        {name.data ? (
          <p className="nl-care__provider-name">{name.data}</p>
        ) : name.loaded || name.error ? (
          <p className="nl-care__muted">{t('patient:care.provider.noName')}</p>
        ) : (
          <p className="nl-care__muted" role="status">
            {t('ui.loading')}
          </p>
        )}
        <p className="nl-care__muted">{t('patient:care.provider.note')}</p>
      </Card>
    )
  }
  if (provider.assigned === false) {
    return (
      <Card title={t('patient:care.noProvider.title')} className="nl-care__side-card nl-care__side-card--none">
        <p>{t('patient:care.noProvider.body')}</p>
        <p className="nl-care__strong">{t('patient:home.guidance.emergency')}</p>
      </Card>
    )
  }
  return (
    <Card title={t('patient:care.provider.title')} className="nl-care__side-card nl-care__side-card--none">
      {provider.loaded || provider.error ? (
        <>
          <p>{t('patient:care.provider.unknown')}</p>
          <div>
            <Button variant="secondary" onClick={provider.reload}>
              {t('errors:retry')}
            </Button>
          </div>
        </>
      ) : (
        <p className="nl-care__muted" role="status">
          {t('ui.loading')}
        </p>
      )}
    </Card>
  )
}

export default function CarePage() {
  const { t, i18n } = useTranslation()
  const language = i18n.language
  const appts = useAppointments()
  const provider = useProviderAssigned()
  const providerName = useProviderName()

  const [notice, setNotice] = useState(null) // { variant, text }
  const [cancelling, setCancelling] = useState(null) // the appointment in the cancel dialog
  const [changing, setChanging] = useState(null) // the appointment in the change-time dialog
  const [modalError, setModalError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [pastShown, setPastShown] = useState(PAST_PAGE)
  // A ref changes at once, a state only after the next render, so two quick taps
  // cannot both send a request.
  const lock = useRef(false)

  // Fetch again when the person comes back to the app (there is no Realtime here).
  const reloadAll = () => [appts, provider, providerName].forEach((q) => q.reload())
  const reloadRef = useRef(reloadAll)
  reloadRef.current = reloadAll
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === 'visible') reloadRef.current()
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => document.removeEventListener('visibilitychange', onVisible)
  }, [])

  const now = Date.now()
  const { upcoming, past } = splitAppointments(appts.data, now)
  const assigned = provider.assigned // true, false or null (unknown): only true allows a request

  async function onRequest(iso) {
    if (lock.current) return { error: { message: 'busy' } }
    lock.current = true
    setBusy(true)
    setNotice(null)
    const { error } = await requestAppointment(iso)
    lock.current = false
    setBusy(false)
    setNotice(error ? { variant: 'danger', text: friendlyError(t, error).text } : { variant: 'success', text: t('patient:care.request.sent') })
    appts.reload()
    return { error }
  }

  async function onConfirmCancel() {
    if (lock.current || !cancelling) return
    lock.current = true
    setBusy(true)
    setModalError(null)
    const { error } = await cancelAppointment(cancelling.id)
    lock.current = false
    setBusy(false)
    appts.reload()
    if (error) {
      setModalError(friendlyError(t, error).text)
      return
    }
    setCancelling(null)
    setNotice({ variant: 'success', text: t('patient:care.cancel.done') })
  }

  async function onSaveChange(iso) {
    if (lock.current || !changing) return
    lock.current = true
    setBusy(true)
    setModalError(null)
    const { error } = await rescheduleAppointment(changing.id, iso)
    lock.current = false
    setBusy(false)
    appts.reload()
    if (error) {
      setModalError(friendlyError(t, error).text)
      return
    }
    setChanging(null)
    setNotice({ variant: 'success', text: t('patient:care.change.done') })
  }

  function openCancel(appt) {
    setModalError(null)
    setCancelling(appt)
  }
  function openChange(appt) {
    setModalError(null)
    setChanging(appt)
  }

  let list
  if (appts.error) {
    const { text, detail } = friendlyError(t, appts.error)
    list = (
      <div className="nl-care__problem-box" role="alert">
        <p>{text}</p>
        {detail && <p className="nl-care__muted">{t('errors:technical_detail', { detail })}</p>}
        <Button variant="secondary" onClick={appts.reload}>
          {t('errors:retry')}
        </Button>
      </div>
    )
  } else if (!appts.loaded) {
    list = (
      <p className="nl-care__muted" role="status">
        {t('ui.loading')}
      </p>
    )
  } else {
    list = (
      <>
        <h3 className="nl-care__subtitle">{t('patient:care.list.upcoming')}</h3>
        {upcoming.length === 0 ? (
          <p className="nl-care__empty" role="status">
            <InfoIcon size={20} />
            <span>{t('patient:care.list.emptyUpcoming')}</span>
          </p>
        ) : (
          <ul className="nl-care__list">
            {upcoming.map((a) => (
              <AppointmentItem
                key={a.id}
                appt={a}
                kind={statusKind(a, now)}
                upcoming
                language={language}
                onCancel={openCancel}
                onChange={openChange}
              />
            ))}
          </ul>
        )}

        <h3 className="nl-care__subtitle">{t('patient:care.list.past')}</h3>
        {past.length === 0 ? (
          <p className="nl-care__empty" role="status">
            <InfoIcon size={20} />
            <span>{t('patient:care.list.emptyPast')}</span>
          </p>
        ) : (
          <>
            <ul className="nl-care__list">
              {past.slice(0, pastShown).map((a) => (
                <AppointmentItem key={a.id} appt={a} kind={statusKind(a, now)} upcoming={false} language={language} />
              ))}
            </ul>
            {past.length > pastShown && (
              <div>
                <Button variant="secondary" onClick={() => setPastShown((n) => n + PAST_PAGE)}>
                  {t('patient:care.list.showMore')}
                </Button>
              </div>
            )}
          </>
        )}
        {(appts.data ?? []).length >= APPOINTMENTS_LIMIT && (
          <p className="nl-care__muted">{t('patient:care.list.truncated', { count: APPOINTMENTS_LIMIT })}</p>
        )}
      </>
    )
  }

  return (
    <>
      <PageHeader title={t('patient:tabs.care')} />
      <div className="nl-care">
        {notice && (
          <div className="nl-care__notice">
            <Toast variant={notice.variant} onDismiss={() => setNotice(null)}>
              {notice.text}
            </Toast>
          </div>
        )}

        <div className="nl-care__top">
          <p>{t('patient:care.intro')}</p>
          <p className="nl-care__muted">{t('patient:care.timeNote')}</p>
        </div>

        <div className="nl-care__grid">
          <div className="nl-care__main">
            <Card title={t('patient:care.request.title')}>
              <div className="nl-care__stack">
                {assigned === true && <p>{t('patient:care.request.reminder')}</p>}
                <RequestForm
                  enabled={assigned === true}
                  reason={assigned === false ? t('patient:care.request.disabled') : t('patient:care.request.disabledUnknown')}
                  sending={busy && !cancelling && !changing}
                  onSubmit={onRequest}
                />
                <p className="nl-care__strong">{t('patient:home.guidance.emergency')}</p>
              </div>
            </Card>

            <Card title={t('patient:care.list.title')}>
              <div className="nl-care__stack">{list}</div>
            </Card>
          </div>

          <aside className="nl-care__side">
            <ProviderCard provider={provider} name={providerName} />

            <Card title={t('patient:care.tele.title')} className="nl-care__side-card">
              <p className="nl-care__soon">
                <MessageIcon size={20} />
                <span>{t('patient:care.tele.badge')}</span>
              </p>
              <p>{t('patient:care.tele.body')}</p>
            </Card>

            <Card title={t('patient:care.history.title')} className="nl-care__side-card">
              <ul className="nl-care__list">
                <li className="nl-care__placeholder">
                  <FileTextIcon size={20} />
                  <span>{t('patient:care.history.empty')}</span>
                </li>
              </ul>
              <p className="nl-care__muted">{t('patient:care.history.body')}</p>
            </Card>
          </aside>
        </div>

        <p className="nl-disclaimer">{t('disclaimer')}</p>
      </div>

      <CancelModal
        key={`cancel-${cancelling?.id ?? 'none'}`}
        appt={cancelling}
        language={language}
        busy={busy}
        error={modalError}
        onClose={() => setCancelling(null)}
        onConfirm={onConfirmCancel}
      />
      <ChangeModal
        key={`change-${changing?.id ?? 'none'}`}
        appt={changing}
        language={language}
        busy={busy}
        error={modalError}
        onClose={() => setChanging(null)}
        onSave={onSaveChange}
      />
    </>
  )
}
