import { useT } from '../lib/useT.js'

export default function Splash() {
  const t = useT()
  return (
    <main className="splash">
      <img
        className="splash__logo"
        src={`${import.meta.env.BASE_URL}logo.png`}
        alt=""
        width="240"
        height="240"
      />
      <h1 className="splash__name">{t('brand.name')}</h1>
      <p className="splash__tagline">{t('brand.tagline')}</p>
    </main>
  )
}
