import { useId } from 'react'
import { AlertOctagonIcon } from './Icons.jsx'

// label is required. hint and error are optional, already-translated text.
// An error shows an icon plus text and is linked with aria-describedby.
export default function TextField({ label, hint, error, id, className = '', ...rest }) {
  const auto = useId()
  const fid = id || auto
  const hintId = `${fid}-hint`
  const errId = `${fid}-err`
  const described = [hint && hintId, error && errId].filter(Boolean).join(' ') || undefined
  return (
    <div className={`nl-field ${className}`.trim()}>
      <label htmlFor={fid} className="nl-field__label">
        {label}
      </label>
      {hint && (
        <p id={hintId} className="nl-field__hint">
          {hint}
        </p>
      )}
      <input
        id={fid}
        className="nl-field__input"
        aria-invalid={error ? true : undefined}
        aria-describedby={described}
        {...rest}
      />
      {error && (
        <p id={errId} className="nl-field__error">
          <AlertOctagonIcon />
          <span>{error}</span>
        </p>
      )}
    </div>
  )
}
