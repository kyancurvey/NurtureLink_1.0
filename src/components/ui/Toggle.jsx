import { useId } from 'react'
import { useT } from '../../lib/useT.js'
import { CheckIcon } from './Icons.jsx'

// Controlled switch. State is shown by knob position, a check icon, AND the
// On/Off text, never by color alone.
export default function Toggle({ label, checked, onChange, ...rest }) {
  const t = useT()
  const labelId = useId()
  return (
    <div className="nl-toggle">
      <span id={labelId} className="nl-toggle__label">
        {label}
      </span>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-labelledby={labelId}
        className="nl-toggle__btn"
        onClick={() => onChange(!checked)}
        {...rest}
      >
        <span className="nl-toggle__track" data-on={checked ? 'true' : 'false'}>
          <span className="nl-toggle__knob">{checked && <CheckIcon size={16} />}</span>
        </span>
        <span className="nl-toggle__state">{checked ? t('ui.on') : t('ui.off')}</span>
      </button>
    </div>
  )
}
