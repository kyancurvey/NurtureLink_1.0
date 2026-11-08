import { useTranslation } from 'react-i18next';
import Card from '../ui/Card.jsx';
import EmptyState from '../ui/EmptyState.jsx';
import HeleAvatar from '../ui/HeleAvatar.jsx';

// TEMP: a short screen inside the real page layout. Each later prompt replaces it with the real screen.
export default function TempPage({ titleKey, art = 'heart' }) {
  const { t } = useTranslation();
  return (
    <section className="page">
      <h1 className="page__title">{t(titleKey)}</h1>
      <Card>
        <EmptyState
          illustration={art}
          art={art === 'hele' ? <HeleAvatar size="lg" /> : undefined}
          title={t('empty.title')}
        >
          {t('empty.body')}
        </EmptyState>
      </Card>
    </section>
  );
}
