// Brand name and tagline are brand identity, not translated copy. They move
// behind i18n keys (en + fil) when the i18n scaffold is added.
export default function Splash() {
  return (
    <main className="splash">
      <img
        className="splash__logo"
        src={`${import.meta.env.BASE_URL}logo.png`}
        alt=""
        width="240"
        height="240"
      />
      <h1 className="splash__name">NurtureLink</h1>
      <p className="splash__tagline">Nurture Lives, Linking Hearts</p>
    </main>
  )
}
