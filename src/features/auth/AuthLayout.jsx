import { useT } from '../../lib/useT.js'

// Shared frame for the sign-in screens: logo, title, the form (children), a
// row of links (footer), and the required disclaimer line.
export default function AuthLayout({ title, subtitle, footer, children }) {
  const t = useT()
  return (
    <main className="nl-auth">
      <div className="nl-auth__panel">
        <img
          className="nl-auth__logo"
          src={`${import.meta.env.BASE_URL}logo.png`}
          alt=""
          width="72"
          height="72"
        />
        <h1 className="nl-auth__title">{title}</h1>
        {subtitle && <p className="nl-auth__subtitle">{subtitle}</p>}
        <div className="nl-auth__body">{children}</div>
        {footer && <div className="nl-auth__links">{footer}</div>}
        <p className="nl-disclaimer">{t('disclaimer')}</p>
      </div>
    </main>
  )
}
