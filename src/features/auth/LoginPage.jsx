import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Button, TextField, Toast } from '../../components/ui/index.js'
import { useAuth } from '../../lib/auth.jsx'
import { friendlyError } from '../../lib/errors.js'
import { supabase } from '../../lib/supabase.js'
import { useT } from '../../lib/useT.js'
import AuthLayout from './AuthLayout.jsx'
import FormError from './FormError.jsx'
import { emailProblem } from './validate.js'

export default function LoginPage() {
  const t = useT()
  const { linkError, dismissLinkError } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [errors, setErrors] = useState({})
  const [formError, setFormError] = useState(null)
  const [busy, setBusy] = useState(false)

  async function onSubmit(e) {
    e.preventDefault()
    const next = {}
    const emailMsg = emailProblem(t, email)
    if (emailMsg) next.email = emailMsg
    if (!password) next.password = t('errors:password_required')
    setErrors(next)
    setFormError(null)
    if (Object.keys(next).length > 0) return
    if (!supabase) {
      setFormError({ text: t('errors:not_configured') })
      return
    }
    setBusy(true)
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
    setBusy(false)
    if (error) setFormError(friendlyError(t, error))
    // On success the session changes and <PublicOnly> moves the person on.
  }

  return (
    <AuthLayout
      title={t('auth:login.title')}
      subtitle={t('auth:login.subtitle')}
      footer={
        <>
          <Link className="nl-auth__link" to="/forgot-password">
            {t('auth:login.forgot')}
          </Link>
          <Link className="nl-auth__link" to="/signup">
            {t('auth:login.createAccount')}
          </Link>
          <Link className="nl-auth__link" to="/invite">
            {t('auth:login.haveInvite')}
          </Link>
        </>
      }
    >
      {linkError && (
        <Toast variant="warning" onDismiss={dismissLinkError}>
          {linkError === 'expired' ? t('errors:link_expired') : t('errors:link_invalid')}
        </Toast>
      )}
      <form className="nl-auth__form" onSubmit={onSubmit} noValidate>
        <TextField
          label={t('auth:field.email')}
          type="email"
          name="email"
          autoComplete="email"
          inputMode="email"
          autoCapitalize="none"
          spellCheck={false}
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          error={errors.email}
        />
        <TextField
          label={t('auth:field.password')}
          type="password"
          name="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          error={errors.password}
        />
        <FormError error={formError} />
        <Button type="submit" full disabled={busy}>
          {busy ? t('auth:working') : t('auth:login.submit')}
        </Button>
      </form>
    </AuthLayout>
  )
}
