import { useState } from 'react'
import { Link, Navigate, useNavigate } from 'react-router-dom'
import Splash from '../../components/Splash.jsx'
import { Button, TextField, Toast } from '../../components/ui/index.js'
import { useAuth } from '../../lib/auth.jsx'
import { friendlyError } from '../../lib/errors.js'
import { supabase } from '../../lib/supabase.js'
import { useT } from '../../lib/useT.js'
import AuthLayout from './AuthLayout.jsx'
import FormError from './FormError.jsx'

// Provider invite. The person first has a normal (patient) account, then types
// the code they were given. redeem_provider_invite (migration 002) is the only
// way an account becomes a provider: the server checks the code and changes the
// role. The app never sends a role.
export default function InvitePage() {
  const t = useT()
  const navigate = useNavigate()
  const { loading, session, profile, refreshProfile } = useAuth()
  const [code, setCode] = useState('')
  const [codeError, setCodeError] = useState(null)
  const [formError, setFormError] = useState(null)
  const [busy, setBusy] = useState(false)

  if (loading) return <Splash />

  // Not signed in yet: send them to sign up or log in, then back here.
  if (!session) {
    return (
      <AuthLayout title={t('auth:invite.title')}>
        <Toast variant="info">{t('auth:invite.needAccount')}</Toast>
        <div className="nl-auth__form">
          <Button full onClick={() => navigate('/signup', { state: { from: '/invite' } })}>
            {t('auth:login.createAccount')}
          </Button>
          <Button variant="secondary" full onClick={() => navigate('/login', { state: { from: '/invite' } })}>
            {t('auth:login.submit')}
          </Button>
        </div>
      </AuthLayout>
    )
  }

  if (profile?.role === 'provider') return <Navigate to="/provider" replace />

  if (profile && profile.role !== 'patient') {
    return (
      <AuthLayout title={t('auth:invite.title')}>
        <Toast variant="info">{t('errors:not_eligible')}</Toast>
      </AuthLayout>
    )
  }

  async function onSubmit(e) {
    e.preventDefault()
    setFormError(null)
    const clean = code.trim()
    setCodeError(clean ? null : t('errors:code_required'))
    if (!clean || !supabase) return
    setBusy(true)
    const { error } = await supabase.rpc('redeem_provider_invite', { p_code: clean })
    if (error) {
      setBusy(false)
      setFormError(friendlyError(t, error))
      return
    }
    // The role changed in the database. Read the profile again so the app sees
    // it, then go to the provider dashboard.
    const { profile: fresh, error: readError } = await refreshProfile()
    setBusy(false)
    if (readError) setFormError(friendlyError(t, readError))
    else if (fresh?.role === 'provider') navigate('/provider', { replace: true })
  }

  return (
    <AuthLayout
      title={t('auth:invite.title')}
      subtitle={t('auth:invite.subtitle')}
      footer={
        <Link className="nl-auth__link" to="/patient">
          {t('auth:invite.notNow')}
        </Link>
      }
    >
      <form className="nl-auth__form" onSubmit={onSubmit} noValidate>
        <TextField
          label={t('auth:field.code')}
          name="invite-code"
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          value={code}
          onChange={(e) => setCode(e.target.value.toUpperCase())}
          error={codeError}
        />
        <FormError error={formError} />
        <Button type="submit" full disabled={busy}>
          {busy ? t('auth:working') : t('auth:invite.submit')}
        </Button>
      </form>
    </AuthLayout>
  )
}
