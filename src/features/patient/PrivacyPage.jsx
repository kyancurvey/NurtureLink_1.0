import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import {
  AlertTriangleIcon,
  Button,
  Card,
  CheckCircleIcon,
  ChevronLeftIcon,
  Modal,
  PageHeader,
  Toast,
} from '../../components/ui/index.js'
import FormError from '../auth/FormError.jsx'
import DeletionRequest from '../consent/DeletionRequest.jsx'
import { DOC, pickDocument } from '../../lib/consentRules.js'
import { useConsent } from '../../lib/consent.jsx'
import { formatDateTime } from '../../lib/dates.js'
import { friendlyError } from '../../lib/errors.js'
import { useT } from '../../lib/useT.js'
import { buildConsentFile, downloadTextFile } from './consentFile.js'
import '../consent/consent.css'

// Patient > Profile > Privacy: see what you accepted, download a copy, withdraw
// a consent, and ask for your data to be deleted. Everything here is the
// person's own data; the database allows nothing else (RLS, migration 005).

const REQUIRED_TYPES = new Set([DOC.TERMS, DOC.PRIVACY, DOC.CONSENT, DOC.DISCLAIMER, DOC.GUARDIAN, DOC.PROVIDER])

function RecordRow({ record, language, onWithdraw }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  const d = record.document
  const active = !record.withdrawn_at
  const when = (v) => formatDateTime(v, language)
  const textId = `nl-rec-${record.id}`

  return (
    <li className="nl-consent__row">
      <h3 className="nl-consent__title">{d?.title ?? t('patient:privacy.file.unknownDocument')}</h3>
      {d && (
        <p className="nl-consent__meta">
          {t('patient:privacy.record.meta', {
            version: d.version,
            language: t(`language.name.${d.language}`),
            date: when(record.accepted_at),
          })}
        </p>
      )}
      <p className="nl-consent__status">
        {active ? <CheckCircleIcon size={20} /> : <AlertTriangleIcon size={20} />}
        <span>
          {active
            ? t('patient:privacy.record.active')
            : t('patient:privacy.record.withdrawnOn', { date: when(record.withdrawn_at) })}
        </span>
      </p>
      <div className="nl-consent__actions">
        <button
          type="button"
          className="nl-consent__toggle"
          aria-expanded={open}
          aria-controls={textId}
          onClick={() => setOpen((v) => !v)}
        >
          <span className={open ? 'nl-consent__chev nl-consent__chev--open' : 'nl-consent__chev'}>
            <ChevronLeftIcon />
          </span>
          {open ? t('terms:item.hide') : t('terms:item.read')}
        </button>
        {active && d && (
          <Button variant="secondary" onClick={() => onWithdraw(record)}>
            {t('patient:privacy.withdraw.button')}
          </Button>
        )}
      </div>
      <div id={textId} className="nl-consent__text" hidden={!open} tabIndex={0} role="region" aria-label={d?.title}>
        {d?.body ?? t('patient:privacy.record.textUnavailable')}
      </div>
    </li>
  )
}

