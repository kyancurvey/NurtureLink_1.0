import { Card, InfoIcon } from '../../components/ui/index.js'
import { useT } from '../../lib/useT.js'

// Profile > Help (step 3.5). PLACEHOLDER STRUCTURE ONLY: the user manual and the
// demo videos are not written yet. Nothing here loads anything from the network.
function Placeholder({ title, body }) {
  const t = useT()
  return (
    <section className="nl-profile__placeholder">
      <h3 className="nl-profile__subtitle">{title}</h3>
      <p className="nl-profile__status nl-profile__status--neutral">
        <InfoIcon size={16} />
        <span>{t('patient:profile.comingSoon')}</span>
      </p>
      <p className="nl-profile__muted">{body}</p>
    </section>
  )
}

export default function ProfileHelp() {
  const t = useT()
  return (
    <Card title={t('patient:profile.help.title')}>
      <div className="nl-profile__form">
        <Placeholder title={t('patient:profile.help.manualTitle')} body={t('patient:profile.help.manualBody')} />
        <Placeholder title={t('patient:profile.help.videosTitle')} body={t('patient:profile.help.videosBody')} />
      </div>
    </Card>
  )
}
