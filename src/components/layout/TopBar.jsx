import { useEffect, useState } from 'react';
import { Bell } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import Logo from '../ui/Logo.jsx';
import { formatManilaNow } from '../../lib/time.js';
import { setLanguage } from '../../i18n/index.js';

const MAX_COUNT_SHOWN = 99;

/** COM-01: language toggle, live date and time (Asia/Manila) and the notification bell with its unread count. */
export default function TopBar({ unreadCount = 0 }) {
  const { t, i18n } = useTranslation();
  const lang = i18n.language === 'fil' ? 'fil' : 'en';
  const [stamp, setStamp] = useState(() => formatManilaNow(new Date(), lang).label);

  useEffect(() => {
    const update = () => setStamp(formatManilaNow(new Date(), lang).label);
    update();
    const timer = window.setInterval(update, 1000);
    return () => window.clearInterval(timer);
  }, [lang]);

  const bellLabel =
    unreadCount > 0 ? t('topbar.notificationsUnread', { count: unreadCount }) : t('topbar.notifications');

  return (
    <header className="topbar">
      <div className="topbar__row">
        <div className="topbar__brand">
          <Logo size="sm" />
          <span className="topbar__name">{t('app.name')}</span>
        </div>
        <div className="lang" role="group" aria-label={t('language.label')}>
          {['en', 'fil'].map((code) => (
            <button
              key={code}
              type="button"
              className="lang__btn"
              lang={code}
              aria-pressed={lang === code}
              aria-label={t(`language.${code}`)}
              onClick={() => setLanguage(code)}
            >
              {t(`language.${code}Short`)}
            </button>
          ))}
        </div>
        {/* TEMP: the bell opens the notification center in Prompt 5; the count stays at 0 until then. */}
        <button type="button" className="bell" aria-label={bellLabel}>
          <Bell size={24} aria-hidden="true" />
          {unreadCount > 0 ? (
            <span className="bell__count" aria-hidden="true">
              {unreadCount > MAX_COUNT_SHOWN ? `${MAX_COUNT_SHOWN}+` : unreadCount}
            </span>
          ) : null}
        </button>
        <span className="topbar__time">{stamp}</span>
      </div>
    </header>
  );
}
