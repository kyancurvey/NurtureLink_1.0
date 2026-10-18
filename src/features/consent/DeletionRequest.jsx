import { useCallback, useEffect, useState } from 'react'
import { Button, CheckCircleIcon, AlertTriangleIcon, InfoIcon, Modal, Toast } from '../../components/ui/index.js'
import FormError from '../auth/FormError.jsx'
import { useAuth } from '../../lib/auth.jsx'
import { formatDateTime } from '../../lib/dates.js'
import { friendlyError } from '../../lib/errors.js'
import { supabase } from '../../lib/supabase.js'
import { useT } from '../../lib/useT.js'
import { useTranslation } from 'react-i18next'

// "Request data deletion" for a patient: shows the latest request and its
// status, and files a new one (a deletion_requests row, patient_id = me, with
// an optional note). The database allows only ONE pending request per patient
// and gives the patient no way to change the status: the project owner handles
// requests in the SQL Editor (docs/ADMIN_SQL.md).
//
// Used on Profile > Privacy and on the consent screen, so a person who has
// withdrawn consent can still ask for their data to be deleted.

const NOTE_MAX = 1000

const STATUS = {
  pending: { icon: <InfoIcon size={20} />, key: 'terms:delete.status.pending' },
  completed: { icon: <CheckCircleIcon size={20} />, key: 'terms:delete.status.completed' },
  declined: { icon: <AlertTriangleIcon size={20} />, key: 'terms:delete.status.declined' },
}

export default function DeletionRequest() {
  const t = useT()
  const { i18n } = useTranslation()
  const { user } = useAuth()
  const userId = user?.id ?? null
  const [latest, setLatest] = useState(null)
  const [loadError, setLoadError] = useState(null)
  const [open, setOpen] = useState(false)
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [sent, setSent] = useState(false)

  const load = useCallback(async () => {
    if (!supabase || !userId) return
    const { data, error: e } = await supabase
      .from('deletion_requests')
      .select('id, status, requested_at')
      .eq('patient_id', userId)
      .order('requested_at', { ascending: false })
      .limit(1)
    if (e) setLoadError(e)
    else {
      setLoadError(null)
      setLatest(data?.[0] ?? null)
    }
  }, [userId])

  useEffect(() => {
    load()
  }, [load])

  async function send() {
    setBusy(true)
    setError(null)
    const trimmed = note.trim()
    const { error: e } = await supabase
      .from('deletion_requests')
      .insert({ patient_id: userId, note: trimmed === '' ? null : trimmed })
    setBusy(false)
    // 23505: a request is already pending (another tab). Not the person's fault.
    if (e && e.code !== '23505') {
      setError(friendlyError(t, e))
      return
    }
    setOpen(false)
    setNote('')
    setSent(!e)
    await load()
  }

  const pending = latest?.status === 'pending'
  const status = latest ? STATUS[latest.status] : null

  return (
    <div className="nl-consent__delete">
      <h3 className="nl-consent__subtitle">{t('terms:delete.title')}</h3>
      <p>{t('terms:delete.body')}</p>

      <FormError error={loadError ? friendlyError(t, loadError) : null} />
      {sent && <Toast variant="success" onDismiss={() => setSent(false)}>{t('terms:delete.sent')}</Toast>}

      {status && (
        <p className="nl-consent__status" role="status">
          {status.icon}
          <span>
            {t(status.key)} {t('terms:delete.requestedOn', { date: formatDateTime(latest.requested_at, i18n.resolvedLanguage) })}
          </span>
        </p>
      )}

      {pending ? (
        <p className="nl-consent__note">{t('terms:delete.pendingNote')}</p>
      ) : (
        <Button variant="secondary" onClick={() => setOpen(true)}>
          {t('terms:delete.button')}
        </Button>
      )}

      <Modal
        open={open}
        onClose={() => !busy && setOpen(false)}
        title={t('terms:delete.modal.title')}
        actions={
          <>
            <Button variant="secondary" onClick={() => setOpen(false)} disabled={busy}>
              {t('terms:delete.modal.cancel')}
            </Button>
            <Button variant="danger" onClick={send} disabled={busy}>
              {busy ? t('terms:saving') : t('terms:delete.modal.confirm')}
            </Button>
          </>
        }
      >
        <p>{t('terms:delete.modal.warning')}</p>
        <div className="nl-field">
          <label htmlFor="nl-delete-note" className="nl-field__label">
            {t('terms:delete.modal.noteLabel')}
          </label>
          <p className="nl-field__hint">{t('terms:delete.modal.noteHint')}</p>
          <textarea
            id="nl-delete-note"
            className="nl-field__input nl-consent__textarea"
            rows={3}
            maxLength={NOTE_MAX}
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
        </div>
        <FormError error={error} />
      </Modal>
    </div>
  )
}
