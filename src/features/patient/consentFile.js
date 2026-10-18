import { formatDateTime } from '../../lib/dates.js'

// Builds the plain-text copy of a person's consent history for download.
// Everything is created on the device from data the person already loaded; no
// extra server call. `t` is the translation function, so the file follows the
// person's current language. The document text is kept in the language it was
// accepted in, exactly as it was shown (it may still be a DRAFT).
export function buildConsentFile({ t, records, language, now = new Date() }) {
  const line = '-'.repeat(60)
  const out = []
  out.push(t('patient:privacy.file.title'))
  out.push(t('patient:privacy.file.created', { date: formatDateTime(now, language) }))
  out.push(t('patient:privacy.file.draftNote'))
  out.push('')
  if (records.length === 0) out.push(t('patient:privacy.file.none'))

  records.forEach((r, i) => {
    const d = r.document
    out.push(line)
    out.push(`${i + 1}. ${d?.title ?? t('patient:privacy.file.unknownDocument')}`)
    if (d) {
      out.push(`${t('patient:privacy.file.type')}: ${d.doc_type}`)
      out.push(`${t('patient:privacy.file.version')}: ${d.version}`)
      out.push(`${t('patient:privacy.file.language')}: ${t(`language.name.${d.language}`)}`)
    }
    out.push(`${t('patient:privacy.file.accepted')}: ${r.accepted_at} (${formatDateTime(r.accepted_at, language)})`)
    out.push(
      r.withdrawn_at
        ? `${t('patient:privacy.file.withdrawn')}: ${r.withdrawn_at} (${formatDateTime(r.withdrawn_at, language)})`
        : `${t('patient:privacy.file.status')}: ${t('patient:privacy.file.active')}`,
    )
    out.push('')
    out.push(d?.body ?? t('patient:privacy.record.textUnavailable'))
    out.push('')
  })
  out.push(line)
  return out.join('\n')
}

// Starts a download in the browser. The object URL is released straight after.
export function downloadTextFile(filename, text) {
  const blob = new Blob([text], { type: 'text/plain;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
