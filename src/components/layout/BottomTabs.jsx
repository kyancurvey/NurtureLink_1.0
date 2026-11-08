import { NavLink } from 'react-router-dom';
import { useTranslation } from 'react-i18next';

export default function BottomTabs({ role, items }) {
  const { t } = useTranslation();
  return (
    <nav className="tabbar" aria-label={t('nav.label')}>
      {items.map(({ path, key, icon: Icon }) => (
        <NavLink key={path} to={`/${role}/${path}`} className="tabbar__item">
          <span className="tabbar__icon">
            <Icon size={24} aria-hidden="true" />
          </span>
          <span>{t(`nav.${key}`)}</span>
        </NavLink>
      ))}
    </nav>
  );
}
