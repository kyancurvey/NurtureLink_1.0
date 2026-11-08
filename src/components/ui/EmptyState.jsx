import SoftArt from './SoftArt.jsx';

/** Calm empty state: illustration (or any node via `art`), title, optional body and action. */
export default function EmptyState({ illustration = 'heart', art, title, children, action }) {
  return (
    <div className="empty">
      {art ?? <SoftArt name={illustration} size="lg" float />}
      <h2 className="empty__title">{title}</h2>
      {children ? <p className="empty__body">{children}</p> : null}
      {action ? <div className="empty__action">{action}</div> : null}
    </div>
  );
}
