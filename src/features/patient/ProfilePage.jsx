import { Link } from 'react-router-dom'
import { Card, ChevronLeftIcon, PageHeader, UserIcon } from '../../components/ui/index.js'
import { useT } from '../../lib/useT.js'
import '../consent/consent.css'

// Patient > Profile. Pregnancy details, health timeline, device pairing and
// manuals come in Phase 3; for now it links to Privacy and consent (step 2.4)
// and keeps the provider-invite link from step 2.3.
export default function ProfilePage() {
  const t = useT()
  return (
    <>
      <PageHeader title={t('patient:tabs.profile')} />
      <div className="nl-consent__card-stack">
        <Card>
          <Link className="nl-consent__linkcard" to="/patient/profile/privacy">
            <UserIcon size={24} />
            <span>
              {t('patient:profile.privacyLink')}
              <br />
              <small className="nl-consent__meta">{t('patient:profile.privacyHint')}</small>
            </span>
          </Link>
        </Card>
        <Card>
          <Link className="nl-auth__link" to="/invite">
            {t('auth:login.haveInvite')}
          </Link>
        </Card>
      </div>
      <p className="nl-disclaimer">{t('disclaimer')}</p>
    </>
  )
}
