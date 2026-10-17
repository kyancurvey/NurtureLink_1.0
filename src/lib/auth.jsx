import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from './supabase.js'
import i18n, { LANGUAGES, registerLanguageSaver, setLanguage } from './i18n.js'
import { getLinkError } from './authLink.js'

// AuthProvider: the one place that knows who is signed in.
//
//  - The SESSION comes from supabase-js (it stores, refreshes and clears the
//    token itself). This file never reads or writes a token.
//  - The PROFILE (role, language) is read from the profiles table. The role is
//    never taken from the token or from user_metadata, because a user can edit
//    their own metadata. It comes only from the database.
//
// Components read it with useAuth().

const AuthContext = createContext(null)

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>')
  return ctx
}

// Returns { profile, error }. A missing row is reported as the code 'no_profile'.
async function fetchProfile(userId) {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, role, language, display_name, date_of_birth')
    .eq('id', userId)
    .maybeSingle()
  if (error) return { profile: null, error }
  if (!data) return { profile: null, error: { message: 'no_profile' } }
  return { profile: data, error: null }
}

export function AuthProvider({ children }) {
  const [ready, setReady] = useState(!supabase) // with no Supabase there is nothing to wait for
  const [session, setSession] = useState(null)
  // One object, tagged with the user it belongs to, so a previous user's
  // profile can never be shown to the next person who signs in.
  const [result, setResult] = useState({ uid: null, profile: null, error: null })
  const [recovery, setRecovery] = useState(false) // opened a password-reset link
  const [linkError, setLinkError] = useState(getLinkError) // expired or invalid email link
  const [notice, setNotice] = useState(null) // an error to show (for example language not saved)
  const syncedFor = useRef(null) // user whose language was already applied

  const userId = session?.user?.id ?? null

  // 1. Session. getSession() waits for supabase-js to finish reading the URL
  // (the "?code=" of an email link) and the stored session. Do not call
  // supabase inside the listener itself; it can deadlock. Only set state.
  useEffect(() => {
    if (!supabase) return undefined
    let gotEvent = false
    const { data } = supabase.auth.onAuthStateChange((event, next) => {
      gotEvent = true
      setSession(next)
      setReady(true)
      if (event === 'PASSWORD_RECOVERY') setRecovery(true)
      if (event === 'SIGNED_OUT') setRecovery(false)
    })
    supabase.auth.getSession().then(({ data: current }) => {
      if (!gotEvent) setSession(current.session)
      setReady(true)
    })
    return () => data.subscription.unsubscribe()
  }, [])

  // 2. Profile, whenever the signed-in user changes.
  useEffect(() => {
    if (!supabase || !userId) return undefined
    let cancelled = false
    fetchProfile(userId).then(({ profile, error }) => {
      if (!cancelled) setResult({ uid: userId, profile, error })
    })
    return () => {
      cancelled = true
    }
  }, [userId])

  const current = result.uid === userId ? result : null
  const profile = current?.profile ?? null
  const profileError = current?.error ?? null
  const loading = !ready || (!!userId && !current)

  // Used after a role change (redeeming an invite) and by "Try again".
  const refreshProfile = useCallback(async () => {
    if (!supabase || !userId) return { profile: null, error: { message: 'not_signed_in' } }
    const out = await fetchProfile(userId)
    setResult({ uid: userId, ...out })
    return out
  }, [userId])

  // 3. Language. The profile wins when it has a usable language; otherwise the
  // language on screen is saved to the profile. Done once per signed-in user.
  useEffect(() => {
    if (!userId) {
      syncedFor.current = null
      return
    }
    if (!profile || syncedFor.current === profile.id) return
    syncedFor.current = profile.id
    if (LANGUAGES.includes(profile.language)) {
      if (profile.language !== i18n.resolvedLanguage) setLanguage(profile.language, { saveToProfile: false })
    } else {
      saveLanguage(i18n.resolvedLanguage)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [profile, userId])

  // Saves the language through set_my_language (migration 002). That function
  // changes only profiles.language, so the app needs no update right on the table.
  async function saveLanguage(code) {
    if (!supabase) return
    const { error } = await supabase.rpc('set_my_language', { p_language: code })
    if (error) {
      setNotice({ kind: 'language', error })
    } else {
      setResult((r) => (r.profile ? { ...r, profile: { ...r.profile, language: code } } : r))
    }
  }

  // Let the language switch (setLanguage in i18n.js) save to the profile.
  const profileId = profile?.id ?? null
  useEffect(() => {
    if (!profileId) return undefined
    return registerLanguageSaver(saveLanguage)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [profileId])

  const signOut = useCallback(async () => {
    if (!supabase) return
    // 'local' signs out this device only, not the person's other devices.
    await supabase.auth.signOut({ scope: 'local' })
  }, [])

  const value = useMemo(
    () => ({
      configured: !!supabase,
      loading,
      session,
      user: session?.user ?? null,
      profile,
      role: profile?.role ?? null,
      profileError,
      refreshProfile,
      signOut,
      recovery,
      finishRecovery: () => setRecovery(false),
      linkError,
      dismissLinkError: () => setLinkError(null),
      notice,
      dismissNotice: () => setNotice(null),
    }),
    [loading, session, profile, profileError, refreshProfile, signOut, recovery, linkError, notice],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
