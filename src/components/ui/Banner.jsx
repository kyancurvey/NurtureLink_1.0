import { STATUS_ICONS } from './statusIcons.js';

/** status: normal | attention | alert | info | neutral. Alert banners are announced at once. */
export default function Banner({ status = 'info', title, action, children }) {
  const Icon = STATUS_ICONS[status];
  return (
    <div className={`banner banner--${status}`} role={status === 'alert' ? 'alert' : 'status'}>
      <Icon className="banner__icon" size={20} aria-hidden="true" />
      <div className="banner__body">
        {title ? <p className="banner__title">{title}</p> : null}
        {children ? <p>{children}</p> : null}
      </div>
      {action ? <div className="banner__action">{action}</div> : null}
    </div>
  );
}
