import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { supabase } from './supabase.js'
import { useAuth } from './auth.jsx'
import { evaluate } from './consentRules.js'

// ConsentProvider: loads the published documents and the signed-in person's own
// consent records, works out what is still to accept (consentRules.js), and
// offers accept() and withdraw(). Used by the consent gate and by Profile >
// Privacy. Mounted once per signed-in patient or provider (see ConsentGate).
//
// What is stored: one consent_records row per accepted document (user_id and
// document_id; the database fills in accepted_at). Version and language come
// from the linked document. Withdrawing sets withdrawn_at (007 makes it the
// server time). All access rules are in the database (004, 005, 007).

const ConsentContext = createContext(null)

export function useConsent() {
  const ctx = useContext(ConsentContext)
  if (!ctx) throw new Error('useConsent must be used inside <ConsentProvider>')
  return ctx
}

async function loadAll(userId) {
  const [docs, records] = await Promise.all([
    supabase
      .from('consent_documents')
      .select('id, doc_type, version, language, title, body')
      .eq('is_published', true),
    supabase
      .from('consent_records')
      .select('id, accepted_at, withdrawn_at, consent_documents(id, doc_type, version, language, title, body)')
      .eq('user_id', userId)
      .order('accepted_at', { ascending: false }),
  ])
  const error = docs.error || records.error
  if (error) return { error }
  return {
    docs: docs.data ?? [],
    // A record whose document is no longer published has document = null.
    records: (records.data ?? []).map((r) => ({
      id: r.id,
      accepted_at: r.accepted_at,
      withdrawn_at: r.withdrawn_at,
      document: r.consent_documents ?? null,
    })),
  }
}

export function ConsentProvider({ children }) {
  const { user, profile } = useAuth()
  const { i18n } = useTranslation()
  const language = i18n.resolvedLanguage === 'fil' ? 'fil' : 'en'
  const userId = user?.id ?? null

  // Tagged with the user it belongs to, so one person's data is never shown to
  // the next person who signs in on the same page.
  const [state, setState] = useState({ uid: null, docs: [], records: [], error: null })

  const refresh = useCallback(async () => {
    if (!supabase || !userId) return { error: { message: 'not_signed_in' } }
    const out = await loadAll(userId)
    setState((s) =>
      out.error
        ? { uid: userId, docs: s.uid === userId ? s.docs : [], records: s.uid === userId ? s.records : [], error: out.error }
        : { uid: userId, docs: out.docs, records: out.records, error: null },
    )
    return out
  }, [userId])

  // Load when the person signs in (every login and page load re-checks, which
  // is how a newer published version re-prompts automatically).
  useEffect(() => {
    let cancelled = false
    if (!supabase || !userId) return undefined
    loadAll(userId).then((out) => {
      if (cancelled) return
      setState(
        out.error
          ? { uid: userId, docs: [], records: [], error: out.error }
          : { uid: userId, docs: out.docs, records: out.records, error: null },
      )
    })
    return () => {
      cancelled = true
    }
  }, [userId])

  const current = state.uid === userId ? state : null
  const loaded = !!current

  // Insert one record per document id, in ONE statement: all are saved or none.
  // A "23505" (already accepted, for example in another tab) is not a failure
  // for the person: the data is reloaded and the gate re-checks.
  const accept = useCallback(
    async (documentIds) => {
      if (!supabase || !userId || documentIds.length === 0) return { error: null }
      const rows = documentIds.map((document_id) => ({ user_id: userId, document_id }))
      const { error } = await supabase.from('consent_records').insert(rows)
      const reloaded = await refresh()
      if (error && error.code !== '23505') return { error }
      return { error: reloaded.error ?? null }
    },
    [userId, refresh],
  )

  // Withdraw one record. The value sent is replaced by the server's time (007).
  // select('id') lets us see whether a row really changed (0 rows = it was
  // already withdrawn or is not yours).
  const withdraw = useCallback(
    async (recordId) => {
      if (!supabase || !userId) return { error: { message: 'not_signed_in' } }
      const { data, error } = await supabase
        .from('consent_records')
        .update({ withdrawn_at: new Date().toISOString() })
        .eq('id', recordId)
        .is('withdrawn_at', null)
        .select('id')
      const reloaded = await refresh()
      if (error) return { error }
      if (!data || data.length === 0) return { error: { message: 'nothing_changed' } }
      return { error: reloaded.error ?? null }
    },
    [userId, refresh],
  )

  const status = useMemo(
    () =>
      loaded && !current.error && profile
        ? evaluate({
            role: profile.role,
            dateOfBirth: profile.date_of_birth,
            docs: current.docs,
            records: current.records,
            language,
          })
        : null,
    [loaded, current, profile, language],
  )

  const value = useMemo(
    () => ({
      loaded,
      error: current?.error ?? null,
      docs: current?.docs ?? [],
      records: current?.records ?? [],
      status,
      language,
      refresh,
      accept,
      withdraw,
    }),
    [loaded, current, status, language, refresh, accept, withdraw],
  )

  return <ConsentContext.Provider value={value}>{children}</ConsentContext.Provider>
}
