import { useEffect, useId, useRef } from 'react'
import { useT } from '../../lib/useT.js'
import { CloseIcon } from './Icons.jsx'

// Uses the native <dialog>: focus is trapped, Esc closes, background is inert.
// Controlled: parent owns `open` and handles onClose.
export default function Modal({ open, onClose, title, children, actions }) {
  const t = useT()
  const ref = useRef(null)
  const titleId = useId()

  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (open && !d.open) d.showModal()
    if (!open && d.open) d.close()
  }, [open])

  return (
    <dialog
      ref={ref}
      className="nl-modal"
      aria-labelledby={titleId}
      onClose={onClose}
      onClick={(e) => {
        if (e.target === ref.current) onClose() // click on the backdrop
      }}
    >
      <div className="nl-modal__panel">
        <div className="nl-modal__head">
          <h2 id={titleId} className="nl-modal__title">
            {title}
          </h2>
          <button
            type="button"
            className="nl-iconbtn"
            onClick={onClose}
            aria-label={t('ui.close')}
          >
            <CloseIcon />
          </button>
        </div>
        <div className="nl-modal__body">{children}</div>
        {actions && <div className="nl-modal__actions">{actions}</div>}
      </div>
    </dialog>
  )
}
