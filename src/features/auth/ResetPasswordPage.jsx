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
import { MIN_PASSWORD } from './validate.js'
import { roleHome } from './guards.jsx'

// Opened from the link in the password-reset email. supabase-js has already
// turned the link into a session and AuthProvider has set `recovery`.
export default function ResetPasswordPage() {
  const t = useT()
  const navigate = useNavigate()
  const { loading, session, profile, recovery, finishRecovery } = useAuth()
  const [password, setPassword] = useState('')
  const [passwordError, setPasswordError] = useState(null)
  const [formError, setFormError] = useState(null)
  const [busy, setBusy] = useState(false)

  if (loading) return <Splash />

  if (!recovery) {
    // Signed in without a reset link: nothing to do here. Otherwise the link
    // was not valid (opened in another browser, expired, or typed by hand).
    if (session && profile) return <Navigate to={roleHome(profile.role)} replace />
    return (
      <AuthLayout
        title={t('auth:reset.title')}
        footer={
          <Link className="nl-auth__link" to="/forgot-password">
            {t('auth:reset.requestNew')}
          </Link>
        }
      >
        <Toast variant="warning">{t('auth:reset.invalid')}</Toast>
      </AuthLayout>
    )
  }

  async function onSubmit(e) {
    e.preventDefault()
    setFormError(null)
    let problem = null
    if (!password) problem = t('errors:password_required')
    else if (password.length < MIN_PASSWORD) problem = t('errors:password_short')
    setPasswordError(problem)
    if (problem || !supabase) return
    setBusy(true)
    const { error } = await supabase.auth.updateUser({ password })
    setBusy(false)
    if (error) {
      setFormError(friendlyError(t, error))
      return
    }
    finishRecovery()
    navigate('/', { replace: true })
  }

  return (
    <AuthLayout title={t('auth:reset.title')} subtitle={t('auth:reset.subtitle')}>
      <form className="nl-auth__form" onSubmit={onSubmit} noValidate>
        <TextField
          label={t('auth:field.newPassword')}
          hint={t('auth:field.passwordHint')}
          type="password"
          name="new-password"
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          error={passwordError}
        />
        <FormError error={formError} />
        <Button type="submit" full disabled={busy}>
          {busy ? t('auth:working') : t('auth:reset.submit')}
        </Button>
      </form>
    </AuthLayout>
  )
}
