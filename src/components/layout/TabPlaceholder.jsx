import { useT } from '../../lib/useT.js'
import PageHeader from '../ui/PageHeader.jsx'
import EmptyState from '../ui/EmptyState.jsx'

// A tab that is not built yet: its title, an empty-state message, and the
// required disclaimer (these tabs will become reading screens, so the line is
// there from the start). Extra children go under the message.
export default function TabPlaceholder({ title, children }) {
  const t = useT()
  return (
    <>
      <PageHeader title={title} />
      <EmptyState title={t('emptyState.title')} body={t('emptyState.body')}>
        {children}
      </EmptyState>
      <p className="nl-disclaimer">{t('disclaimer')}</p>
    </>
  )
}
