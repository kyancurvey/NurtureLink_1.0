import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Button, TextField, Toast } from '../../components/ui/index.js'
import { SITE_URL } from '../../lib/authLink.js'
import { friendlyError } from '../../lib/errors.js'
import i18n from '../../lib/i18n.js'
import { supabase } from '../../lib/supabase.js'
import { useT } from '../../lib/useT.js'
import AuthLayout from './AuthLayout.jsx'
import FormError from './FormError.jsx'
import { MIN_PASSWORD, ageFromDob, dobProblem, emailProblem, todayString } from './validate.js'

// Patient sign-up. The account is ALWAYS a patient: the database trigger
// ignores anything else. Only the date of birth and the language are sent as
// extra data; never a role.
export default function SignUpPage() {
  const t = useT()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [dob, setDob] = useState('')
  const [errors, setErrors] = useState({})
  const [formError, setFormError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [sentTo, setSentTo] = useState(null)

  const isMinor = !dobProblem(t, dob) && ageFromDob(dob) < 18

  async function onSubmit(e) {
    e.preventDefault()
    const next = {}
    const emailMsg = emailProblem(t, email)
    if (emailMsg) next.email = emailMsg
    if (!password) next.password = t('errors:password_required')
    else if (password.length < MIN_PASSWORD) next.password = t('errors:password_short')
    const dobMsg = dobProblem(t, dob)
    if (dobMsg) next.dob = dobMsg
    setErrors(next)
    setFormError(null)
    if (Object.keys(next).length > 0) return
    if (!supabase) {
      setFormError({ text: t('errors:not_configured') })
      return
    }
    setBusy(true)
    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: {
        emailRedirectTo: SITE_URL,
        data: { date_of_birth: dob, language: i18n.resolvedLanguage },
      },
    })
    setBusy(false)
    if (error) {
      setFormError(friendlyError(t, error))
      return
    }
    // With "Confirm email" ON there is no session yet: ask them to check their
    // email. (The same message is shown even if the address already has an
    // account, so nobody can use this form to find out who is registered.)
    // With it OFF there is a session, and <PublicOnly> moves the person on.
    if (!data.session) setSentTo(email.trim())
  }

  if (sentTo) {
    return (
      <AuthLayout
        title={t('auth:signup.checkEmail.title')}
        footer={
          <Link className="nl-auth__link" to="/login">
            {t('auth:backToLogin')}
          </Link>
        }
      >
        <Toast variant="success">{t('auth:signup.checkEmail.body', { email: sentTo })}</Toast>
        <p className="nl-auth__note">{t('auth:signup.checkEmail.sameBrowser')}</p>
      </AuthLayout>
    )
  }

  return (
    <AuthLayout
      title={t('auth:signup.title')}
      subtitle={t('auth:signup.subtitle')}
      footer={
        <>
          <Link className="nl-auth__link" to="/login">
            {t('auth:signup.haveAccount')}
          </Link>
          <Link className="nl-auth__link" to="/invite">
            {t('auth:login.haveInvite')}
          </Link>
        </>
      }
    >
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
          hint={t('auth:field.passwordHint')}
          type="password"
          name="new-password"
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          error={errors.password}
        />
        <TextField
          label={t('auth:field.dob')}
          hint={t('auth:field.dobHint')}
          type="date"
          name="dob"
          min="1900-01-01"
          max={todayString()}
          value={dob}
          onChange={(e) => setDob(e.target.value)}
          error={errors.dob}
        />
        {isMinor && <Toast variant="info">{t('auth:signup.minorNote')}</Toast>}
        <FormError error={formError} />
        <Button type="submit" full disabled={busy}>
          {busy ? t('auth:working') : t('auth:signup.submit')}
        </Button>
      </form>
    </AuthLayout>
  )
}
