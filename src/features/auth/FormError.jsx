import { Toast } from '../../components/ui/index.js'
import { useT } from '../../lib/useT.js'

// Shows the result of friendlyError(): calm text, plus (for permission
// problems only) the technical detail so a grant mistake is easy to spot.
export default function FormError({ error, onDismiss }) {
  const t = useT()
  if (!error) return null
  return (
    <Toast variant="danger" onDismiss={onDismiss}>
      {error.text}
      {error.detail && (
        <>
          <br />
          <small>{t('errors:technical_detail', { detail: error.detail })}</small>
        </>
      )}
    </Toast>
  )
}
