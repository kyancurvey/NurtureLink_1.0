import { useT } from '../../lib/useT.js'
import { CheckCircleIcon, AlertTriangleIcon, AlertOctagonIcon } from './Icons.jsx'

// status: 'success' (green) | 'warning' (amber) | 'danger' (red).
// Always renders an icon (different shape per status) AND text.
// With no children it shows the default text for that status.
const ICONS = {
  success: CheckCircleIcon,
  warning: AlertTriangleIcon,
  danger: AlertOctagonIcon,
}

export default function StatusBadge({ status = 'success', children }) {
  const t = useT()
  const Icon = ICONS[status]
  return (
    <span className={`nl-badge nl-badge--${status}`}>
      <Icon />
      <span>{children ?? t(`status.${status}`)}</span>
    </span>
  )
}
