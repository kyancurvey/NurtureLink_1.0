import { lazy, Suspense } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { AppShell, TabPlaceholder } from '../../components/layout/index.js'
import { ActivityIcon, BellIcon, HeartIcon, HomeIcon, UserIcon } from '../../components/ui/index.js'
import { useT } from '../../lib/useT.js'

// Each patient screen is loaded only when it is opened (route-level code
// splitting), so the first download stays small. The shell and tab bar are not lazy.
const Home = lazy(() => import('./Home.jsx'))
const ProfilePage = lazy(() => import('./ProfilePage.jsx'))
const PrivacyPage = lazy(() => import('./PrivacyPage.jsx'))

// The patient app: five tabs (bottom bar on phones, sidebar on laptops).
// Home is built (step 3.1); the other tabs are placeholders until later steps.
const TABS = [
  { to: '/patient', labelKey: 'patient:tabs.home', icon: <HomeIcon />, end: true },
  { to: '/patient/monitor', labelKey: 'patient:tabs.monitor', icon: <ActivityIcon /> },
  { to: '/patient/alerts', labelKey: 'patient:tabs.alerts', icon: <BellIcon /> },
  { to: '/patient/care', labelKey: 'patient:tabs.care', icon: <HeartIcon /> },
  { to: '/patient/profile', labelKey: 'patient:tabs.profile', icon: <UserIcon /> },
]

function RouteLoading() {
  const t = useT()
  return (
    <p className="nl-empty__body" role="status">
      {t('ui.loading')}
    </p>
  )
}

export default function PatientApp() {
  const t = useT()
  return (
    <AppShell tabs={TABS}>
      <Suspense fallback={<RouteLoading />}>
        <Routes>
          <Route index element={<Home />} />
          <Route path="monitor" element={<TabPlaceholder title={t('patient:tabs.monitor')} />} />
          <Route path="alerts" element={<TabPlaceholder title={t('patient:tabs.alerts')} />} />
          <Route path="care" element={<TabPlaceholder title={t('patient:tabs.care')} />} />
          <Route path="profile" element={<ProfilePage />} />
          <Route path="profile/privacy" element={<PrivacyPage />} />
          <Route path="*" element={<Navigate to="/patient" replace />} />
        </Routes>
      </Suspense>
    </AppShell>
  )
}
