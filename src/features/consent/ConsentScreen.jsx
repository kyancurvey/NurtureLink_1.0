import { useEffect, useRef, useState } from 'react'
import { Button, Card, Toast } from '../../components/ui/index.js'
import FormError from '../auth/FormError.jsx'
import { useAuth } from '../../lib/auth.jsx'
import { useConsent } from '../../lib/consent.jsx'
import { friendlyError } from '../../lib/errors.js'
import { useT } from '../../lib/useT.js'
import ConsentItem from './ConsentItem.jsx'
import DeletionRequest from './DeletionRequest.jsx'
import './consent.css'

// The one consent screen. Shows only what the person still has to accept (all
// of it on first login, only the new versions later). Every item has its own
// text and its own checkbox; nothing is ticked for them, and there is no
// "accept all". The optional study item starts unticked and is never required.
//
// The text is in the person's current language (the EN | FIL switch stays in the
// header). If they switch language, the ticks are cleared: what is saved must
// be the text they were looking at when they ticked.
export default function ConsentScreen() {
  const t = useT()
  const { profile } = useAuth()
  const { status, language, accept } = useConsent()
  const [checked, setChecked] = useState({})
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [langNote, setLangNote] = useState(false)

  const checkedRef = useRef(checked)
  checkedRef.current = checked
  const lastLanguage = useRef(language)
  useEffect(() => {
    if (lastLanguage.current === language) return
    lastLanguage.current = language
    setLangNote(Object.values(checkedRef.current).some(Boolean))
    setChecked({})
  }, [language])

  const items = status?.items ?? []
  const required = items.filter((i) => i.required)
  const optional = items.filter((i) => !i.required)
  const left = required.filter((i) => !checked[i.type]).length
  const anyUpdated = items.some((i) => i.updated)
  const name = (code) => t(`language.name.${code}`)

  async function submit() {
    if (left > 0 || busy) return
    setBusy(true)
    setError(null)
    const ids = items.filter((i) => checked[i.type]).map((i) => i.doc.id)
    const { error: e } = await accept(ids)
    setBusy(false)
    if (e) setError(friendlyError(t, e))
    // On success the gate sees the new records and lets the person in.
  }

  const renderItem = (item) => (
    <ConsentItem
      key={item.type}
      item={item}
      checked={!!checked[item.type]}
      disabled={busy}
      onChange={(v) => setChecked((c) => ({ ...c, [item.type]: v }))}
      wantedLanguageName={name(language)}
      shownLanguageName={name(item.doc.language)}
    />
  )

  return (
    <main className="nl-consent">
      <div className="nl-consent__panel">
        <h1 className="nl-consent__h1">{t('terms:gate.title')}</h1>
        <p>{t('terms:gate.intro')}</p>
        <p className="nl-consent__note">{t('terms:gate.languageHint')}</p>
        {anyUpdated && <Toast variant="info">{t('terms:gate.updated')}</Toast>}
        {langNote && <Toast variant="warning" onDismiss={() => setLangNote(false)}>{t('terms:gate.languageChanged')}</Toast>}

        {required.length > 0 && (
          <section aria-labelledby="nl-consent-required">
            <h2 id="nl-consent-required" className="nl-consent__subtitle">{t('terms:gate.requiredHeading')}</h2>
            <ul className="nl-consent__list">{required.map(renderItem)}</ul>
          </section>
        )}

        {optional.length > 0 && (
          <section aria-labelledby="nl-consent-optional">
            <h2 id="nl-consent-optional" className="nl-consent__subtitle">{t('terms:gate.optionalHeading')}</h2>
            <p className="nl-consent__note">{t('terms:gate.optionalHint')}</p>
            <ul className="nl-consent__list">{optional.map(renderItem)}</ul>
          </section>
        )}

        <FormError error={error} />
        <div className="nl-consent__submit">
          {left > 0 && (
            <p id="nl-consent-left" className="nl-consent__note">{t('terms:gate.remaining', { n: left })}</p>
          )}
          <Button full onClick={submit} disabled={left > 0 || busy} aria-describedby={left > 0 ? 'nl-consent-left' : undefined}>
            {busy ? t('terms:saving') : t('terms:gate.continue')}
          </Button>
        </div>

        {profile?.role === 'patient' && (
          <Card title={t('terms:exit.title')}>
            <p>{t('terms:exit.body')}</p>
            <DeletionRequest />
          </Card>
        )}

        <p className="nl-disclaimer">{t('disclaimer')}</p>
      </div>
    </main>
  )
}
