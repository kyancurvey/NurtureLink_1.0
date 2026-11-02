import { useEffect, useId, useState } from 'react'
import {
  AlertOctagonIcon,
  Button,
  Card,
  CheckCircleIcon,
  CloseIcon,
  InfoIcon,
  TextField,
} from '../../components/ui/index.js'
import { friendlyError } from '../../lib/errors.js'
import { dueDateProblem, gestationalAge, manilaToday } from '../../lib/gestation.js'
import { saveMyPregnancyDetails, usePregnancyDetails } from '../../lib/patientData.js'
import { useT } from '../../lib/useT.js'
import { CONDITIONS_MAX, CONDITION_MAX, HISTORY_MAX, checkCondition, checkHistory } from './profileRules.js'

// Profile > Pregnancy details (step 3.5). Due date, short history notes and a
// list of conditions. Weeks and trimester are WORKED OUT from the due date on
// this screen (src/lib/gestation.js) and never stored. Saving goes through the
// database function save_pregnancy_details (migration 013), which checks
// everything again. All limits are draft, pending medical officer.

function dueMessage(t, problem) {
  if (problem === 'past') return t('patient:profile.preg.duePast')
  if (problem === 'ahead') return t('patient:profile.preg.dueAhead')
  return t('patient:profile.preg.dueInvalid')
}

function historyMessage(t, error) {
  return error === 'long'
    ? t('patient:profile.preg.historyLong', { max: HISTORY_MAX })
    : t('patient:profile.preg.historyBad')
}

function conditionMessage(t, error) {
  switch (error) {
    case 'bad':
      return t('patient:profile.preg.condBad')
    case 'long':
      return t('patient:profile.preg.condLong', { len: CONDITION_MAX })
    case 'duplicate':
      return t('patient:profile.preg.condDuplicate')
    case 'full':
      return t('patient:profile.preg.condFull', { max: CONDITIONS_MAX })
    default:
      return t('patient:profile.preg.condEmpty')
  }
}

function weeksAndDays(t, age) {
  const weeks = t(age.weeks === 1 ? 'patient:profile.preg.ga.weeksOne' : 'patient:profile.preg.ga.weeksMany', { n: age.weeks })
  const days = t(age.days === 1 ? 'patient:profile.preg.ga.daysOne' : 'patient:profile.preg.ga.daysMany', { n: age.days })
  return t('patient:profile.preg.ga.join', { weeks, days })
}

function trimesterText(t, n) {
  if (n === 1) return t('patient:profile.preg.ga.trimester1')
  if (n === 2) return t('patient:profile.preg.ga.trimester2')
  return t('patient:profile.preg.ga.trimester3')
}

// Read-only. Worked out from the due date as it is in the form right now.
function AgeBlock({ due }) {
  const t = useT()
  const age = gestationalAge(due, manilaToday())
  let main = null
  let note = null
  if (age.state === 'unset') main = t('patient:profile.preg.ga.unset')
  else if (age.state === 'before_start') main = t('patient:profile.preg.ga.beforeStart')
  else if (age.state === 'over_42') main = t('patient:profile.preg.ga.over42')
  else {
    main = weeksAndDays(t, age)
    if (age.state === 'past_due') note = t('patient:profile.preg.ga.pastDue')
  }
  return (
    <div className="nl-profile__age" aria-live="polite">
      <h3 className="nl-profile__subtitle">{t('patient:profile.preg.ga.title')}</h3>
      <p className="nl-profile__big">{main}</p>
      {age.trimester && (
        <p>
          <strong>{t('patient:profile.preg.ga.trimesterLabel')}: </strong>
          {trimesterText(t, age.trimester)}
        </p>
      )}
      {note && (
        <p className="nl-profile__msg nl-profile__msg--info">
          <InfoIcon size={20} />
          <span>{note}</span>
        </p>
      )}
      <p className="nl-profile__muted">{t('patient:profile.preg.ga.explain')}</p>
    </div>
  )
}

function Conditions({ list, onChange }) {
  const t = useT()
  const [text, setText] = useState('')
  const [error, setError] = useState(null)

  function add() {
    const checked = checkCondition(text, list)
    if (checked.error) {
      setError(checked.error)
      return
    }
    onChange([...list, checked.value])
    setText('')
    setError(null)
  }

  return (
    <div className="nl-profile__form">
      <h3 className="nl-profile__subtitle">{t('patient:profile.preg.conditions')}</h3>
      <p className="nl-profile__muted">
        {t('patient:profile.preg.conditionsHint', { max: CONDITIONS_MAX, len: CONDITION_MAX })}
      </p>
      {list.length === 0 ? (
        <p className="nl-profile__muted">{t('patient:profile.preg.conditionsNone')}</p>
      ) : (
        <ul className="nl-profile__chips">
          {list.map((name, index) => (
            <li key={`${index}:${name}`} className="nl-profile__chip">
              <span>{name}</span>
              <button
                type="button"
                className="nl-profile__chip-remove"
                aria-label={`${t('patient:profile.preg.conditionRemove')}: ${name}`}
                onClick={() => onChange(list.filter((_, i) => i !== index))}
              >
                <CloseIcon size={20} />
              </button>
            </li>
          ))}
        </ul>
      )}
      <div className="nl-profile__add-row">
        <TextField
          label={t('patient:profile.preg.conditionInput')}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault()
              add()
            }
          }}
          autoComplete="off"
          error={error ? conditionMessage(t, error) : undefined}
        />
        <Button variant="secondary" onClick={add}>
          {t('patient:profile.preg.conditionAdd')}
        </Button>
      </div>
    </div>
  )
}

