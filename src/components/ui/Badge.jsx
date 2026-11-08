import { STATUS_ICONS } from './statusIcons.js';

/** status: normal | attention | alert | info | neutral. The label text is required. */
export default function Badge({ status = 'neutral', children }) {
  const Icon = STATUS_ICONS[status];
  return (
    <span className={`badge badge--${status}`}>
      <Icon className="badge__icon" size={16} aria-hidden="true" />
      <span>{children}</span>
    </span>
  );
}
