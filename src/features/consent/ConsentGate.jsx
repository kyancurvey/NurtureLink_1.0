import Splash from '../../components/Splash.jsx'
import { Button } from '../../components/ui/index.js'
import AuthLayout from '../auth/AuthLayout.jsx'
import FormError from '../auth/FormError.jsx'
import { useAuth } from '../../lib/auth.jsx'
import { ConsentProvider, useConsent } from '../../lib/consent.jsx'
import { friendlyError } from '../../lib/errors.js'
import { useT } from '../../lib/useT.js'
import ConsentScreen from './ConsentScreen.jsx'

// ---------------------------------------------------------------------------
// THE CONSENT GATE: FOR USABILITY ONLY (like the route guards).
//
// It wraps the patient and provider apps. Until the person has accepted every
// required document at its newest published version, the app behind it is not
// shown, only the consent screen. This is a screen, not a lock: the database
// keeps the proof (consent_records) but does not yet refuse data access without
// consent (PLAN.md, decision 5: app-only enforcement for now, an open item).
//
// It fails closed: while loading, on an error, or when a required document has
// not been published yet, the person does not get in.
// ---------------------------------------------------------------------------

function Gate({ children }) {
  const t = useT()
  const { loaded, error, status, refresh } = useConsent()

  if (!loaded) return <Splash />

  if (error) {
    return (
      <AuthLayout title={t('terms:loadError.title')}>
        <FormError error={friendlyError(t, error)} />
        <Button variant="secondary" full onClick={refresh}>
          {t('errors:retry')}
        </Button>
      </AuthLayout>
    )
  }

  if (!status) return <Splash />

  if (status.unavailable.length > 0) {
    return (
      <AuthLayout title={t('terms:unavailable.title')}>
        <p>{t('terms:unavailable.body')}</p>
        <Button variant="secondary" full onClick={refresh}>
          {t('errors:retry')}
        </Button>
      </AuthLayout>
    )
  }

  if (!status.complete) return <ConsentScreen />
  return children
}

// Admin accounts have no consent screen: they work in the SQL Editor.
export default function ConsentGate({ children }) {
  const { user, profile } = useAuth()
  if (!user || !profile || (profile.role !== 'patient' && profile.role !== 'provider')) return children
  return (
    <ConsentProvider key={user.id}>
      <Gate>{children}</Gate>
    </ConsentProvider>
  )
}
