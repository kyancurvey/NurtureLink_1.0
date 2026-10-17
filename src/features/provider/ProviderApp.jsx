import { Navigate, Route, Routes } from 'react-router-dom'
import { AppShell, TabPlaceholder } from '../../components/layout/index.js'
import {
  BellIcon,
  CheckCircleIcon,
  FileTextIcon,
  HomeIcon,
  MessageIcon,
  SettingsIcon,
  UsersIcon,
} from '../../components/ui/index.js'
import { useT } from '../../lib/useT.js'

// The provider dashboard: seven tabs in the sidebar on laptops. A phone tab bar
// has room for five, so Validation and Reports are laptop-only for now (open
// decision for Phase 4). Every tab is a placeholder; Phase 4 fills them in.
const OVERVIEW = { to: '/provider', labelKey: 'provider:tabs.overview', icon: <HomeIcon />, end: true }
const PATIENTS = { to: '/provider/patients', labelKey: 'provider:tabs.patients', icon: <UsersIcon /> }
const ALERTS = { to: '/provider/alerts', labelKey: 'provider:tabs.alerts', icon: <BellIcon /> }
const CONSULTS = { to: '/provider/consults', labelKey: 'provider:tabs.consults', icon: <MessageIcon /> }
const VALIDATION = {
  to: '/provider/validation',
  labelKey: 'provider:tabs.validation',
  icon: <CheckCircleIcon size={24} />,
}
const REPORTS = { to: '/provider/reports', labelKey: 'provider:tabs.reports', icon: <FileTextIcon /> }
const SETTINGS = { to: '/provider/settings', labelKey: 'provider:tabs.settings', icon: <SettingsIcon /> }

const TABS = [OVERVIEW, PATIENTS, ALERTS, CONSULTS, VALIDATION, REPORTS, SETTINGS]
const PHONE_TABS = [OVERVIEW, PATIENTS, ALERTS, CONSULTS, SETTINGS]

export default function ProviderApp() {
  const t = useT()
  return (
    <AppShell tabs={TABS} phoneTabs={PHONE_TABS}>
      <Routes>
        <Route index element={<TabPlaceholder title={t('provider:tabs.overview')} />} />
        <Route path="patients" element={<TabPlaceholder title={t('provider:tabs.patients')} />} />
        <Route path="alerts" element={<TabPlaceholder title={t('provider:tabs.alerts')} />} />
        <Route path="consults" element={<TabPlaceholder title={t('provider:tabs.consults')} />} />
        <Route path="validation" element={<TabPlaceholder title={t('provider:tabs.validation')} />} />
        <Route path="reports" element={<TabPlaceholder title={t('provider:tabs.reports')} />} />
        <Route path="settings" element={<TabPlaceholder title={t('provider:tabs.settings')} />} />
        <Route path="*" element={<Navigate to="/provider" replace />} />
      </Routes>
    </AppShell>
  )
}
