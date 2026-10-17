import LanguageToggle from '../ui/LanguageToggle.jsx'

// Slim top bar rendered once in App.jsx, above every route, so the language
// switch is on every screen (splash, login, Terms and so on).
export default function AppHeader() {
  return (
    <header className="nl-appheader">
      <LanguageToggle />
    </header>
  )
}
