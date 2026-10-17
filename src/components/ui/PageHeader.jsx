// Page title bar. The gradient strip is decorative; the title sits on
// lavender so it keeps full contrast.
export default function PageHeader({ title, subtitle, actions }) {
  return (
    <header className="nl-pageheader">
      <div className="nl-pageheader__bar" aria-hidden="true" />
      <div className="nl-pageheader__row">
        <div className="nl-pageheader__text">
          <h1 className="nl-pageheader__title">{title}</h1>
          {subtitle && <p className="nl-pageheader__subtitle">{subtitle}</p>}
        </div>
        {actions && <div className="nl-pageheader__actions">{actions}</div>}
      </div>
    </header>
  )
}
