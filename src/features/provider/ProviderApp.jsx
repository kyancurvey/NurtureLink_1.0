import { lazy, Suspense } from 'react'
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
import PatientDetailPlaceholder from './PatientDetailPlaceholder.jsx'

// The Overview is loaded only when a provider opens it (route-level code splitting).
// The tiny patient placeholder is imported normally on purpose: it opens inside the
// Overview, and a lazy load there would hide the Overview behind the loading line.
const Overview = lazy(() => import('./Overview.jsx'))

// The provider dashboard: seven tabs in the sidebar on laptops. A phone tab bar
// has room for five, so Validation and Reports are laptop-only for now (open
// decision for Phase 4). Overview is built (step 4.1); the other tabs are placeholders
// that Phase 4 fills in. Navigation is unchanged in step 4.1.
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

function RouteLoading() {
  const t = useT()
  return (
    <p className="nl-empty__body" role="status">
      {t('ui.loading')}
    </p>
  )
}

export default function ProviderApp() {
  const t = useT()
  return (
    <AppShell tabs={TABS} phoneTabs={PHONE_TABS}>
      <Suspense fallback={<RouteLoading />}>
        <Routes>
          {/* One layout route: the Overview stays mounted while a patient placeholder opens beside it. */}
          <Route element={<Overview />}>
            <Route index element={null} />
            <Route path="patient/:patientId" element={<PatientDetailPlaceholder />} />
          </Route>
          <Route path="patients" element={<TabPlaceholder title={t('provider:tabs.patients')} />} />
          <Route path="alerts" element={<TabPlaceholder title={t('provider:tabs.alerts')} />} />
          <Route path="consults" element={<TabPlaceholder title={t('provider:tabs.consults')} />} />
          <Route path="validation" element={<TabPlaceholder title={t('provider:tabs.validation')} />} />
          <Route path="reports" element={<TabPlaceholder title={t('provider:tabs.reports')} />} />
          <Route path="settings" element={<TabPlaceholder title={t('provider:tabs.settings')} />} />
          <Route path="*" element={<Navigate to="/provider" replace />} />
        </Routes>
      </Suspense>
    </AppShell>
  )
}
