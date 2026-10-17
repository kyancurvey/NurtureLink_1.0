import { NavLink } from 'react-router-dom'
import { useT } from '../../lib/useT.js'

// Laptop navigation. Same tabs prop as BottomTabBar. Shown from 900px up.
// `footer` is an optional slot (for example a language switch or logout).
export default function Sidebar({ tabs, footer }) {
  const t = useT()
  return (
    <aside className="nl-sidebar">
      <div className="nl-sidebar__brand">
        <img
          className="nl-sidebar__logo"
          src={`${import.meta.env.BASE_URL}logo.png`}
          alt=""
          width="40"
          height="40"
        />
        <span className="nl-sidebar__name">{t('brand.name')}</span>
      </div>
      <nav aria-label={t('nav.main')}>
        <ul className="nl-sidebar__list">
          {tabs.map((tab) => (
            <li key={tab.to}>
              <NavLink to={tab.to} end={tab.end} className="nl-sidebar__link">
                {tab.icon}
                <span>{t(tab.labelKey)}</span>
              </NavLink>
            </li>
          ))}
        </ul>
      </nav>
      {footer && <div className="nl-sidebar__footer">{footer}</div>}
    </aside>
  )
}
