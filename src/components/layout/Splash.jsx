import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import LogoTile from '../ui/LogoTile.jsx';
import SoftArt from '../ui/SoftArt.jsx';

// AUTH-01: 5 seconds. Keep in step with --splash-duration in tokens.css.
const SPLASH_MS = 5000;

export default function Splash() {
  const { t } = useTranslation();
  const navigate = useNavigate();

  useEffect(() => {
    // Goes to sign-in; the saved-session check arrives with the guards in Prompt 3.
    const timer = window.setTimeout(() => navigate('/sign-in', { replace: true }), SPLASH_MS);
    return () => window.clearTimeout(timer);
  }, [navigate]);

  return (
    <main className="splash" aria-busy="true">
      <SoftArt name="belt" size="md" float className="splash__art splash__art--belt" />
      <SoftArt name="heart" size="md" float className="splash__art splash__art--heart" />
      <SoftArt name="band" size="md" float className="splash__art splash__art--band" />
      <div className="splash__center">
        <LogoTile size="lg" float />
        <h1 className="splash__name">{t('app.name')}</h1>
        <div className="splash__bar" aria-hidden="true">
          <div className="splash__fill" />
        </div>
        <span className="visually-hidden" role="status">
          {t('splash.loading')}
        </span>
      </div>
    </main>
  );
}