export default function PrivacyPage() {
  const t = useT()
  const { i18n } = useTranslation()
  const { loaded, error, records, docs, language, accept, withdraw, refresh } = useConsent()
  const [target, setTarget] = useState(null) // the record being withdrawn
  const [busy, setBusy] = useState(false)
  const [actionError, setActionError] = useState(null)
  const [done, setDone] = useState(null) // 'withdrawn' | 'studyAccepted'
  const [studyOpen, setStudyOpen] = useState(false)

  const active = records.filter((r) => !r.withdrawn_at)
  const history = records.filter((r) => r.withdrawn_at)
  const studyActive = active.some((r) => r.document?.doc_type === DOC.STUDY)

  // The newest published study text in the person's language, for opting in later.
  const studyVersion = docs.filter((d) => d.doc_type === DOC.STUDY).reduce((m, d) => Math.max(m, d.version), 0)
  const study = studyVersion > 0 ? pickDocument(docs, DOC.STUDY, studyVersion, language).doc : null

  async function confirmWithdraw() {
    setBusy(true)
    setActionError(null)
    const { error: e } = await withdraw(target.id)
    setBusy(false)
    if (e) {
      setActionError(
        e.message === 'nothing_changed'
          ? { text: t('patient:privacy.withdraw.nothingChanged') }
          : friendlyError(t, e),
      )
      return
    }
    setTarget(null)
    setDone('withdrawn')
    // A withdrawn REQUIRED consent: the gate takes over and shows the consent screen.
  }

  async function giveStudyConsent() {
    setBusy(true)
    setActionError(null)
    const { error: e } = await accept([study.id])
    setBusy(false)
    if (e) {
      setActionError(friendlyError(t, e))
      return
    }
    setStudyOpen(false)
    setDone('studyAccepted')
  }

  function download() {
    const text = buildConsentFile({ t, records, language: i18n.resolvedLanguage })
    const stamp = new Date().toISOString().slice(0, 10)
    downloadTextFile(`nurturelink-consents-${stamp}.txt`, text)
  }

  const targetIsRequired = target?.document ? REQUIRED_TYPES.has(target.document.doc_type) : true

  return (
    <>
      <PageHeader title={t('patient:privacy.title')} subtitle={t('patient:privacy.subtitle')} />
      <p>
        <Link className="nl-auth__link" to="/patient/profile">
          <ChevronLeftIcon />
          {t('patient:privacy.backToProfile')}
        </Link>
      </p>

      {done === 'withdrawn' && <Toast variant="success" onDismiss={() => setDone(null)}>{t('patient:privacy.withdraw.done')}</Toast>}
      {done === 'studyAccepted' && <Toast variant="success" onDismiss={() => setDone(null)}>{t('patient:privacy.study.done')}</Toast>}
      {actionError && !target && !studyOpen && <FormError error={actionError} onDismiss={() => setActionError(null)} />}

      <div className="nl-consent__card-stack">
        <Card title={t('patient:privacy.accepted.title')}>
          {!loaded ? (
            <p>{t('patient:privacy.loading')}</p>
          ) : error ? (
            <>
              <FormError error={friendlyError(t, error)} />
              <Button variant="secondary" onClick={refresh}>{t('errors:retry')}</Button>
            </>
          ) : active.length === 0 ? (
            <p>{t('patient:privacy.accepted.empty')}</p>
          ) : (
            <ul className="nl-consent__list">
              {active.map((r) => (
                <RecordRow key={r.id} record={r} language={i18n.resolvedLanguage} onWithdraw={(rec) => { setActionError(null); setTarget(rec) }} />
              ))}
            </ul>
          )}
        </Card>

        {loaded && !error && !studyActive && study && (
          <Card title={t('patient:privacy.study.title')}>
            <p>{t('patient:privacy.study.off')}</p>
            <p className="nl-consent__note">{study.title}</p>
            <Button variant="secondary" onClick={() => { setActionError(null); setStudyOpen(true) }}>
              {t('patient:privacy.study.button')}
            </Button>
          </Card>
        )}

        {history.length > 0 && (
          <Card title={t('patient:privacy.history.title')}>
            <ul className="nl-consent__list">
              {history.map((r) => (
                <RecordRow key={r.id} record={r} language={i18n.resolvedLanguage} onWithdraw={() => {}} />
              ))}
            </ul>
          </Card>
        )}

        <Card title={t('patient:privacy.download.title')}>
          <p>{t('patient:privacy.download.body')}</p>
          <Button variant="secondary" onClick={download} disabled={!loaded || !!error}>
            {t('patient:privacy.download.button')}
          </Button>
        </Card>

        <Card>
          <DeletionRequest />
        </Card>
      </div>

      <p className="nl-disclaimer">{t('disclaimer')}</p>

      <Modal
        open={!!target}
        onClose={() => !busy && setTarget(null)}
        title={t('patient:privacy.withdraw.title')}
        actions={
          <>
            <Button variant="secondary" onClick={() => setTarget(null)} disabled={busy}>
              {t('patient:privacy.withdraw.cancel')}
            </Button>
            <Button variant="danger" onClick={confirmWithdraw} disabled={busy}>
              {busy ? t('terms:saving') : t('patient:privacy.withdraw.confirm')}
            </Button>
          </>
        }
      >
        <p><strong>{target?.document?.title}</strong></p>
        <p>{targetIsRequired ? t('patient:privacy.withdraw.warningRequired') : t('patient:privacy.withdraw.warningStudy')}</p>
        <FormError error={actionError} />
      </Modal>

      <Modal
        open={studyOpen}
        onClose={() => !busy && setStudyOpen(false)}
        title={study?.title ?? ''}
        actions={
          <>
            <Button variant="secondary" onClick={() => setStudyOpen(false)} disabled={busy}>
              {t('patient:privacy.study.cancel')}
            </Button>
            <Button onClick={giveStudyConsent} disabled={busy}>
              {busy ? t('terms:saving') : t('patient:privacy.study.confirm')}
            </Button>
          </>
        }
      >
        <div className="nl-consent__text" tabIndex={0} role="region" aria-label={study?.title}>{study?.body}</div>
        <FormError error={actionError} />
      </Modal>
    </>
  )
}
