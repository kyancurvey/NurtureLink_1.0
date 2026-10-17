import { Navigate, useLocation } from 'react-router-dom'
import Splash from '../../components/Splash.jsx'
import { Button } from '../../components/ui/index.js'
import { useAuth } from '../../lib/auth.jsx'
import { friendlyError } from '../../lib/errors.js'
import { useT } from '../../lib/useT.js'
import AuthLayout from './AuthLayout.jsx'
import FormError from './FormError.jsx'

// ---------------------------------------------------------------------------
// ROUTE GUARDS: FOR USABILITY ONLY.
//
// These components only decide which SCREEN to show. They are NOT security.
// GitHub Pages serves the same files to everyone, and anyone can open the
// browser tools and skip these checks. The real protection is in the database:
// row-level security (RLS) policies plus minimal grants (migrations 004 and
// 005). A patient who got past every guard here would still read nothing that
// belongs to a provider. Never put a secret or a rule in this file.
// ---------------------------------------------------------------------------

export function roleHome(role) {
  if (role === 'patient') return '/patient'
  if (role === 'provider') return '/provider'
  if (role === 'admin') return '/admin'
  return '/login'
}

// Shown when the profile could not be read (missing row, or a permission
// problem). Never a blank screen, and never raw errors except the permission
// detail, which the project owner needs.
function ProfileProblem() {
  const t = useT()
  const { profileError, refreshProfile } = useAuth()
  return (
    <AuthLayout title={t('errors:profile_title')}>
      <FormError error={friendlyError(t, profileError)} />
      <Button variant="secondary" full onClick={refreshProfile}>
        {t('errors:retry')}
      </Button>
    </AuthLayout>
  )
}

// Signed-in people only, and only the given role. Anyone else is sent away:
// signed out -> log in; wrong role -> their own home.
export function RequireRole({ role, children }) {
  const { loading, session, profile, profileError, recovery } = useAuth()
  if (loading) return <Splash />
  if (recovery) return <Navigate to="/reset-password" replace />
  if (!session) return <Navigate to="/login" replace />
  if (profileError || !profile) return <ProfileProblem />
  if (profile.role !== role) return <Navigate to={roleHome(profile.role)} replace />
  return children
}

// Log in, sign up and forgot-password are for signed-out people. A signed-in
// person is moved on to their home (or back to the invite page, if that is
// where they came from).
export function PublicOnly({ children }) {
  const { loading, session, profile, profileError, recovery } = useAuth()
  const location = useLocation()
  if (loading) return <Splash />
  if (recovery) return <Navigate to="/reset-password" replace />
  if (!session) return children
  if (profileError || !profile) return <ProfileProblem />
  const backToInvite = location.state?.from === '/invite' && profile.role === 'patient'
  return <Navigate to={backToInvite ? '/invite' : roleHome(profile.role)} replace />
}

// The "/" address: send each person where they belong.
export function HomeRedirect() {
  const { loading, session, profile, profileError, recovery } = useAuth()
  if (loading) return <Splash />
  if (recovery) return <Navigate to="/reset-password" replace />
  if (!session) return <Navigate to="/login" replace />
  if (profileError || !profile) return <ProfileProblem />
  return <Navigate to={roleHome(profile.role)} replace />
}

// Shown under the header when something failed in the background, for example
// the language could not be saved to the profile.
export function AuthNotice() {
  const t = useT()
  const { notice, dismissNotice } = useAuth()
  if (!notice) return null
  const friendly = friendlyError(t, notice.error)
  return (
    <div className="nl-notice">
      <FormError
        error={{ text: `${t('errors:language_not_saved')} ${friendly.text}`, detail: friendly.detail }}
        onDismiss={dismissNotice}
      />
    </div>
  )
}