export default function PregnancyDetails() {
  const t = useT()
  const q = usePregnancyDetails()
  const [form, setForm] = useState(null) // null until the saved details have arrived
  const [errors, setErrors] = useState({})
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState(null) // { kind: 'ok' | 'error', text, detail? }
  const histId = useId()

  // Fill the form once, from what is saved (or empty when there is no row yet).
  useEffect(() => {
    if (form || !q.loaded || q.error) return
    setForm({
      due: q.data?.due_date ?? '',
      history: q.data?.obstetric_history ?? '',
      conditions: Array.isArray(q.data?.conditions) ? q.data.conditions : [],
    })
  }, [form, q.loaded, q.error, q.data])

  async function submit(e) {
    e.preventDefault()
    setNotice(null)
    const found = {}
    // Only a CHANGED due date has to be inside the allowed window (same rule as the database).
    if (form.due && form.due !== (q.data?.due_date ?? '')) {
      const problem = dueDateProblem(form.due, manilaToday())
      if (problem) found.due = problem
    }
    const history = checkHistory(form.history)
    if (history.error) found.history = history.error
    setErrors(found)
    if (found.due || found.history) return

    setBusy(true)
    const out = await saveMyPregnancyDetails({
      dueDate: form.due,
      history: history.value,
      conditions: form.conditions,
    })
    setBusy(false)
    if (out.error) {
      const shown = friendlyError(t, out.error)
      setNotice({ kind: 'error', text: shown.text, detail: shown.detail })
      return
    }
    setForm((f) => ({ ...f, history: history.value ?? '' }))
    setNotice({ kind: 'ok', text: t('patient:profile.preg.saved') })
    q.reload()
  }

  let body
  if (q.error && !form) {
    body = (
      <div className="nl-profile__form">
        <p className="nl-profile__msg nl-profile__msg--error" role="alert">
          <AlertOctagonIcon size={20} />
          <span>{t('patient:profile.preg.loadFailed')}</span>
        </p>
        <div className="nl-profile__actions">
          <Button variant="secondary" onClick={q.reload}>
            {t('errors:retry')}
          </Button>
        </div>
      </div>
    )
  } else if (!form) {
    body = (
      <p className="nl-profile__muted" role="status">
        {t('ui.loading')}
      </p>
    )
  } else {
    body = (
      <form noValidate onSubmit={submit} className="nl-profile__form">
        <p className="nl-profile__muted">{t('patient:profile.preg.intro')}</p>
        <TextField
          label={t('patient:profile.preg.dueDate')}
          hint={t('patient:profile.preg.dueDateHint')}
          type="date"
          value={form.due}
          onChange={(e) => setForm((f) => ({ ...f, due: e.target.value }))}
          error={errors.due ? dueMessage(t, errors.due) : undefined}
        />
        <AgeBlock due={form.due} />
        <div className="nl-field">
          <label htmlFor={histId} className="nl-field__label">
            {t('patient:profile.preg.history')}
          </label>
          <p id={`${histId}-hint`} className="nl-field__hint">
            {t('patient:profile.preg.historyHint', { max: HISTORY_MAX })}
          </p>
          <textarea
            id={histId}
            className="nl-field__input nl-profile__textarea"
            rows={4}
            value={form.history}
            onChange={(e) => setForm((f) => ({ ...f, history: e.target.value }))}
            aria-invalid={errors.history ? true : undefined}
            aria-describedby={`${histId}-hint`}
          />
          <p className="nl-profile__muted">
            {t('patient:profile.preg.historyCount', { count: Array.from(form.history).length, max: HISTORY_MAX })}
          </p>
          {errors.history && (
            <p className="nl-field__error">
              <AlertOctagonIcon />
              <span>{historyMessage(t, errors.history)}</span>
            </p>
          )}
        </div>
        <Conditions list={form.conditions} onChange={(conditions) => setForm((f) => ({ ...f, conditions }))} />
        <div className="nl-profile__actions">
          <Button type="submit" disabled={busy}>
            {busy ? t('patient:profile.preg.saving') : t('patient:profile.preg.save')}
          </Button>
        </div>
        {notice && (
          <div
            className={`nl-profile__msg nl-profile__msg--${notice.kind}`}
            role={notice.kind === 'error' ? 'alert' : 'status'}
          >
            {notice.kind === 'error' ? <AlertOctagonIcon size={20} /> : <CheckCircleIcon size={20} />}
            <span>
              {notice.text}
              {notice.detail && <> {t('errors:technical_detail', { detail: notice.detail })}</>}
            </span>
          </div>
        )}
      </form>
    )
  }

  return <Card title={t('patient:profile.preg.title')}>{body}</Card>
}
