import { useId, useState } from 'react'
import { Checkbox, ChevronLeftIcon, InfoIcon } from '../../components/ui/index.js'
import { useT } from '../../lib/useT.js'

// One document on the consent screen: its title, a Required/Optional tag, its
// text (opens and closes, plain text only), and its OWN checkbox. There is
// deliberately no "accept all" anywhere.
//   item:    { type, required, doc: { title, body, version, language }, fallback, updated }
//   checked, onChange, disabled: the checkbox state, owned by the screen.
export default function ConsentItem({ item, checked, onChange, disabled, shownLanguageName, wantedLanguageName }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  const textId = useId()
  const { doc } = item

  return (
    <li className="nl-consent__item">
      <div className="nl-consent__head">
        <h3 className="nl-consent__title">{doc.title}</h3>
        <div className="nl-consent__tags">
          <span className={`nl-consent__tag${item.required ? ' nl-consent__tag--required' : ''}`}>
            {item.required ? t('terms:item.required') : t('terms:item.optional')}
          </span>
          {item.updated && (
            <span className="nl-consent__tag">
              <InfoIcon size={16} />
              {t('terms:item.updated')}
            </span>
          )}
          <span className="nl-consent__version">{t('terms:item.version', { version: doc.version })}</span>
        </div>
      </div>

      {item.fallback && (
        <p className="nl-consent__note">
          {t('terms:item.fallback', { wanted: wantedLanguageName, shown: shownLanguageName })}
        </p>
      )}

      <button
        type="button"
        className="nl-consent__toggle"
        aria-expanded={open}
        aria-controls={textId}
        onClick={() => setOpen((v) => !v)}
      >
        <span className={open ? 'nl-consent__chev nl-consent__chev--open' : 'nl-consent__chev'}>
          <ChevronLeftIcon />
        </span>
        {open ? t('terms:item.hide') : t('terms:item.read')}
      </button>

      {/* Plain text only: React escapes it, and CSS keeps the line breaks. */}
      <div id={textId} className="nl-consent__text" hidden={!open} tabIndex={0} role="region" aria-label={doc.title}>
        {doc.body}
      </div>

      <Checkbox
        checked={checked}
        disabled={disabled}
        onChange={(e) => onChange(e.target.checked)}
        label={t('terms:item.agree', { title: doc.title })}
      />
    </li>
  )
}
