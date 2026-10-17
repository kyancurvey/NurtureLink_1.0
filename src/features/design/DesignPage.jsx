import { useState } from 'react'
import { useT } from '../../lib/useT.js'
import {
  Button, Card, StatusBadge, TextField, Checkbox, Toggle, Modal, Toast, PageHeader,
  HomeIcon, ActivityIcon, BellIcon, HeartIcon, UserIcon,
} from '../../components/ui/index.js'
import { AppShell, SplitView } from '../../components/layout/index.js'

// Visual check page at /#/design. Developer tool: remove or hide before release.
// Text is shown through i18n keys (placeholders until step 1.3). CSS variable
// names in the swatches are technical identifiers, not UI copy.
const TABS = [
  { to: '/design', end: true, labelKey: 'nav.home', icon: <HomeIcon /> },
  { to: '/design/monitor', labelKey: 'nav.monitor', icon: <ActivityIcon /> },
  { to: '/design/alerts', labelKey: 'nav.alerts', icon: <BellIcon /> },
  { to: '/design/care', labelKey: 'nav.care', icon: <HeartIcon /> },
  { to: '/design/profile', labelKey: 'nav.profile', icon: <UserIcon /> },
]

const SWATCHES = [
  ['--color-brand-coral', 'var(--color-brand-coral)'],
  ['--color-brand-violet', 'var(--color-brand-violet)'],
  ['--color-brand-purple', 'var(--color-brand-purple)'],
  ['--color-bg-tint', 'var(--color-bg-tint)'],
  ['--gradient-brand', 'var(--gradient-brand)'],
  ['--gradient-action', 'var(--gradient-action)'],
  ['--color-success', 'var(--color-success)'],
  ['--color-warning', 'var(--color-warning)'],
  ['--color-danger', 'var(--color-danger)'],
]

const ITEMS = [1, 2, 3, 4]

export default function DesignPage() {
  const t = useT()
  const [modalOpen, setModalOpen] = useState(false)
  const [toast, setToast] = useState(null)
  const [toggleOn, setToggleOn] = useState(true)
  const [checked, setChecked] = useState(false)
  const [selected, setSelected] = useState(null)

  return (
    <AppShell tabs={TABS}>
      <PageHeader
        title={t('design.title')}
        subtitle={t('design.subtitle')}
        actions={<Button variant="secondary">{t('design.header.action')}</Button>}
      />

      <div className="design-grid">
        <Card title={t('design.section.colors')}>
          <div className="design-swatches">
            {SWATCHES.map(([name, value]) => (
              <div key={name} className="design-swatch">
                <span className="design-swatch__chip" style={{ background: value }} />
                <code>{name}</code>
              </div>
            ))}
          </div>
        </Card>

        <Card title={t('design.section.buttons')}>
          <div className="design-row">
            <Button>{t('design.button.primary')}</Button>
            <Button variant="secondary">{t('design.button.secondary')}</Button>
            <Button variant="danger">{t('design.button.danger')}</Button>
            <Button disabled>{t('design.button.disabled')}</Button>
          </div>
          <div className="design-row">
            <Button full>{t('design.button.full')}</Button>
          </div>
        </Card>

        <Card title={t('design.section.status')}>
          <div className="design-row">
            <StatusBadge status="success" />
            <StatusBadge status="warning" />
            <StatusBadge status="danger" />
          </div>
        </Card>

        <Card title={t('design.section.form')}>
          <div className="design-stack">
            <TextField label={t('design.field.label')} hint={t('design.field.hint')} placeholder={t('design.field.placeholder')} />
            <TextField label={t('design.field.label')} defaultValue="x" error={t('design.field.error')} />
            <Checkbox label={t('design.checkbox.label')} checked={checked} onChange={(e) => setChecked(e.target.checked)} />
            <Toggle label={t('design.toggle.label')} checked={toggleOn} onChange={setToggleOn} />
          </div>
        </Card>

        <Card title={t('design.section.overlays')}>
          <div className="design-row">
            <Button onClick={() => setModalOpen(true)}>{t('design.modal.open')}</Button>
            {['info', 'success', 'warning', 'danger'].map((v) => (
              <Button key={v} variant="secondary" onClick={() => setToast(v)}>
                {t(`design.toast.${v}`)}
              </Button>
            ))}
          </div>
          {toast && (
            <div className="design-toast">
              <Toast variant={toast} onDismiss={() => setToast(null)}>
                {t('design.toast.message')}
              </Toast>
            </div>
          )}
        </Card>

        <Card title={t('design.section.split')}>
          <SplitView
            hasSelection={selected !== null}
            onBack={() => setSelected(null)}
            emptyDetail={<p>{t('design.split.empty')}</p>}
            list={
              <ul className="design-list">
                {ITEMS.map((n) => (
                  <li key={n}>
                    <button
                      type="button"
                      className="design-list__item"
                      aria-pressed={selected === n}
                      onClick={() => setSelected(n)}
                    >
                      <span>{t('design.split.item')} {n}</span>
                      <StatusBadge status={['success', 'warning', 'danger', 'success'][n - 1]} />
                    </button>
                  </li>
                ))}
              </ul>
            }
            detail={
              <Card title={`${t('design.split.detail')} ${selected}`}>
                <p>{t('design.split.body')}</p>
              </Card>
            }
          />
        </Card>
      </div>

      <Modal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        title={t('design.modal.title')}
        actions={
          <>
            <Button variant="secondary" onClick={() => setModalOpen(false)}>{t('design.modal.cancel')}</Button>
            <Button variant="danger" onClick={() => setModalOpen(false)}>{t('design.modal.confirm')}</Button>
          </>
        }
      >
        <p>{t('design.modal.body')}</p>
      </Modal>
    </AppShell>
  )
}
