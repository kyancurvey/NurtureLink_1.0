import { HashRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AppHeader } from './components/layout/index.js'
import { AuthProvider } from './lib/auth.jsx'
import { AuthNotice, HomeRedirect, PublicOnly, RequireRole } from './features/auth/guards.jsx'
import LoginPage from './features/auth/LoginPage.jsx'
import SignUpPage from './features/auth/SignUpPage.jsx'
import ForgotPasswordPage from './features/auth/ForgotPasswordPage.jsx'
import ResetPasswordPage from './features/auth/ResetPasswordPage.jsx'
import InvitePage from './features/auth/InvitePage.jsx'
import AdminNoticePage from './features/auth/AdminNoticePage.jsx'
import PatientApp from './features/patient/PatientApp.jsx'
import ProviderApp from './features/provider/ProviderApp.jsx'
import DesignPage from './features/design/DesignPage.jsx'

// HashRouter keeps deep links working on GitHub Pages, which has no
// server-side routing. AuthProvider sits inside it so every screen can ask who
// is signed in. AppHeader sits above the routes so the language switch (and
// Log out) is on every screen. The wrapper div is what lets the sticky header
// stay put for the whole page (#root is only one screen tall).
//
// The route guards (RequireRole, PublicOnly) only choose which screen to show.
// They are for usability, not security: RLS plus grants in the database are the
// real protection (see guards.jsx).
export default function App() {
  return (
    <HashRouter>
      <AuthProvider>
        <div>
          <AppHeader />
          <AuthNotice />
          <Routes>
            <Route path="/" element={<HomeRedirect />} />
            <Route path="/login" element={<PublicOnly><LoginPage /></PublicOnly>} />
            <Route path="/signup" element={<PublicOnly><SignUpPage /></PublicOnly>} />
            <Route path="/forgot-password" element={<PublicOnly><ForgotPasswordPage /></PublicOnly>} />
            <Route path="/reset-password" element={<ResetPasswordPage />} />
            <Route path="/invite" element={<InvitePage />} />
            <Route path="/patient/*" element={<RequireRole role="patient"><PatientApp /></RequireRole>} />
            <Route path="/provider/*" element={<RequireRole role="provider"><ProviderApp /></RequireRole>} />
            <Route path="/admin" element={<RequireRole role="admin"><AdminNoticePage /></RequireRole>} />
            <Route path="/design/*" element={<DesignPage />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </div>
      </AuthProvider>
    </HashRouter>
  )
}
