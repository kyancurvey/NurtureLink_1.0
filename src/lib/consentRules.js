// The rules of the consent gate, as plain functions (no React, no Supabase), so
// they are easy to read and to test. NOT security: the database stores the
// proof of what a person accepted; this only decides which screen to show.
//
// Document types match consent_documents.doc_type (migration 001). Note the
// optional study item is stored as 'study_data_use'.

export const DOC = {
  TERMS: 'terms_of_use',
  PRIVACY: 'privacy_notice',
  CONSENT: 'informed_consent',
  DISCLAIMER: 'medical_disclaimer',
  GUARDIAN: 'guardian_assent',
  STUDY: 'study_data_use',
  PROVIDER: 'provider_confidentiality',
}

// Order here is the order on screen.
const PATIENT_REQUIRED = [DOC.TERMS, DOC.PRIVACY, DOC.CONSENT, DOC.DISCLAIMER]
const PROVIDER_REQUIRED = [DOC.PROVIDER, DOC.TERMS, DOC.PRIVACY]

// A patient with no date of birth on file is treated as a minor: asking for a
// guardian by mistake is safer than skipping it by mistake. Sign-up asks for a
// date of birth, so this is rare (the signup trigger drops an invalid date).
export function isMinor(dateOfBirth, now = new Date()) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateOfBirth ?? ''))
  if (!match) return true
  const [, y, m, d] = match.map(Number)
  const eighteenth = new Date(y + 18, m - 1, d)
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  return today < eighteenth
}

// Required and optional document types for a person, in display order.
// Admin accounts have no consent screen (they work in the SQL Editor).
export function typesFor(role, dateOfBirth, now = new Date()) {
  if (role === 'patient') {
    const required = [...PATIENT_REQUIRED]
    if (isMinor(dateOfBirth, now)) required.push(DOC.GUARDIAN)
    return { required, optional: [DOC.STUDY] }
  }
  if (role === 'provider') return { required: [...PROVIDER_REQUIRED], optional: [] }
  return { required: [], optional: [] }
}

// Newest published version of a type. Languages share one version number.
function latestVersion(docs, type) {
  let latest = 0
  for (const d of docs) if (d.doc_type === type && d.version > latest) latest = d.version
  return latest
}

// The text to show for a type at a version: the person's language, else
// English, else whatever exists. `fallback` is true when it is not their language.
export function pickDocument(docs, type, version, language) {
  const same = docs.filter((d) => d.doc_type === type && d.version === version)
  const exact = same.find((d) => d.language === language)
  if (exact) return { doc: exact, fallback: false }
  const english = same.find((d) => d.language === 'en')
  const doc = english ?? same[0] ?? null
  return { doc, fallback: !!doc }
}

// records: [{ id, accepted_at, withdrawn_at, document: { doc_type, version, ... } | null }]
// docs:    published documents [{ id, doc_type, version, language, title, body }]
//
// Returns:
//   complete     true when every required item is accepted at its newest version
//   unavailable  required types that have no published text yet (blocks, fail closed)
//   items        what the screen must show, in order: { type, required, doc, fallback, updated }
//                (optional items appear only while the screen is showing anyway)
//
// A record counts when it is active (not withdrawn) and its document is of that
// type at the newest version. Language does not matter: a person who accepted
// the English text and then switches to Filipino has still accepted version N.
export function evaluate({ role, dateOfBirth, docs, records, language, now = new Date() }) {
  const { required, optional } = typesFor(role, dateOfBirth, now)
  const unavailable = []
  const pendingRequired = []
  const pendingOptional = []

  const needs = (type, isRequired) => {
    const version = latestVersion(docs, type)
    if (version === 0) {
      if (isRequired) unavailable.push(type)
      return
    }
    const has = (r) => r.document?.doc_type === type
    const accepted = records.some((r) => !r.withdrawn_at && has(r) && r.document.version >= version)
    if (accepted) return
    const { doc, fallback } = pickDocument(docs, type, version, language)
    if (!doc) return
    const updated = records.some((r) => has(r) && r.document.version < version)
    const item = { type, required: isRequired, doc, fallback, updated }
    ;(isRequired ? pendingRequired : pendingOptional).push(item)
  }

  required.forEach((type) => needs(type, true))
  optional.forEach((type) => needs(type, false))

  const complete = unavailable.length === 0 && pendingRequired.length === 0
  const items = complete ? [] : [...pendingRequired, ...pendingOptional]
  return { complete, unavailable, items }
}
