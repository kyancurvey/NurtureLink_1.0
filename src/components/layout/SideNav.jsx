import { NavLink } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import LogoTile from '../ui/LogoTile.jsx';

/** Super account, 1024 px and wider. Hidden by CSS below that width, where the bottom tabs show instead. */
export default function SideNav({ role, items }) {
  const { t } = useTranslation();
  return (
    <aside className="sidenav">
      <div className="sidenav__brand">
        <LogoTile size="sm" />
        <span className="sidenav__name">{t('app.name')}</span>
      </div>
      <nav aria-label={t('nav.label')}>
        <ul className="sidenav__list">
          {items.map(({ path, key, icon: Icon }) => (
            <li key={path}>
              <NavLink to={`/${role}/${path}`} className="sidenav__link">
                <Icon size={24} aria-hidden="true" />
                <span>{t(`nav.${key}`)}</span>
              </NavLink>
            </li>
          ))}
        </ul>
      </nav>
    </aside>
  );
}
