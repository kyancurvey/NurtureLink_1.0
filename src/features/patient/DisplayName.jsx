import { useState } from 'react'
import { Button, Card, CheckCircleIcon, TextField } from '../../components/ui/index.js'
import { useAuth } from '../../lib/auth.jsx'
import { friendlyError } from '../../lib/errors.js'
import { setMyDisplayName } from '../../lib/patientData.js'
import { useT } from '../../lib/useT.js'
import { NAME_MAX, checkName } from './profileRules.js'

// Profile > Display name. Optional. The name is typed by the person, never
// verified, and is always shown as plain text. Saving and removing both go
// through the database function set_my_display_name (migration 013); a blank
// name removes it.
export default function DisplayName() {
  const t = useT()
  const { profile, refreshProfile } = useAuth()
  const current = profile?.display_name ?? null
  const [value, setValue] = useState(current ?? '')
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState(null)
  const [done, setDone] = useState(null)

  async function save(raw) {
    setDone(null)
    setProblem(null)
    const checked = checkName(raw)
    if (checked.error === 'bad') {
      setProblem(t('patient:profile.name.bad'))
      return
    }
    if (checked.error === 'long') {
      setProblem(t('patient:profile.name.long', { max: NAME_MAX }))
      return
    }
    setBusy(true)
    const out = await setMyDisplayName(checked.value)
    if (out.error) {
      setBusy(false)
      setProblem(friendlyError(t, out.error).text)
      return
    }
    await refreshProfile()
    setBusy(false)
    setValue(out.name ?? '')
    setDone(out.name ? t('patient:profile.name.saved') : t('patient:profile.name.removed'))
  }

  function onSubmit(e) {
    e.preventDefault()
    save(value)
  }

  return (
    <Card title={t('patient:profile.name.title')}>
      <form noValidate onSubmit={onSubmit} className="nl-profile__form">
        <p className="nl-profile__muted">{t('patient:profile.name.intro')}</p>
        <p>
          {current ? (
            <>
              {t('patient:profile.name.currentLabel')}: <strong>{current}</strong>
            </>
          ) : (
            t('patient:profile.name.none')
          )}
        </p>
        <TextField
          label={t('patient:profile.name.label')}
          hint={t('patient:profile.name.hint', { max: NAME_MAX })}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          autoComplete="off"
          error={problem ?? undefined}
        />
        <div className="nl-profile__actions">
          <Button type="submit" disabled={busy}>
            {busy ? t('patient:profile.name.saving') : t('patient:profile.name.save')}
          </Button>
          {current && (
            <Button variant="secondary" disabled={busy} onClick={() => save('')}>
              {t('patient:profile.name.remove')}
            </Button>
          )}
        </div>
        {done && (
          <p className="nl-profile__msg nl-profile__msg--ok" role="status">
            <CheckCircleIcon size={20} />
            <span>{done}</span>
          </p>
        )}
      </form>
    </Card>
  )
}
