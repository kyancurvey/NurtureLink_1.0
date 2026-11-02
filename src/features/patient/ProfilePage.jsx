import { Link } from 'react-router-dom'
import { Button, Card, LanguageToggle, PageHeader, UserIcon } from '../../components/ui/index.js'
import { useAuth } from '../../lib/auth.jsx'
import { useT } from '../../lib/useT.js'
import '../consent/consent.css'
import DisplayName from './DisplayName.jsx'
import HealthTimeline from './HealthTimeline.jsx'
import PregnancyDetails from './PregnancyDetails.jsx'
import ProfileDevices from './ProfileDevices.jsx'
import ProfileHelp from './ProfileHelp.jsx'
import './profile.css'

// Patient > Profile. Step 3.5 adds pregnancy details, display name, the health
// record timeline, devices (read only), help placeholders and language / log out.
// It keeps the Privacy and consent link (step 2.4) and the provider-invite link
// (step 2.3). The consent flow itself is not touched.
export default function ProfilePage() {
  const t = useT()
  const { signOut } = useAuth()
  return (
    <>
      <PageHeader title={t('patient:tabs.profile')} subtitle={t('patient:profile.intro')} />
      <div className="nl-consent__card-stack nl-profile">
        <PregnancyDetails />
        <DisplayName />
        <HealthTimeline />
        <ProfileDevices />
        <ProfileHelp />
        <Card title={t('patient:profile.account.title')}>
          <div className="nl-profile__form">
            <p className="nl-profile__muted">{t('patient:profile.account.languageHint')}</p>
            <div>
              <LanguageToggle />
            </div>
            <div className="nl-profile__actions">
              <Button variant="secondary" onClick={signOut}>
                {t('auth:logout')}
              </Button>
            </div>
          </div>
        </Card>
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
