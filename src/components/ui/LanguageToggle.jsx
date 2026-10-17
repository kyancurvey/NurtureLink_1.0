import { useTranslation } from 'react-i18next'
import { LANGUAGES, setLanguage } from '../../lib/i18n.js'
import { CheckIcon } from './Icons.jsx'

// EN | FIL switch. The chosen language is shown by a filled background, a
// check icon AND aria-pressed, never by color alone. Each button is at least
// 44px. The visible text is a short code; the full name is the accessible name.
export default function LanguageToggle() {
  const { t, i18n } = useTranslation()
  const current = i18n.resolvedLanguage
  return (
    <div className="nl-lang" role="group" aria-label={t('language.label')}>
      {LANGUAGES.map((code) => {
        const active = current === code
        return (
          <button
            key={code}
            type="button"
            lang={code}
            className="nl-lang__btn"
            aria-pressed={active}
            aria-label={t(`language.name.${code}`, { lng: code })}
            onClick={() => setLanguage(code)}
          >
            {active && <CheckIcon size={16} />}
            <span aria-hidden="true">{t(`language.short.${code}`, { lng: code })}</span>
          </button>
        )
      })}
    </div>
  )
}
