import { useTranslation } from 'react-i18next';
import Button from '../ui/Button.jsx';
import Card from '../ui/Card.jsx';
import Field from '../ui/Field.jsx';
import LogoTile from '../ui/LogoTile.jsx';

// TEMP: replaced by the real sign-in in Prompt 3 (no sign-in logic in Prompt 1).
export default function TempSignIn() {
  const { t } = useTranslation();
  return (
    <main className="auth">
      <div className="auth__intro">
        <LogoTile size="md" float />
        <h1>{t('signIn.title')}</h1>
        <p>{t('signIn.welcome')}</p>
      </div>
      <Card className="auth__card">
        <Field label={t('signIn.identifier')} type="text" autoComplete="username" />
        <Field label={t('signIn.password')} type="password" autoComplete="current-password" />
        <Button block disabled>
          {t('signIn.submit')}
        </Button>
      </Card>
    </main>
  );
}
