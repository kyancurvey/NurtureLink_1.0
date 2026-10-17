import { useT } from '../../lib/useT.js'
import { CheckCircleIcon, AlertTriangleIcon, AlertOctagonIcon, InfoIcon, CloseIcon } from './Icons.jsx'

// variant: 'info' | 'success' | 'warning' | 'danger'. Icon plus text.
// No auto-dismiss: the parent decides (a setTimeout calling onDismiss).
const ICONS = {
  info: InfoIcon,
  success: CheckCircleIcon,
  warning: AlertTriangleIcon,
  danger: AlertOctagonIcon,
}

export default function Toast({ variant = 'info', onDismiss, children }) {
  const t = useT()
  const Icon = ICONS[variant]
  return (
    <div
      className={`nl-toast nl-toast--${variant}`}
      role={variant === 'danger' ? 'alert' : 'status'}
    >
      <Icon size={24} />
      <p className="nl-toast__text">{children}</p>
      {onDismiss && (
        <button
          type="button"
          className="nl-iconbtn"
          onClick={onDismiss}
          aria-label={t('ui.dismiss')}
        >
          <CloseIcon />
        </button>
      )}
    </div>
  )
}
