import { useT } from '../../lib/useT.js'
import { ChevronLeftIcon } from '../ui/Icons.jsx'

// Laptop (900px+): list left, detail right, both visible.
// Phone: one column. Shows the list until something is selected, then the
// detail with a Back button. The parent owns the selection.
export default function SplitView({ list, detail, emptyDetail, hasSelection, onBack }) {
  const t = useT()
  return (
    <div className="nl-split" data-has-selection={hasSelection ? 'true' : 'false'}>
      <div className="nl-split__list">{list}</div>
      <div className="nl-split__detail">
        {hasSelection ? (
          <>
            <button type="button" className="nl-split__back" onClick={onBack}>
              <ChevronLeftIcon />
              <span>{t('ui.back')}</span>
            </button>
            {detail}
          </>
        ) : (
          <div className="nl-split__empty">{emptyDetail}</div>
        )}
      </div>
    </div>
  )
}
