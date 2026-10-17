import { NavLink } from 'react-router-dom'
import { useT } from '../../lib/useT.js'

// Phone navigation. tabs: [{ to, labelKey, icon, end? }]. Shown below 900px.
export default function BottomTabBar({ tabs }) {
  const t = useT()
  return (
    <nav className="nl-tabbar" aria-label={t('nav.main')}>
      <ul className="nl-tabbar__list">
        {tabs.map((tab) => (
          <li key={tab.to} className="nl-tabbar__item">
            <NavLink to={tab.to} end={tab.end} className="nl-tabbar__link">
              {tab.icon}
              <span>{t(tab.labelKey)}</span>
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  )
}
