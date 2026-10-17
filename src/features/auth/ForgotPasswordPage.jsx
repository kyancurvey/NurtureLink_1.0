import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Button, TextField, Toast } from '../../components/ui/index.js'
import { SITE_URL } from '../../lib/authLink.js'
import { friendlyError } from '../../lib/errors.js'
import { supabase } from '../../lib/supabase.js'
import { useT } from '../../lib/useT.js'
import AuthLayout from './AuthLayout.jsx'
import FormError from './FormError.jsx'
import { emailProblem } from './validate.js'

export default function ForgotPasswordPage() {
  const t = useT()
  const [email, setEmail] = useState('')
  const [emailError, setEmailError] = useState(null)
  const [formError, setFormError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [sentTo, setSentTo] = useState(null)

  async function onSubmit(e) {
    e.preventDefault()
    const problem = emailProblem(t, email)
    setEmailError(problem)
    setFormError(null)
    if (problem) return
    if (!supabase) {
      setFormError({ text: t('errors:not_configured') })
      return
    }
    setBusy(true)
    // The link comes back to the site root. supabase-js turns the "?code=" in
    // it into a session and announces PASSWORD_RECOVERY (see auth.jsx), which
    // opens the reset screen.
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: SITE_URL })
    setBusy(false)
    if (error) {
      setFormError(friendlyError(t, error))
      return
    }
    // The same message whether or not the address has an account.
    setSentTo(email.trim())
  }

  const back = (
    <Link className="nl-auth__link" to="/login">
      {t('auth:backToLogin')}
    </Link>
  )

  if (sentTo) {
    return (
      <AuthLayout title={t('auth:forgot.sent.title')} footer={back}>
        <Toast variant="success">{t('auth:forgot.sent.body', { email: sentTo })}</Toast>
        <p className="nl-auth__note">{t('auth:signup.checkEmail.sameBrowser')}</p>
      </AuthLayout>
    )
  }

  return (
    <AuthLayout title={t('auth:forgot.title')} subtitle={t('auth:forgot.subtitle')} footer={back}>
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
          error={emailError}
        />
        <FormError error={formError} />
        <Button type="submit" full disabled={busy}>
          {busy ? t('auth:working') : t('auth:forgot.submit')}
        </Button>
      </form>
    </AuthLayout>
  )
}
