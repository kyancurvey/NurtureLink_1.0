import { Navigate, Route, Routes } from 'react-router-dom'
import { AppShell, TabPlaceholder } from '../../components/layout/index.js'
import { ActivityIcon, BellIcon, HeartIcon, HomeIcon, UserIcon } from '../../components/ui/index.js'
import { useT } from '../../lib/useT.js'
import PrivacyPage from './PrivacyPage.jsx'
import ProfilePage from './ProfilePage.jsx'

// The patient app: five tabs (bottom bar on phones, sidebar on laptops).
// Every tab is a placeholder for now; Phase 3 fills them in.
const TABS = [
  { to: '/patient', labelKey: 'patient:tabs.home', icon: <HomeIcon />, end: true },
  { to: '/patient/monitor', labelKey: 'patient:tabs.monitor', icon: <ActivityIcon /> },
  { to: '/patient/alerts', labelKey: 'patient:tabs.alerts', icon: <BellIcon /> },
  { to: '/patient/care', labelKey: 'patient:tabs.care', icon: <HeartIcon /> },
  { to: '/patient/profile', labelKey: 'patient:tabs.profile', icon: <UserIcon /> },
]

export default function PatientApp() {
  const t = useT()
  return (
    <AppShell tabs={TABS}>
      <Routes>
        <Route index element={<TabPlaceholder title={t('patient:tabs.home')} />} />
        <Route path="monitor" element={<TabPlaceholder title={t('patient:tabs.monitor')} />} />
        <Route path="alerts" element={<TabPlaceholder title={t('patient:tabs.alerts')} />} />
        <Route path="care" element={<TabPlaceholder title={t('patient:tabs.care')} />} />
        <Route path="profile" element={<ProfilePage />} />
        <Route path="profile/privacy" element={<PrivacyPage />} />
        <Route path="*" element={<Navigate to="/patient" replace />} />
      </Routes>
    </AppShell>
  )
}
